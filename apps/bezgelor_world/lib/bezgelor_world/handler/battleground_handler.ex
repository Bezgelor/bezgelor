defmodule BezgelorWorld.Handler.BattlegroundHandler do
  @moduledoc """
  Handles battleground-related packets from clients.

  Processes:
  - Queue join/leave requests
  - Queue status queries
  - Ready confirmation
  - Match interactions (kills, objectives)
  """

  # Suppress type warnings for packet parsing case clauses
  @dialyzer {:nowarn_function, handle: 2}

  @behaviour BezgelorProtocol.Handler

  require Logger

  alias BezgelorProtocol.PacketReader
  alias BezgelorProtocol.PacketWriter
  alias BezgelorWorld.PvP.BattlegroundQueue
  alias BezgelorWorld.PvP.BattlegroundInstance

  # Client packet opcodes (from client_battleground_*.ex packets)
  @opcode_join_queue 0x0B01
  @opcode_leave_queue 0x0B02
  @opcode_queue_status 0x0B03
  @opcode_confirm_ready 0x0B04
  @opcode_report_kill 0x0B05
  @opcode_interact_objective 0x0B06

  @impl true
  def handle(payload, state) do
    reader = PacketReader.new(payload)
    {:ok, opcode, reader} = PacketReader.read_uint16(reader)

    result =
      case opcode do
        @opcode_join_queue -> handle_join_queue(reader, state)
        @opcode_leave_queue -> handle_leave_queue(reader, state)
        @opcode_queue_status -> handle_queue_status(reader, state)
        @opcode_confirm_ready -> handle_confirm_ready(reader, state)
        @opcode_report_kill -> handle_report_kill(reader, state)
        @opcode_interact_objective -> handle_interact_objective(reader, state)
        _ -> {:error, :unknown_opcode}
      end

    case result do
      {:ok, _packets, _state} = success -> success
      {:error, reason} -> {:error, reason}
    end
  end

  # Handler implementations

  defp handle_join_queue(reader, state) do
    {:ok, battleground_id, _reader} = PacketReader.read_uint32(reader)

    # Get player info from connection state
    player_guid = Map.get(state, :character_guid, 0)
    player_name = Map.get(state, :character_name, "Unknown")
    faction = Map.get(state, :faction, :exile)
    level = Map.get(state, :level, 50)
    class_id = Map.get(state, :class_id, 1)

    case BattlegroundQueue.join_queue(player_guid, player_name, faction, level, class_id, battleground_id) do
      {:ok, estimated_wait} ->
        Logger.debug("Player #{player_name} joined BG queue #{battleground_id}")
        packet = build_queue_joined_packet(battleground_id, estimated_wait)
        {:ok, [packet], state}

      {:error, :already_in_queue} ->
        packet = build_queue_error_packet(:already_in_queue)
        {:ok, [packet], state}

      {:error, :invalid_battleground} ->
        packet = build_queue_error_packet(:invalid_battleground)
        {:ok, [packet], state}

      {:error, reason} ->
        Logger.warning("Failed to join BG queue: #{inspect(reason)}")
        packet = build_queue_error_packet(reason)
        {:ok, [packet], state}
    end
  end

  defp handle_leave_queue(_reader, state) do
    player_guid = Map.get(state, :character_guid, 0)

    case BattlegroundQueue.leave_queue(player_guid) do
      :ok ->
        Logger.debug("Player #{player_guid} left BG queue")
        packet = build_queue_left_packet()
        {:ok, [packet], state}

      {:error, :not_in_queue} ->
        packet = build_queue_error_packet(:not_in_queue)
        {:ok, [packet], state}
    end
  end

  defp handle_queue_status(_reader, state) do
    player_guid = Map.get(state, :character_guid, 0)

    case BattlegroundQueue.get_queue_status(player_guid) do
      {:ok, status} ->
        packet = build_queue_status_packet(status)
        {:ok, [packet], state}

      {:error, :not_in_queue} ->
        packet = build_not_in_queue_packet()
        {:ok, [packet], state}
    end
  end

  defp handle_confirm_ready(_reader, state) do
    player_guid = Map.get(state, :character_guid, 0)

    case BattlegroundQueue.confirm_ready(player_guid) do
      :ok ->
        packet = build_ready_confirmed_packet()
        {:ok, [packet], state}

      {:error, reason} ->
        packet = build_queue_error_packet(reason)
        {:ok, [packet], state}
    end
  end

  defp handle_report_kill(reader, state) do
    {:ok, victim_guid, _reader} = PacketReader.read_uint64(reader)

    player_guid = Map.get(state, :character_guid, 0)
    match_id = Map.get(state, :battleground_match_id)

    if match_id do
      case BattlegroundInstance.report_kill(match_id, player_guid, victim_guid) do
        :ok -> {:ok, [], state}
        {:error, _reason} -> {:ok, [], state}
      end
    else
      {:ok, [], state}
    end
  end

  defp handle_interact_objective(reader, state) do
    {:ok, objective_id, _reader} = PacketReader.read_uint32(reader)

    player_guid = Map.get(state, :character_guid, 0)
    match_id = Map.get(state, :battleground_match_id)

    if match_id do
      case BattlegroundInstance.interact_objective(match_id, player_guid, objective_id) do
        :ok ->
          packet = build_objective_update_packet(match_id, objective_id)
          {:ok, [packet], state}

        {:error, reason} ->
          Logger.debug("Objective interaction failed: #{inspect(reason)}")
          {:ok, [], state}
      end
    else
      {:ok, [], state}
    end
  end

  # Packet builders

  defp build_queue_joined_packet(battleground_id, estimated_wait) do
    PacketWriter.new()
    |> PacketWriter.write_uint16(0x0B81)  # Server opcode for queue joined
    |> PacketWriter.write_uint32(battleground_id)
    |> PacketWriter.write_uint32(estimated_wait)
    |> PacketWriter.write_byte(1)  # Success
    |> PacketWriter.to_binary()
  end

  defp build_queue_left_packet do
    PacketWriter.new()
    |> PacketWriter.write_uint16(0x0B82)  # Server opcode for queue left
    |> PacketWriter.write_byte(1)  # Success
    |> PacketWriter.to_binary()
  end

  defp build_queue_status_packet(status) do
    PacketWriter.new()
    |> PacketWriter.write_uint16(0x0B83)  # Server opcode for queue status
    |> PacketWriter.write_uint32(status.battleground_id)
    |> PacketWriter.write_uint32(status.wait_time_seconds)
    |> PacketWriter.write_uint32(status.estimated_wait)
    |> PacketWriter.write_uint32(status.position)
    |> PacketWriter.write_byte(faction_to_int(status.faction))
    |> PacketWriter.to_binary()
  end

  defp build_not_in_queue_packet do
    PacketWriter.new()
    |> PacketWriter.write_uint16(0x0B83)  # Server opcode for queue status
    |> PacketWriter.write_uint32(0)  # No battleground
    |> PacketWriter.write_uint32(0)  # No wait time
    |> PacketWriter.write_uint32(0)  # No estimated wait
    |> PacketWriter.write_uint32(0)  # No position
    |> PacketWriter.write_byte(0)  # No faction
    |> PacketWriter.to_binary()
  end

  defp build_ready_confirmed_packet do
    PacketWriter.new()
    |> PacketWriter.write_uint16(0x0B84)  # Server opcode for ready confirmed
    |> PacketWriter.write_byte(1)  # Success
    |> PacketWriter.to_binary()
  end

  defp build_queue_error_packet(reason) do
    error_code =
      case reason do
        :already_in_queue -> 1
        :invalid_battleground -> 2
        :not_in_queue -> 3
        :level_too_low -> 4
        _ -> 255
      end

    PacketWriter.new()
    |> PacketWriter.write_uint16(0x0B85)  # Server opcode for queue error
    |> PacketWriter.write_byte(error_code)
    |> PacketWriter.to_binary()
  end

  defp build_objective_update_packet(match_id, objective_id) do
    # Get current match state for objective data
    case BattlegroundInstance.get_state(match_id) do
      {:ok, match_state} ->
        objective = Enum.find(match_state.objectives, fn o -> o.id == objective_id end)

        if objective do
          PacketWriter.new()
          |> PacketWriter.write_uint16(0x0B86)  # Server opcode for objective update
          |> PacketWriter.write_uint32(objective_id)
          |> PacketWriter.write_byte(owner_to_int(objective.owner))
          |> PacketWriter.write_float32(objective.progress)
          |> PacketWriter.to_binary()
        else
          <<>>
        end

      {:error, _} ->
        <<>>
    end
  end

  defp faction_to_int(:exile), do: 1
  defp faction_to_int(:dominion), do: 2
  defp faction_to_int(_), do: 0

  defp owner_to_int(:neutral), do: 0
  defp owner_to_int(:exile), do: 1
  defp owner_to_int(:dominion), do: 2
  defp owner_to_int(_), do: 0

  # Public helper for combat integration

  @doc """
  Called by CombatHandler when a kill occurs in a battleground.
  Returns true if the kill was in a battleground context.
  """
  @spec report_battleground_kill(String.t() | nil, non_neg_integer(), non_neg_integer()) :: boolean()
  def report_battleground_kill(nil, _killer_guid, _victim_guid), do: false

  def report_battleground_kill(match_id, killer_guid, victim_guid) do
    case BattlegroundInstance.report_kill(match_id, killer_guid, victim_guid) do
      :ok -> true
      {:error, _} -> false
    end
  end

  @doc """
  Get match state for a player's current battleground.
  """
  @spec get_player_match(String.t() | nil) :: {:ok, map()} | {:error, :not_found}
  def get_player_match(nil), do: {:error, :not_found}

  def get_player_match(match_id) do
    BattlegroundInstance.get_state(match_id)
  end
end
