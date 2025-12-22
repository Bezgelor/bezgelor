defmodule BezgelorWorld.Handler.LootHandler do
  @moduledoc """
  Handles loot-related packets.

  Processes:
  - Corpse looting
  - Loot rolls (need/greed/pass)
  - Master loot assignments
  - Loot settings changes
  """

  require Logger

  alias BezgelorCore.Economy.TelemetryEvents
  alias BezgelorWorld.{CombatBroadcaster, CorpseManager}
  alias BezgelorWorld.Loot.LootManager
  alias BezgelorProtocol.Packets.World.ServerLootSettings

  @doc """
  Handles corpse loot request.

  When a player loots a corpse:
  1. Check if corpse exists
  2. Check if player can loot (hasn't already)
  3. Award loot items to player inventory
  4. Send loot notification
  """
  def handle_loot_corpse(packet, state) do
    player_guid = state.session_data[:entity_guid]
    character_id = state.session_data[:character_id]
    corpse_guid = packet.corpse_guid

    if player_guid && character_id do
      # Get corpse info before taking loot (for telemetry)
      corpse_info =
        case CorpseManager.get_corpse(corpse_guid) do
          {:ok, corpse} ->
            %{
              creature_id: corpse.creature_id || 0,
              world_id: corpse.world_id || 0,
              zone_id: corpse.zone_id || 0
            }

          {:error, _} ->
            nil
        end

      case CorpseManager.take_loot(corpse_guid, player_guid) do
        {:ok, loot_items} when loot_items != [] ->
          # Separate gold and items
          {gold, items} = separate_gold_and_items(loot_items)

          # Add items to player inventory
          add_items_to_inventory(character_id, items)

          # Add gold to player
          if gold > 0 do
            creature_id = if corpse_info, do: corpse_info.creature_id, else: 0
            add_gold_to_player(character_id, gold, creature_id)
          end

          # Emit loot drop telemetry
          if corpse_info do
            emit_loot_telemetry(character_id, corpse_info, gold, items)
          end

          # Send loot notification
          CombatBroadcaster.send_loot_drop(player_guid, corpse_guid, gold, items)

          Logger.info(
            "Player #{player_guid} looted corpse #{corpse_guid}: #{gold} gold, #{length(items)} items"
          )

          {:ok, [], state}

        {:ok, []} ->
          # Already looted or empty
          Logger.debug("Player #{player_guid} tried to loot already-looted corpse #{corpse_guid}")
          {:ok, [], state}

        {:error, :not_found} ->
          Logger.debug("Player #{player_guid} tried to loot non-existent corpse #{corpse_guid}")
          {:ok, [], state}
      end
    else
      {:ok, [], state}
    end
  end

  @doc """
  Handles player roll response (need/greed/pass).
  """
  def handle_roll(packet, state) do
    character_id = state.session_data[:character_id]
    instance_guid = state.session_data[:instance_guid]

    if character_id && instance_guid do
      roll_type = int_to_roll_type(packet.roll_type)

      case LootManager.submit_roll(instance_guid, packet.loot_id, character_id, roll_type) do
        :ok ->
          Logger.debug("Player #{character_id} rolled #{roll_type} on loot #{packet.loot_id}")
          {:ok, [], state}

        {:error, reason} ->
          Logger.warning("Roll failed: #{inspect(reason)}")
          {:ok, [], state}
      end
    else
      {:ok, [], state}
    end
  end

  @doc """
  Handles master loot assignment.
  """
  def handle_master_assign(packet, state) do
    character_id = state.session_data[:character_id]
    instance_guid = state.session_data[:instance_guid]

    if character_id && instance_guid do
      case LootManager.master_assign(
             instance_guid,
             packet.loot_id,
             character_id,
             packet.recipient_id
           ) do
        :ok ->
          Logger.info(
            "Master loot: #{character_id} assigned loot #{packet.loot_id} to #{packet.recipient_id}"
          )

          {:ok, [], state}

        {:error, reason} ->
          Logger.warning("Master loot failed: #{inspect(reason)}")
          {:ok, [], state}
      end
    else
      {:ok, [], state}
    end
  end

  @doc """
  Handles loot settings change request.
  """
  def handle_settings_change(packet, state) do
    character_id = state.session_data[:character_id]
    instance_guid = state.session_data[:instance_guid]

    if character_id && instance_guid do
      method = int_to_loot_method(packet.loot_method)

      case LootManager.set_loot_method(instance_guid, character_id, method) do
        :ok ->
          response = %ServerLootSettings{
            loot_method: method
          }

          {:ok, [response], state}

        {:error, reason} ->
          Logger.warning("Settings change failed: #{inspect(reason)}")
          {:ok, [], state}
      end
    else
      {:ok, [], state}
    end
  end

  # Convert wire format to atoms
  defp int_to_roll_type(0), do: :need
  defp int_to_roll_type(1), do: :greed
  defp int_to_roll_type(2), do: :pass
  defp int_to_roll_type(_), do: :pass

  defp int_to_loot_method(0), do: :personal
  defp int_to_loot_method(1), do: :group_loot
  defp int_to_loot_method(2), do: :need_before_greed
  defp int_to_loot_method(3), do: :master_loot
  defp int_to_loot_method(4), do: :round_robin
  defp int_to_loot_method(_), do: :personal

  # Separate gold (item_id 0) from actual items
  defp separate_gold_and_items(loot_items) do
    {gold_entries, item_entries} =
      Enum.split_with(loot_items, fn {item_id, _qty} -> item_id == 0 end)

    gold = Enum.reduce(gold_entries, 0, fn {_id, qty}, acc -> acc + qty end)
    items = item_entries

    {gold, items}
  end

  # Add items to player inventory
  defp add_items_to_inventory(character_id, items) do
    alias BezgelorDb.Inventory

    Enum.each(items, fn {item_id, quantity} ->
      case Inventory.add_item(character_id, item_id, quantity) do
        {:ok, _} ->
          Logger.debug("Added #{quantity}x item #{item_id} to character #{character_id}")

        {:error, reason} ->
          Logger.warning(
            "Failed to add item #{item_id} to character #{character_id}: #{inspect(reason)}"
          )
      end
    end)
  end

  # Add gold to player's currency
  defp add_gold_to_player(character_id, gold, creature_id) do
    alias BezgelorDb.{Characters, Inventory}

    case Characters.add_currency(character_id, :gold, gold) do
      {:ok, currency} ->
        Logger.debug("Added #{gold} gold to character #{character_id}")

        # Emit currency transaction telemetry
        balance_after = Map.get(currency, :gold, 0)

        TelemetryEvents.emit_currency_transaction(
          amount: gold,
          balance_after: balance_after,
          character_id: character_id,
          currency_type: :gold,
          source_type: :loot,
          source_id: creature_id
        )

      {:error, reason} ->
        Logger.warning("Failed to add gold to character #{character_id}: #{inspect(reason)}")
    end
  end

  # Emit loot drop telemetry for each item and total gold
  defp emit_loot_telemetry(character_id, corpse_info, gold, items) do
    # For now, we'll use a simple heuristic for item value
    # In a production system, this would query item templates for actual values
    item_value = calculate_total_item_value(items)

    TelemetryEvents.emit_loot_drop(
      item_value: item_value,
      currency_amount: gold,
      character_id: character_id,
      creature_id: corpse_info.creature_id,
      world_id: corpse_info.world_id,
      zone_id: corpse_info.zone_id
    )
  end

  # Calculate estimated value of items
  # This is a placeholder - in production, would query item data for sell prices
  defp calculate_total_item_value(items) do
    # Estimate: assume average item value of 10 gold per item
    # Real implementation would look up item_id in item templates
    Enum.reduce(items, 0, fn {_item_id, quantity}, acc ->
      acc + quantity * 10
    end)
  end
end
