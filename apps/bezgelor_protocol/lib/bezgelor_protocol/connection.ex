defmodule BezgelorProtocol.Connection do
  @compile {:no_warn_undefined, [BezgelorWorld.Quest.SessionQuestManager, BezgelorWorld.Quest.QuestPersistence, BezgelorWorld.WorldManager, BezgelorWorld.VisibilityBroadcaster]}

  @moduledoc """
  GenServer handling a single client TCP connection.

  ## Overview

  Each connected client gets a dedicated Connection process that:
  - Receives data from the socket
  - Assembles packets from the data stream
  - Decrypts packets when encryption is enabled
  - Dispatches packets to handlers
  - Encrypts and sends outgoing packets

  ## Connection Types

  - `:auth` - Auth server connection (sends ConnectionType=3)
  - `:world` - World server connection (sends ConnectionType=11)

  ## State Machine

  1. `connected` - Initial state, sends ServerHello
  2. `authenticating` - Awaiting client authentication
  3. `authenticated` - Client is authenticated
  4. `disconnected` - Connection closed

  ## Ranch Protocol

  This module implements the Ranch protocol behaviour for TCP connections.
  """

  use GenServer
  require Logger

  alias BezgelorProtocol.{Framing, Opcode, PacketWriter}
  alias BezgelorCrypto.PacketCrypt
  alias BezgelorDb.Characters
  alias BezgelorWorld.Quest.{QuestPersistence, SessionQuestManager}

  @behaviour :ranch_protocol

  # Persist dirty quests every 30 seconds
  @quest_persist_interval 30_000

  # ServerHello packet protocol constants (WildStar specific)
  @auth_version 16042
  @default_realm_id 1
  @default_realm_group_id 21
  @auth_message 0x97998A0
  @connection_type_world 11
  @connection_type_auth 3

  defstruct [
    :socket,
    :transport,
    :connection_type,
    :buffer,
    :encryption,
    :state,
    :session_data,
    :quest_persist_timer
  ]

  @type connection_type :: :auth | :world
  @type connection_state :: :connected | :authenticating | :authenticated | :disconnected

  @type t :: %__MODULE__{
          socket: :inet.socket(),
          transport: module(),
          connection_type: connection_type(),
          buffer: binary(),
          encryption: PacketCrypt.t() | nil,
          state: connection_state(),
          session_data: map()
        }

  # Ranch protocol callback
  @impl :ranch_protocol
  def start_link(ref, transport, opts) do
    pid = :proc_lib.spawn_link(__MODULE__, :ranch_init, [{ref, transport, opts}])
    {:ok, pid}
  end

  # GenServer init - not used since we use Ranch's spawn_link pattern
  @impl GenServer
  def init(_), do: {:stop, :not_used}

  @doc false
  def ranch_init({ref, transport, opts}) do
    {:ok, socket} = :ranch.handshake(ref)
    :ok = transport.setopts(socket, [{:active, :once}])

    connection_type = Keyword.get(opts, :connection_type, :auth)
    {:ok, {client_ip, client_port}} = :inet.peername(socket)
    client_addr = "#{:inet.ntoa(client_ip)}:#{client_port}"

    # Set connection ID for log tracing across sessions
    conn_id = generate_conn_id(client_port)
    Logger.metadata(conn_id: conn_id)

    Logger.info("[#{server_name(connection_type)}] New connection from #{client_addr}")

    state = %__MODULE__{
      socket: socket,
      transport: transport,
      connection_type: connection_type,
      buffer: <<>>,
      encryption: nil,
      state: :connected,
      session_data: %{
        active_quests: %{},
        completed_quest_ids: MapSet.new(),
        quest_dirty: false,
        client_addr: client_addr
      }
    }

    # Initialize encryption with auth build key
    auth_key = PacketCrypt.key_from_auth_build()
    encryption = PacketCrypt.new(auth_key)
    state = %{state | encryption: encryption}

    # Send ServerHello
    state = send_server_hello(state)

    :gen_server.enter_loop(__MODULE__, [], state)
  end

  @impl GenServer
  def handle_info({:tcp, socket, data}, %{socket: socket, buffer: buffer} = state) do
    # Re-enable active mode
    state.transport.setopts(socket, [{:active, :once}])

    # Append to buffer and parse packets
    new_buffer = buffer <> data
    state = %{state | buffer: new_buffer}

    case process_buffer(state) do
      {:ok, state} ->
        {:noreply, state}

      {:error, reason} ->
        Logger.warning("Packet processing error: #{inspect(reason)}")
        {:stop, :normal, state}
    end
  end

  def handle_info({:tcp_closed, socket}, %{socket: socket} = state) do
    Logger.debug("[#{server_name(state.connection_type)}] Connection closed by client (#{state.session_data[:client_addr]})")
    {:stop, :normal, %{state | state: :disconnected}}
  end

  def handle_info({:tcp_error, socket, reason}, %{socket: socket} = state) do
    Logger.warning("[#{server_name(state.connection_type)}] TCP error: #{inspect(reason)} (#{state.session_data[:client_addr]})")
    {:stop, :normal, %{state | state: :disconnected}}
  end

  # Handle game events for quest progress tracking
  def handle_info({:game_event, event_type, event_data}, state) do
    {session_data, packets} = SessionQuestManager.process_game_event(
      state.session_data,
      event_type,
      event_data
    )

    # Send any generated packets to client
    state = %{state | session_data: session_data}

    state =
      Enum.reduce(packets, state, fn {opcode, packet_data}, acc ->
        do_send_packet(acc, opcode, packet_data)
      end)

    {:noreply, state}
  end

  # Periodic quest persistence timer
  def handle_info(:persist_quests, state) do
    state = persist_dirty_quests(state)
    # Schedule next persistence
    timer = Process.send_after(self(), :persist_quests, @quest_persist_interval)
    {:noreply, %{state | quest_persist_timer: timer}}
  end

  # Schedule persistence timer when entering world (only if not already scheduled)
  def handle_info(:schedule_quest_persistence, state) do
    if is_nil(state.quest_persist_timer) do
      timer = Process.send_after(self(), :persist_quests, @quest_persist_interval)
      {:noreply, %{state | quest_persist_timer: timer}}
    else
      {:noreply, state}
    end
  end

  # Handle packets sent as structs (from handlers like AchievementHandler)
  def handle_info({:send_packet, packet}, state) when is_struct(packet) do
    # Get opcode from packet module
    opcode = packet.__struct__.opcode()

    # Encode packet
    writer = PacketWriter.new()
    {:ok, writer} = packet.__struct__.write(packet, writer)
    payload = PacketWriter.to_binary(writer)

    state = do_send_encrypted_world_packet(state, opcode, payload)
    {:noreply, state}
  end

  # Public API

  @doc "Send a packet to the client."
  @spec send_packet(pid(), atom(), binary()) :: :ok
  def send_packet(pid, opcode, payload) do
    GenServer.cast(pid, {:send_packet, opcode, payload})
  end

  @impl GenServer
  def handle_cast({:send_packet, opcode, payload}, state) do
    state = do_send_packet(state, opcode, payload)
    {:noreply, state}
  end

  # Private functions

  defp send_server_hello(state) do
    # Build ServerHello packet matching NexusForever's format exactly.
    # IMPORTANT: NexusForever writes ALL values as continuous bits with NO byte alignment.
    # After writing ConnectionType (5 bits), AuthMessage continues from bit 5, not a new byte.
    connection_type_value =
      if state.connection_type == :world, do: @connection_type_world, else: @connection_type_auth

    # Write all fields as bits to match NexusForever's GamePacketWriter behavior
    writer = PacketWriter.new()
    |> PacketWriter.write_bits(@auth_version, 32)
    |> PacketWriter.write_bits(@default_realm_id, 32)
    |> PacketWriter.write_bits(@default_realm_group_id, 32)
    |> PacketWriter.write_bits(0, 32)         # RealmGroupEnum (unused)
    |> PacketWriter.write_bits(0, 64)         # StartupTime (unused)
    |> PacketWriter.write_bits(0, 16)         # ListenPort (unused)
    |> PacketWriter.write_bits(connection_type_value, 5)
    |> PacketWriter.write_bits(@auth_message, 32)
    |> PacketWriter.write_bits(0, 32)         # ProcessId (unused)
    |> PacketWriter.write_bits(0, 64)         # ProcessCreationTime (unused)
    |> PacketWriter.write_bits(0, 32)         # Unused
    |> PacketWriter.flush_bits()

    payload = PacketWriter.to_binary(writer)

    # World server sends ServerHello encrypted with ServerRealmEncrypted wrapper
    # Auth/Realm servers send unencrypted
    if state.connection_type == :world do
      do_send_encrypted_world_packet(state, :server_hello, payload)
    else
      do_send_packet(state, :server_hello, payload)
    end
  end

  defp do_send_packet(%{socket: socket, transport: transport, connection_type: conn_type} = state, opcode, payload) do
    opcode_int = if is_atom(opcode), do: Opcode.to_integer(opcode), else: opcode
    packet = Framing.frame_packet(opcode_int, payload)

    case transport.send(socket, packet) do
      :ok ->
        Logger.debug("[#{server_name(conn_type)}] Sent: #{Opcode.name(opcode)} (#{byte_size(payload)} bytes)")
        state

      {:error, reason} ->
        Logger.warning("[#{server_name(conn_type)}] Failed to send packet: #{inspect(reason)}")
        state
    end
  end

  # Send an encrypted packet wrapped in ServerRealmEncrypted (world server).
  # Uses opcode 0x03DC instead of 0x0076.
  defp do_send_encrypted_world_packet(%{state: :disconnected} = state, _opcode, _payload), do: state

  defp do_send_encrypted_world_packet(%{socket: socket, transport: transport, connection_type: conn_type, encryption: encryption} = state, opcode, payload) do
    opcode_int = if is_atom(opcode), do: Opcode.to_integer(opcode), else: opcode

    # Build inner packet: opcode (16 bits) + payload
    inner = PacketWriter.new()
    |> PacketWriter.write_bits(opcode_int, 16)
    |> PacketWriter.write_bytes(payload)
    |> PacketWriter.flush_bits()
    |> PacketWriter.to_binary()

    # Encrypt the inner packet
    case PacketCrypt.encrypt(encryption, inner) do
      {:ok, encrypted} ->
        # Build ServerRealmEncrypted payload: size (data length + 4) + encrypted data
        encrypted_payload = PacketWriter.new()
        |> PacketWriter.write_bits(byte_size(encrypted) + 4, 32)
        |> PacketWriter.write_bytes(encrypted)
        |> PacketWriter.flush_bits()
        |> PacketWriter.to_binary()

        # Frame with ServerRealmEncrypted opcode (0x03DC) for world server
        packet = Framing.frame_packet(Opcode.to_integer(:server_realm_encrypted), encrypted_payload)

        case transport.send(socket, packet) do
          :ok ->
            Logger.debug("[#{server_name(conn_type)}] Sent encrypted (world): #{Opcode.name(opcode)} (#{byte_size(payload)} bytes)")
            state

          {:error, reason} ->
            handle_send_error(state, reason)
        end

      {:error, reason} ->
        Logger.error("[#{server_name(conn_type)}] Encryption failed for #{Opcode.name(opcode)}: #{inspect(reason)}")
        state
    end
  end

  # Send an encrypted packet wrapped in ServerAuthEncrypted (realm server).
  # This is used for realm server packets that need encryption.
  # The inner packet (opcode + payload) is encrypted with PacketCrypt,
  # then wrapped in a ServerAuthEncrypted container.
  defp do_send_encrypted_packet(%{state: :disconnected} = state, _opcode, _payload), do: state

  defp do_send_encrypted_packet(%{socket: socket, transport: transport, connection_type: conn_type, encryption: encryption} = state, opcode, payload) do
    opcode_int = if is_atom(opcode), do: Opcode.to_integer(opcode), else: opcode

    # Build inner packet: opcode (16 bits) + payload
    inner = PacketWriter.new()
    |> PacketWriter.write_bits(opcode_int, 16)
    |> PacketWriter.write_bytes(payload)
    |> PacketWriter.flush_bits()
    |> PacketWriter.to_binary()

    # Encrypt the inner packet
    case PacketCrypt.encrypt(encryption, inner) do
      {:ok, encrypted} ->
        # Build ServerAuthEncrypted payload: size (data length + 4) + encrypted data
        # The +4 accounts for the size field itself
        encrypted_payload = PacketWriter.new()
        |> PacketWriter.write_bits(byte_size(encrypted) + 4, 32)
        |> PacketWriter.write_bytes(encrypted)
        |> PacketWriter.flush_bits()
        |> PacketWriter.to_binary()

        # Frame with ServerAuthEncrypted opcode (0x0076)
        packet = Framing.frame_packet(Opcode.to_integer(:server_auth_encrypted), encrypted_payload)

        case transport.send(socket, packet) do
          :ok ->
            Logger.debug("[#{server_name(conn_type)}] Sent encrypted: #{Opcode.name(opcode)} (#{byte_size(payload)} bytes)")
            state

          {:error, reason} ->
            handle_send_error(state, reason)
        end

      {:error, reason} ->
        Logger.error("[#{server_name(conn_type)}] Encryption failed for #{Opcode.name(opcode)}: #{inspect(reason)}")
        state
    end
  end

  # Handle send errors - mark connection as dead for fatal errors to prevent log floods
  defp handle_send_error(%{connection_type: conn_type} = state, reason) do
    case reason do
      fatal when fatal in [:enotconn, :closed, :econnreset, :epipe, :etimedout] ->
        # Only log once for fatal errors, mark as disconnected
        if state.state != :disconnected do
          Logger.warning("[#{server_name(conn_type)}] Connection lost: #{inspect(reason)}")
        end
        %{state | state: :disconnected}

      _ ->
        Logger.warning("[#{server_name(conn_type)}] Failed to send packet: #{inspect(reason)}")
        state
    end
  end

  defp process_buffer(%{buffer: buffer} = state) do
    case Framing.parse_packets(buffer) do
      {:ok, packets, remaining} ->
        state = %{state | buffer: remaining}
        process_packets(packets, state)
    end
  end

  defp process_packets([], state), do: {:ok, state}

  defp process_packets([{opcode, payload} | rest], state) do
    case handle_packet(opcode, payload, state) do
      {:ok, state} ->
        process_packets(rest, state)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_packet(opcode, payload, state) do
    start_time = System.monotonic_time(:microsecond)

    case Opcode.from_integer(opcode) do
      {:ok, opcode_atom} ->
        # Skip logging outer encrypted packet wrapper - inner handler logs the actual opcode
        unless opcode_atom in [:client_encrypted, :client_packed_world] do
          Logger.debug("[#{server_name(state.connection_type)}] Recv: #{Opcode.name(opcode_atom)} (#{byte_size(payload)} bytes)")
        end
        result = dispatch_to_handler(opcode_atom, payload, state, start_time)
        result

      {:error, :unknown_opcode} ->
        Logger.warning("[#{server_name(state.connection_type)}] Unknown opcode: 0x#{Integer.to_string(opcode, 16)}")
        {:ok, state}
    end
  end

  # Wrapper opcodes that log inner content - suppress outer logging
  @wrapper_opcodes [:client_encrypted, :client_packed_world]

  defp dispatch_to_handler(opcode_atom, payload, state, start_time) do
    alias BezgelorProtocol.PacketRegistry

    case PacketRegistry.lookup(opcode_atom) do
      nil ->
        Logger.debug("[#{server_name(state.connection_type)}] No handler for #{Opcode.name(opcode_atom)}")
        {:ok, state}

      handler ->
        result = handler.handle(payload, state)
        elapsed_us = System.monotonic_time(:microsecond) - start_time
        elapsed_ms = elapsed_us / 1000

        # Skip logging for wrapper packets (inner handler logs the actual opcode)
        log_handler_result? = opcode_atom not in @wrapper_opcodes

        case result do
          {:ok, new_state} ->
            if log_handler_result? do
              Logger.debug("[#{server_name(state.connection_type)}] Handled #{Opcode.name(opcode_atom)} in #{Float.round(elapsed_ms, 2)}ms")
            end
            {:ok, new_state}

          {:reply, reply_opcode, reply_payload, new_state} ->
            do_send_packet(%{state | session_data: new_state.session_data}, reply_opcode, reply_payload)
            Logger.debug("[#{server_name(state.connection_type)}] #{Opcode.name(opcode_atom)} -> #{Opcode.name(reply_opcode)} in #{Float.round(elapsed_ms, 2)}ms")
            {:ok, new_state}

          {:reply_encrypted, reply_opcode, reply_payload, new_state} ->
            # Send encrypted packet (for realm server)
            do_send_encrypted_packet(%{state | session_data: new_state.session_data}, reply_opcode, reply_payload)
            Logger.debug("[#{server_name(state.connection_type)}] #{Opcode.name(opcode_atom)} -> #{Opcode.name(reply_opcode)} (encrypted) in #{Float.round(elapsed_ms, 2)}ms")
            {:ok, new_state}

          {:reply_multi, responses, new_state} ->
            # Send multiple packets in sequence
            updated_state = %{state | session_data: new_state.session_data}
            Enum.each(responses, fn {op, pl} ->
              do_send_packet(updated_state, op, pl)
            end)
            Logger.debug("[#{server_name(state.connection_type)}] #{Opcode.name(opcode_atom)} -> #{length(responses)} packets in #{Float.round(elapsed_ms, 2)}ms")
            {:ok, new_state}

          {:reply_multi_encrypted, responses, new_state} ->
            # Send multiple encrypted packets in sequence (for realm server)
            updated_state = %{state | session_data: new_state.session_data}
            Enum.each(responses, fn {op, pl} ->
              do_send_encrypted_packet(updated_state, op, pl)
            end)
            Logger.debug("[#{server_name(state.connection_type)}] #{Opcode.name(opcode_atom)} -> #{length(responses)} encrypted packets in #{Float.round(elapsed_ms, 2)}ms")
            {:ok, new_state}

          {:reply_world_encrypted, reply_opcode, reply_payload, new_state} ->
            # Send encrypted packet using ServerRealmEncrypted (for world server)
            do_send_encrypted_world_packet(%{state | session_data: new_state.session_data}, reply_opcode, reply_payload)
            Logger.debug("[#{server_name(state.connection_type)}] #{Opcode.name(opcode_atom)} -> #{Opcode.name(reply_opcode)} (world encrypted) in #{Float.round(elapsed_ms, 2)}ms")
            {:ok, new_state}

          {:reply_multi_world_encrypted, responses, new_state} ->
            # Send multiple encrypted packets using ServerRealmEncrypted (for world server)
            updated_state = %{state | session_data: new_state.session_data}
            Enum.each(responses, fn {op, pl} ->
              do_send_encrypted_world_packet(updated_state, op, pl)
            end)
            Logger.debug("[#{server_name(state.connection_type)}] #{Opcode.name(opcode_atom)} -> #{length(responses)} world encrypted packets in #{Float.round(elapsed_ms, 2)}ms")
            {:ok, new_state}

          {:error, reason} ->
            Logger.warning("[#{server_name(state.connection_type)}] Handler error for #{Opcode.name(opcode_atom)}: #{inspect(reason)} (#{Float.round(elapsed_ms, 2)}ms)")
            {:error, reason}
        end
    end
  end

  # Terminate callback - persist quests and position on disconnect, clean up handlers
  @impl GenServer
  def terminate(_reason, state) do
    # Cancel the persistence timer if running
    if state.quest_persist_timer do
      Process.cancel_timer(state.quest_persist_timer)
    end

    # Stop achievement handler if running
    if handler = get_in(state.session_data, [:achievement_handler]) do
      GenServer.stop(handler, :normal)
    end

    # Persist any dirty quests before shutdown
    character = get_in(state.session_data, [:character])

    if character && character.id do
      QuestPersistence.persist_on_logout(character.id, state.session_data)
      persist_position_on_logout(character, state.session_data)
    end

    # Broadcast player despawn and unregister session for multiplayer
    broadcast_player_despawn(state)

    :ok
  end

  # Broadcast player despawn to other players and unregister from WorldManager
  defp broadcast_player_despawn(state) do
    entity_guid = get_in(state.session_data, [:entity_guid])
    zone_id = get_in(state.session_data, [:zone_id])
    instance_id = get_in(state.session_data, [:instance_id]) || 1
    account_id = get_in(state.session_data, [:account_id])

    # Broadcast despawn to other players in the zone
    if entity_guid && zone_id do
      BezgelorWorld.VisibilityBroadcaster.broadcast_player_despawn(
        entity_guid,
        zone_id,
        instance_id,
        :disconnect
      )
    end

    # Unregister session from WorldManager
    if account_id do
      BezgelorWorld.WorldManager.unregister_session(account_id)
    end
  end

  # Persist dirty quests and return updated state
  defp persist_dirty_quests(state) do
    character = get_in(state.session_data, [:character])

    if character && character.id do
      {:ok, _success_count, _failure_count, updated_session_data} =
        QuestPersistence.persist_dirty_quests(character.id, state.session_data)

      %{state | session_data: updated_session_data}
    else
      state
    end
  end

  # Persist character position on logout
  defp persist_position_on_logout(character, session_data) do
    entity = session_data[:entity]
    zone_id = session_data[:zone_id]
    world_id = session_data[:world_id]

    # Only persist if we have valid entity position data
    if entity && entity.position do
      {x, y, z} = entity.position

      {rot_x, rot_y, rot_z} =
        case entity.rotation do
          {rx, ry, rz} -> {rx, ry, rz}
          _ -> {0.0, 0.0, 0.0}
        end

      position_attrs = %{
        location_x: x,
        location_y: y,
        location_z: z,
        rotation_x: rot_x,
        rotation_y: rot_y,
        rotation_z: rot_z,
        world_zone_id: zone_id,
        world_id: world_id
      }

      case Characters.update_position(character, position_attrs) do
        {:ok, _} ->
          Logger.debug("Saved position for character #{character.id} at logout: #{inspect({x, y, z})}")
          :ok

        {:error, reason} ->
          Logger.error("Failed to save position for character #{character.id}: #{inspect(reason)}")
          :ok
      end
    else
      :ok
    end
  end

  # Helper to get human-readable server name for logging
  defp server_name(:auth), do: "Auth"
  defp server_name(:realm), do: "Realm"
  defp server_name(:world), do: "World"
  defp server_name(other), do: "#{other}"

  # Generate a short connection ID for log tracing
  # Format: port + 3-char random suffix (e.g., "52341abc")
  defp generate_conn_id(port) do
    suffix = :crypto.strong_rand_bytes(2) |> Base.encode16(case: :lower) |> binary_part(0, 3)
    "#{port}#{suffix}"
  end
end
