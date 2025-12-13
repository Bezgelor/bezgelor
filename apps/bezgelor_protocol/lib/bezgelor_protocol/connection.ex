defmodule BezgelorProtocol.Connection do
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
  alias BezgelorWorld.Quest.{QuestPersistence, SessionQuestManager}

  @behaviour :ranch_protocol

  # Persist dirty quests every 30 seconds
  @quest_persist_interval 30_000

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
        quest_dirty: false
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
    Logger.debug("Connection closed by client")
    {:stop, :normal, %{state | state: :disconnected}}
  end

  def handle_info({:tcp_error, socket, reason}, %{socket: socket} = state) do
    Logger.warning("TCP error: #{inspect(reason)}")
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
    # Build ServerHello packet
    # AuthVersion = 16042, RealmId = 1, etc.
    connection_type_value = if state.connection_type == :auth, do: 3, else: 11

    writer = PacketWriter.new()
    |> PacketWriter.write_uint32(16042)  # AuthVersion
    |> PacketWriter.write_uint32(1)      # RealmId
    |> PacketWriter.write_uint32(1)      # RealmGroupId
    |> PacketWriter.write_uint32(0x97998A0)  # AuthMessage
    |> PacketWriter.write_bits(connection_type_value, 5)  # ConnectionType
    |> PacketWriter.write_bits(0, 11)    # Unused bits to align
    |> PacketWriter.flush_bits()

    payload = PacketWriter.to_binary(writer)
    do_send_packet(state, :server_hello, payload)
  end

  defp do_send_packet(%{socket: socket, transport: transport} = state, opcode, payload) do
    opcode_int = if is_atom(opcode), do: Opcode.to_integer(opcode), else: opcode
    packet = Framing.frame_packet(opcode_int, payload)

    case transport.send(socket, packet) do
      :ok ->
        Logger.debug("Sent packet: #{Opcode.name(opcode)} (#{byte_size(payload)} bytes)")
        state

      {:error, reason} ->
        Logger.warning("Failed to send packet: #{inspect(reason)}")
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
    alias BezgelorProtocol.PacketRegistry

    case Opcode.from_integer(opcode) do
      {:ok, opcode_atom} ->
        Logger.debug("Received packet: #{Opcode.name(opcode_atom)} (#{byte_size(payload)} bytes)")
        dispatch_to_handler(opcode_atom, payload, state)

      {:error, :unknown_opcode} ->
        Logger.warning("Unknown opcode: 0x#{Integer.to_string(opcode, 16)}")
        {:ok, state}
    end
  end

  defp dispatch_to_handler(opcode_atom, payload, state) do
    alias BezgelorProtocol.PacketRegistry

    case PacketRegistry.lookup(opcode_atom) do
      nil ->
        Logger.debug("No handler registered for #{Opcode.name(opcode_atom)}")
        {:ok, state}

      handler ->
        case handler.handle(payload, state) do
          {:ok, new_state} ->
            {:ok, new_state}

          {:reply, reply_opcode, reply_payload, new_state} ->
            do_send_packet(%{state | session_data: new_state.session_data}, reply_opcode, reply_payload)
            {:ok, new_state}

          {:reply_multi, responses, new_state} ->
            # Send multiple packets in sequence
            updated_state = %{state | session_data: new_state.session_data}
            Enum.each(responses, fn {opcode, payload} ->
              do_send_packet(updated_state, opcode, payload)
            end)
            {:ok, new_state}

          {:error, reason} ->
            Logger.warning("Handler error for #{Opcode.name(opcode_atom)}: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  # Terminate callback - persist quests on disconnect and clean up handlers
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
    end

    :ok
  end

  # Persist dirty quests and return updated state
  defp persist_dirty_quests(state) do
    character = get_in(state.session_data, [:character])

    if character && character.id do
      case QuestPersistence.persist_dirty_quests(character.id, state.session_data) do
        {:ok, _count, updated_session_data} ->
          %{state | session_data: updated_session_data}

        {:error, _reason} ->
          state
      end
    else
      state
    end
  end
end
