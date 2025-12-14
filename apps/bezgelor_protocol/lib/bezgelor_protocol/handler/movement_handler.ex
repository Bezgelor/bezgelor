defmodule BezgelorProtocol.Handler.MovementHandler do
  @moduledoc """
  Handler for ClientMovement packets.

  Updates character position and broadcasts to nearby players.
  Position updates are throttled to reduce database writes.

  ## Flow

  1. Parse movement packet
  2. Validate player is in world
  3. Update entity position in memory
  4. Periodically persist to database
  5. Broadcast to nearby players (future)
  """

  @behaviour BezgelorProtocol.Handler
  @compile {:no_warn_undefined, [BezgelorWorld.TriggerManager, BezgelorWorld.EventDispatcher]}

  alias BezgelorProtocol.Packets.World.ClientMovement
  alias BezgelorProtocol.PacketReader
  alias BezgelorDb.Characters
  alias BezgelorCore.Entity

  require Logger

  # Minimum time between database position saves (milliseconds)
  @position_save_interval_ms 5000

  @impl true
  def handle(payload, state) do
    reader = PacketReader.new(payload)

    case ClientMovement.read(reader) do
      {:ok, packet, _reader} ->
        process_movement(packet, state)

      {:error, reason} ->
        Logger.warning("Failed to parse ClientMovement: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp process_movement(packet, state) do
    unless state.session_data[:in_world] do
      Logger.warning("Movement received before player entered world")
      {:error, :not_in_world}
    else
      do_process_movement(packet, state)
    end
  end

  defp do_process_movement(packet, state) do
    entity = state.session_data[:entity]
    character_id = state.session_data[:character_id]

    # Get old position before update
    old_position = if entity, do: entity.position, else: {0.0, 0.0, 0.0}

    # Update entity position in memory
    new_position = ClientMovement.position(packet)
    new_rotation = ClientMovement.rotation(packet)
    updated_entity = Entity.update_position(entity, new_position, new_rotation)

    # Update state
    state = put_in(state.session_data[:entity], updated_entity)

    # Throttle database saves
    state = maybe_save_position(character_id, packet, state)

    # Check trigger volumes for area-based objectives
    state = check_trigger_volumes(old_position, new_position, state)

    {:ok, state}
  end

  # Check if player entered any trigger volumes
  defp check_trigger_volumes(old_position, new_position, state) do
    triggers = state.session_data[:zone_triggers] || []
    active_triggers = state.session_data[:active_triggers] || MapSet.new()

    if triggers == [] do
      state
    else
      alias BezgelorWorld.TriggerManager

      {entered, _exited, new_active} =
        TriggerManager.check_triggers(triggers, old_position, new_position, active_triggers)

      state = put_in(state.session_data[:active_triggers], new_active)

      # Fire events for entered triggers
      if entered != [] do
        zone_id = state.session_data[:zone_id] || 0
        fire_trigger_events(entered, zone_id, state)
      else
        state
      end
    end
  end

  defp fire_trigger_events([], _zone_id, state), do: state

  defp fire_trigger_events([trigger_id | rest], zone_id, state) do
    alias BezgelorWorld.EventDispatcher

    Logger.info("Player entered trigger #{trigger_id} in zone #{zone_id}")

    # Dispatch enter_area event for quest objectives
    {updated_session, _packets} =
      EventDispatcher.dispatch_enter_area(state.session_data, trigger_id, zone_id)

    state = %{state | session_data: updated_session}

    fire_trigger_events(rest, zone_id, state)
  end

  # Throttle database position saves
  defp maybe_save_position(character_id, packet, state) do
    now = System.monotonic_time(:millisecond)
    last_save = state.session_data[:last_position_save] || 0

    if now - last_save >= @position_save_interval_ms do
      save_position(character_id, packet)
      put_in(state.session_data[:last_position_save], now)
    else
      state
    end
  end

  defp save_position(character_id, packet) do
    case Characters.get_character(character_id) do
      nil ->
        Logger.warning("Character #{character_id} not found for position update")
        :ok

      character ->
        position_attrs = %{
          location_x: packet.position_x,
          location_y: packet.position_y,
          location_z: packet.position_z,
          rotation_x: packet.rotation_x,
          rotation_y: packet.rotation_y,
          rotation_z: packet.rotation_z
        }

        case Characters.update_position(character, position_attrs) do
          {:ok, _} ->
            :ok

          {:error, reason} ->
            Logger.warning("Failed to save position for character #{character_id}: #{inspect(reason)}")
            :ok
        end
    end
  end
end
