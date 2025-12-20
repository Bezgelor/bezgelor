defmodule BezgelorWorld.Handler.GatheringHandler do
  @moduledoc """
  Handles gathering operations from resource nodes.

  ## Packets Handled
  - ClientGatherStart - Begin gathering from a node
  - ClientGatherComplete - Gathering cast completed

  ## Packets Sent
  - ServerGatherResult - Gathering result with loot
  - ServerNodeUpdate - Node state change (tapped/depleted)
  - ServerTradeskillUpdate - XP gained from gathering
  """

  @behaviour BezgelorProtocol.Handler
  @dialyzer {:nowarn_function, [handle_start: 2, handle_complete: 2]}

  require Logger

  alias BezgelorDb.Tradeskills
  alias BezgelorProtocol.PacketReader
  alias BezgelorProtocol.PacketWriter

  alias BezgelorProtocol.Packets.World.{
    ClientGatherStart,
    ClientGatherComplete,
    ServerGatherResult,
    ServerNodeUpdate,
    ServerTradeskillUpdate
  }

  alias BezgelorData.Store
  alias BezgelorWorld.Gathering.GatheringNode
  alias BezgelorWorld.TradeskillConfig

  @impl true
  def handle(payload, state) do
    reader = PacketReader.new(payload)

    with {:error, _} <- try_start(reader, state),
         {:error, _} <- try_complete(reader, state) do
      {:error, :unknown_gathering_packet}
    end
  end

  # Start gathering

  defp try_start(reader, state) do
    case ClientGatherStart.read(reader) do
      {:ok, packet, _} -> handle_start(packet, state)
      error -> error
    end
  end

  defp handle_start(packet, state) do
    character_id = state.session_data[:character_id]
    zone_instance = state.session_data[:zone_instance]

    # Get node from zone instance
    case get_node(zone_instance, packet.node_guid) do
      nil ->
        Logger.warning(
          "Character #{character_id} tried to gather from unknown node #{packet.node_guid}"
        )

        {:ok, state}

      %{} = node ->
        cond do
          not GatheringNode.available?(node) ->
            Logger.debug("Node #{packet.node_guid} not available")
            {:ok, state}

          not GatheringNode.can_harvest?(node, character_id) ->
            Logger.debug("Character #{character_id} cannot harvest node #{packet.node_guid}")
            {:ok, state}

          true ->
            # Tap the node based on competition mode
            case TradeskillConfig.node_competition() do
              :first_tap ->
                tapped_node = GatheringNode.tap(node, character_id)
                update_node(zone_instance, tapped_node)
                broadcast_node_update(tapped_node, state)

              :shared ->
                # Shared tap window - anyone can harvest
                :ok

              :instanced ->
                # Instanced - each player gets their own copy
                :ok
            end

            # Store pending gather
            new_state = put_in(state, [:session_data, :gathering_node], packet.node_guid)

            Logger.debug("Character #{character_id} started gathering node #{packet.node_guid}")
            {:ok, new_state}
        end
    end
  end

  # Complete gathering

  defp try_complete(reader, state) do
    case ClientGatherComplete.read(reader) do
      {:ok, packet, _} -> handle_complete(packet, state)
      error -> error
    end
  end

  defp handle_complete(packet, state) do
    character_id = state.session_data[:character_id]
    zone_instance = state.session_data[:zone_instance]
    pending_node = get_in(state, [:session_data, :gathering_node])

    cond do
      pending_node != packet.node_guid ->
        Logger.warning("Character #{character_id} completed gather for wrong node")
        {:ok, state}

      true ->
        case get_node(zone_instance, packet.node_guid) do
          nil ->
            {:ok, state}

          %{} = node ->
            if GatheringNode.can_harvest?(node, character_id) do
              do_harvest(node, character_id, zone_instance, state)
            else
              Logger.debug("Character #{character_id} lost tap on node #{packet.node_guid}")
              send_gather_result(:failed, packet.node_guid, [], 0, state)
            end
        end
    end
  end

  defp do_harvest(node, character_id, zone_instance, state) do
    # Generate loot
    loot = generate_loot(node.node_type_id)

    # Calculate XP
    xp_gained = calculate_gather_xp(node.node_type_id)

    # Mark node as harvested with respawn timer
    respawn_seconds = get_respawn_time(node.node_type_id)
    harvested_node = GatheringNode.harvest(node, respawn_seconds)
    update_node(zone_instance, harvested_node)

    # Broadcast node depleted
    broadcast_node_update(harvested_node, state)

    # Award XP
    award_gathering_xp(character_id, node.node_type_id, xp_gained, state)

    # TODO: Add loot to inventory

    Logger.debug(
      "Character #{character_id} harvested node #{node.node_id}: #{length(loot)} items, #{xp_gained} XP"
    )

    # Clear pending gather and send result
    new_state = put_in(state, [:session_data, :gathering_node], nil)
    send_gather_result(:success, node.node_id, loot, xp_gained, new_state)
  end

  defp generate_loot(node_type_id) do
    case Store.get_node_type(node_type_id) do
      {:ok, node_type} ->
        node_type.loot_table
        |> Enum.filter(fn loot_entry ->
          :rand.uniform() <= loot_entry.chance
        end)
        |> Enum.map(fn loot_entry ->
          quantity = Enum.random(loot_entry.min_quantity..loot_entry.max_quantity)
          %{item_id: loot_entry.item_id, quantity: quantity}
        end)
        |> Enum.filter(fn item -> item.quantity > 0 end)

      :error ->
        # Fallback loot
        [
          %{item_id: node_type_id * 100 + 1, quantity: Enum.random(1..3)},
          %{item_id: node_type_id * 100 + 2, quantity: Enum.random(0..1)}
        ]
        |> Enum.filter(fn item -> item.quantity > 0 end)
    end
  end

  defp calculate_gather_xp(node_type_id) do
    case Store.get_node_type(node_type_id) do
      {:ok, node_type} -> node_type.xp_reward
      :error -> 150
    end
  end

  defp get_respawn_time(node_type_id) do
    case Store.get_node_type(node_type_id) do
      {:ok, node_type} -> node_type.respawn_seconds
      :error -> 60
    end
  end

  defp award_gathering_xp(character_id, node_type_id, xp, _state) do
    # Look up profession from node type
    profession_id =
      case Store.get_node_type(node_type_id) do
        {:ok, node_type} -> node_type.profession_id
        # Fallback to Mining
        :error -> 101
      end

    case Tradeskills.add_xp(character_id, profession_id, xp) do
      {:ok, tradeskill, levels_gained} when levels_gained > 0 ->
        update = %ServerTradeskillUpdate{
          profession_id: tradeskill.profession_id,
          profession_type: tradeskill.profession_type,
          skill_level: tradeskill.skill_level,
          skill_xp: tradeskill.skill_xp,
          is_active: tradeskill.is_active,
          levels_gained: levels_gained
        }

        writer = PacketWriter.new()
        {:ok, writer} = ServerTradeskillUpdate.write(update, writer)
        packet_data = PacketWriter.to_binary(writer)

        send(self(), {:send_packet, :server_tradeskill_update, packet_data})

      _ ->
        :ok
    end
  end

  defp send_gather_result(result, node_guid, items, xp_gained, state) do
    response = %ServerGatherResult{
      result: result,
      node_guid: node_guid,
      items: items,
      xp_gained: xp_gained
    }

    writer = PacketWriter.new()
    {:ok, writer} = ServerGatherResult.write(response, writer)
    packet_data = PacketWriter.to_binary(writer)
    {:reply, :server_gather_result, packet_data, state}
  end

  defp broadcast_node_update(node, state) do
    update = %ServerNodeUpdate{
      node_guid: node.node_id,
      is_available: GatheringNode.available?(node),
      tapped_by: node.tapped_by
    }

    writer = PacketWriter.new()
    {:ok, writer} = ServerNodeUpdate.write(update, writer)
    packet_data = PacketWriter.to_binary(writer)

    # Broadcast to all players in zone
    zone_instance = state.session_data[:zone_instance]

    if zone_instance do
      send(zone_instance, {:broadcast, :server_node_update, packet_data})
    end
  end

  # Zone node management stubs - would integrate with ZoneInstance

  defp get_node(zone_instance, node_guid) do
    # TODO: Query zone instance for node by GUID
    # Stub uses Process.get for dynamic return type (supports testing mocks)
    Process.get({:gathering_node, zone_instance, node_guid})
  end

  defp update_node(_zone_instance, _node) do
    # TODO: Update node in zone instance state
    :ok
  end
end
