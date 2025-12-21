defmodule BezgelorWorld.Handler.EventHandler do
  @moduledoc """
  Handles public event participation and contribution packets.

  ## Packets Handled
  - ClientEventJoin - Join an active public event
  - ClientEventLeave - Leave a public event
  - ClientEventListRequest - Request list of active events in zone
  - ClientEventContribute - Report contribution to event objective

  ## Packets Sent
  - ServerEventList - List of active events in zone
  - ServerEventStart - Event started notification
  - ServerEventUpdate - Event progress update
  - ServerEventComplete - Event completion notification
  """

  @behaviour BezgelorProtocol.Handler

  require Logger

  alias BezgelorProtocol.PacketReader
  alias BezgelorProtocol.PacketWriter

  alias BezgelorProtocol.Packets.World.{
    ClientEventJoin,
    ClientEventLeave,
    ClientEventListRequest,
    ClientEventContribute,
    ServerEventList,
    ServerEventUpdate
  }

  alias BezgelorWorld.EventManager

  @impl true
  def handle(payload, state) do
    reader = PacketReader.new(payload)

    with {:error, _} <- try_join(reader, state),
         {:error, _} <- try_leave(reader, state),
         {:error, _} <- try_list_request(reader, state),
         {:error, _} <- try_contribute(reader, state) do
      {:error, :unknown_event_packet}
    end
  end

  # Join Event

  defp try_join(reader, state) do
    case ClientEventJoin.read(reader) do
      {:ok, packet, _} -> handle_join(packet, state)
      error -> error
    end
  end

  defp handle_join(packet, state) do
    character_id = state.session_data[:character_id]
    zone_id = state.session_data[:zone_id]
    instance_id = state.session_data[:zone_instance_id] || 1

    manager = EventManager.via_tuple(zone_id, instance_id)

    case GenServer.whereis(manager) do
      nil ->
        Logger.warning("No EventManager for zone #{zone_id}:#{instance_id}")
        {:error, :no_event_manager}

      _pid ->
        case EventManager.join_event(manager, packet.instance_id, character_id) do
          :ok ->
            Logger.debug("Character #{character_id} joined event #{packet.instance_id}")

            # Send event updates to the player (one per objective)
            case EventManager.get_event(manager, packet.instance_id) do
              {:ok, event_state} ->
                send_event_updates(packet.instance_id, event_state, state)

              _ ->
                {:ok, state}
            end

          {:error, reason} ->
            Logger.debug("Failed to join event #{packet.instance_id}: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  # Leave Event

  defp try_leave(reader, state) do
    case ClientEventLeave.read(reader) do
      {:ok, packet, _} -> handle_leave(packet, state)
      error -> error
    end
  end

  defp handle_leave(packet, state) do
    character_id = state.session_data[:character_id]
    zone_id = state.session_data[:zone_id]
    instance_id = state.session_data[:zone_instance_id] || 1

    manager = EventManager.via_tuple(zone_id, instance_id)

    case GenServer.whereis(manager) do
      nil ->
        {:ok, state}

      _pid ->
        EventManager.leave_event(manager, packet.instance_id, character_id)
        Logger.debug("Character #{character_id} left event #{packet.instance_id}")
        {:ok, state}
    end
  end

  # List Events

  defp try_list_request(reader, state) do
    case ClientEventListRequest.read(reader) do
      {:ok, _packet, _} -> handle_list_request(state)
      error -> error
    end
  end

  defp handle_list_request(state) do
    character_id = state.session_data[:character_id]
    zone_id = state.session_data[:zone_id]
    instance_id = state.session_data[:zone_instance_id] || 1

    manager = EventManager.via_tuple(zone_id, instance_id)

    events =
      case GenServer.whereis(manager) do
        nil ->
          []

        _pid ->
          EventManager.list_events(manager)
      end

    Logger.debug("Character #{character_id} requested event list, found #{length(events)} events")

    response = build_event_list(events)
    send_response(:server_event_list, response, state)
  end

  # Contribute to Event

  defp try_contribute(reader, state) do
    case ClientEventContribute.read(reader) do
      {:ok, packet, _} -> handle_contribute(packet, state)
      error -> error
    end
  end

  defp handle_contribute(packet, state) do
    character_id = state.session_data[:character_id]
    zone_id = state.session_data[:zone_id]
    instance_id = state.session_data[:zone_instance_id] || 1

    manager = EventManager.via_tuple(zone_id, instance_id)

    case GenServer.whereis(manager) do
      nil ->
        {:error, :no_event_manager}

      _pid ->
        # Handle item-based contribution (turn-in)
        if packet.item_id do
          # TODO: Verify player has item and consume it
          Logger.debug(
            "Character #{character_id} contributing #{packet.amount} of item #{packet.item_id}"
          )
        end

        # Record contribution
        case EventManager.track_contribution(
               manager,
               packet.instance_id,
               character_id,
               packet.amount
             ) do
          {:ok, _participant} ->
            # Send updated event state (one packet per objective)
            case EventManager.get_event(manager, packet.instance_id) do
              {:ok, event_state} ->
                send_event_updates(packet.instance_id, event_state, state)

              _ ->
                {:ok, state}
            end

          {:error, reason} ->
            Logger.debug(
              "Failed to contribute to event #{packet.instance_id}: #{inspect(reason)}"
            )

            {:error, reason}
        end
    end
  end

  # Response Building

  defp build_event_list(events) do
    event_entries =
      Enum.map(events, fn event ->
        %{
          instance_id: event.instance_id,
          event_id: event.event_id,
          event_type: string_to_event_type(event.event_type),
          phase: event.phase,
          time_remaining_ms: event.time_remaining_ms,
          participant_count: event.participant_count
        }
      end)

    %ServerEventList{events: event_entries}
  end

  # ServerEventUpdate is per-objective, so send one per objective
  defp build_event_updates(instance_id, event_state) do
    Enum.map(event_state.objectives, fn obj ->
      %ServerEventUpdate{
        instance_id: instance_id,
        objective_index: obj.index,
        current: obj.current,
        target: obj.target
      }
    end)
  end

  defp string_to_event_type("invasion"), do: :invasion
  defp string_to_event_type("collection"), do: :collection
  defp string_to_event_type("territory"), do: :territory
  defp string_to_event_type("defense"), do: :defense
  defp string_to_event_type("escort"), do: :escort
  defp string_to_event_type(_), do: :invasion

  # Response Sending

  defp send_response(:server_event_list, packet, state) do
    writer = PacketWriter.new()
    {:ok, writer} = ServerEventList.write(packet, writer)
    packet_data = PacketWriter.to_binary(writer)
    {:reply, :server_event_list, packet_data, state}
  end

  defp send_event_updates(instance_id, event_state, state) do
    updates = build_event_updates(instance_id, event_state)

    case updates do
      [] ->
        {:ok, state}

      [single] ->
        # Single objective - send one packet
        writer = PacketWriter.new()
        {:ok, writer} = ServerEventUpdate.write(single, writer)
        packet_data = PacketWriter.to_binary(writer)
        {:reply, :server_event_update, packet_data, state}

      multiple ->
        # Multiple objectives - send all packets
        # Note: The handler framework may need to support multiple replies
        # For now, build all packets and return the last one
        # TODO: Consider batching or using a different packet format
        packets =
          Enum.map(multiple, fn update ->
            writer = PacketWriter.new()
            {:ok, writer} = ServerEventUpdate.write(update, writer)
            PacketWriter.to_binary(writer)
          end)

        # Return the combined response - last packet for now
        {:reply, :server_event_update, List.last(packets), state}
    end
  end
end
