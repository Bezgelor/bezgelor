defmodule BezgelorProtocol.Handler.VendorSellHandler do
  @moduledoc """
  Handles selling items to vendors.

  ## Flow

  1. Validates vendor is open
  2. Gets item from player inventory
  3. Calculates sell price (base * sell_multiplier * quantity)
  4. Removes item from inventory
  5. Grants currency to player
  """

  @behaviour BezgelorProtocol.Handler

  alias BezgelorCore.Economy.TelemetryEvents
  alias BezgelorData
  alias BezgelorData.Store
  alias BezgelorDb.Inventory
  alias BezgelorProtocol.PacketReader
  alias BezgelorProtocol.Packets.World.ClientVendorSell

  require Logger

  @impl true
  def handle(payload, state) do
    reader = PacketReader.new(payload)

    case ClientVendorSell.read(reader) do
      {:ok, packet, _reader} ->
        handle_sell(packet, state)

      {:error, reason} ->
        Logger.warning("Failed to parse ClientVendorSell: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp handle_sell(packet, state) do
    character_id = state.session_data[:character_id]
    vendor_creature_id = state.session_data[:open_vendor_creature_id]

    cond do
      is_nil(character_id) ->
        Logger.warning("Vendor sell without character")
        {:ok, state}

      is_nil(vendor_creature_id) ->
        Logger.warning("Vendor sell without open vendor")
        {:ok, state}

      true ->
        do_sell(character_id, vendor_creature_id, packet, state)
    end
  end

  defp do_sell(character_id, vendor_creature_id, packet, state) do
    # Get the item from player inventory
    case Inventory.get_item_at(character_id, packet.location, 0, packet.bag_index) do
      nil ->
        Logger.warning("Item not found at location #{packet.location}:#{packet.bag_index}")
        {:ok, state}

      item ->
        process_sell(character_id, vendor_creature_id, item, packet.quantity, state)
    end
  end

  defp process_sell(character_id, vendor_creature_id, inventory_item, quantity, state) do
    item_id = inventory_item.item_id

    # Get item info for sell price
    case BezgelorData.get_item(item_id) do
      {:ok, item} ->
        # Calculate sell price
        base_price = Map.get(item, :sellToVendorPrice, 0)

        # Get vendor's sell multiplier
        sell_multiplier =
          case Store.get_vendor_by_creature(vendor_creature_id) do
            {:ok, vendor} -> vendor.sell_price_multiplier
            :error -> 0.25
          end

        # Ensure we don't sell more than we have
        actual_quantity = min(quantity, inventory_item.quantity)
        total_value = round(base_price * actual_quantity * sell_multiplier)

        if total_value > 0 do
          # Remove item(s) from inventory
          case Inventory.remove_item(character_id, inventory_item.id, actual_quantity) do
            {:ok, _} ->
              # Grant currency
              Inventory.add_currency(character_id, :gold, total_value)

              Logger.info(
                "Player #{character_id} sold #{actual_quantity}x item #{item_id} for #{total_value} gold"
              )

              # Emit telemetry event for successful vendor transaction
              TelemetryEvents.emit_vendor_transaction(
                total_cost: total_value,
                item_count: actual_quantity,
                character_id: character_id,
                vendor_id: vendor_creature_id,
                transaction_type: :sell
              )

            {:error, reason} ->
              Logger.warning("Failed to remove sold item: #{inspect(reason)}")
          end
        else
          Logger.debug("Item #{item_id} has no sell value")
        end

        {:ok, state}

      :error ->
        Logger.warning("Item #{item_id} not found in store")
        {:ok, state}
    end
  end
end
