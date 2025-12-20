defmodule BezgelorProtocol.Handler.VendorHandler do
  @moduledoc """
  Handles vendor purchase and sell operations.

  ## Purchase Flow

  1. Player opens vendor via NPC interaction (handled by NpcHandler)
  2. Player sends ClientVendorPurchase with item index and quantity
  3. Handler validates: vendor open, item exists, player can afford
  4. Deducts currency and creates item in player inventory
  5. Sends ServerItemAdd to confirm

  ## Sell Flow

  1. Player drags item to vendor window
  2. Handler validates item is sellable
  3. Calculates sell price (base price * sell multiplier)
  4. Removes item and grants currency
  """

  @behaviour BezgelorProtocol.Handler

  alias BezgelorData
  alias BezgelorData.Store
  alias BezgelorDb.Inventory
  alias BezgelorProtocol.PacketReader
  alias BezgelorProtocol.Packets.World.ClientVendorPurchase

  require Logger

  @impl true
  def handle(payload, state) do
    reader = PacketReader.new(payload)

    case ClientVendorPurchase.read(reader) do
      {:ok, packet, _reader} ->
        handle_purchase(packet, state)

      {:error, reason} ->
        Logger.warning("Failed to parse ClientVendorPurchase: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp handle_purchase(packet, state) do
    character_id = state.session_data[:character_id]
    vendor_creature_id = state.session_data[:open_vendor_creature_id]

    cond do
      is_nil(character_id) ->
        Logger.warning("Vendor purchase without character")
        {:ok, state}

      is_nil(vendor_creature_id) ->
        Logger.warning("Vendor purchase without open vendor")
        {:ok, state}

      true ->
        do_purchase(character_id, vendor_creature_id, packet, state)
    end
  end

  defp do_purchase(character_id, vendor_creature_id, packet, state) do
    # Get vendor's items
    items = Store.get_vendor_items_for_creature(vendor_creature_id)

    # Find the item at the requested index
    vendor_item = Enum.at(items, packet.vendor_index)

    cond do
      is_nil(vendor_item) ->
        Logger.warning("Invalid vendor item index: #{packet.vendor_index}")
        {:ok, state}

      packet.quantity < 1 or packet.quantity > 99 ->
        Logger.warning("Invalid purchase quantity: #{packet.quantity}")
        {:ok, state}

      true ->
        process_purchase(character_id, vendor_creature_id, vendor_item, packet.quantity, state)
    end
  end

  defp process_purchase(character_id, vendor_creature_id, vendor_item, quantity, state) do
    item_id = vendor_item.item_id

    # Get item info for price
    case BezgelorData.get_item(item_id) do
      {:ok, item} ->
        # Calculate cost
        base_price = Map.get(item, :buyFromVendorPrice, 0)

        # Get vendor's buy multiplier
        buy_multiplier =
          case Store.get_vendor_by_creature(vendor_creature_id) do
            {:ok, vendor} -> vendor.buy_price_multiplier
            :error -> 1.0
          end

        total_cost = round(base_price * quantity * buy_multiplier)

        # Check player has enough gold (primary currency)
        current_gold = Inventory.get_currency(character_id, :gold)

        if current_gold >= total_cost do
          # Try to spend the currency
          case Inventory.spend_currency(character_id, :gold, total_cost) do
            {:ok, _currency} ->
              # Add item to inventory
              case Inventory.add_item(character_id, item_id, quantity) do
                {:ok, _item} ->
                  Logger.info(
                    "Player #{character_id} purchased #{quantity}x item #{item_id} for #{total_cost} gold"
                  )

                {:error, reason} ->
                  # Refund currency on failure
                  Inventory.add_currency(character_id, :gold, total_cost)
                  Logger.warning("Failed to add purchased item: #{inspect(reason)}")
              end

            {:error, reason} ->
              Logger.warning("Failed to spend currency: #{inspect(reason)}")
          end
        else
          Logger.debug(
            "Player #{character_id} cannot afford item (cost: #{total_cost}, has: #{current_gold})"
          )
        end

        {:ok, state}

      :error ->
        Logger.warning("Item #{item_id} not found in store")
        {:ok, state}
    end
  end

  @doc """
  Set the currently open vendor for a player session.
  Called when player opens a vendor.
  """
  @spec set_open_vendor(map(), integer()) :: map()
  def set_open_vendor(session_data, creature_id) do
    Map.put(session_data, :open_vendor_creature_id, creature_id)
  end

  @doc """
  Clear the currently open vendor.
  Called when player closes vendor or moves away.
  """
  @spec clear_open_vendor(map()) :: map()
  def clear_open_vendor(session_data) do
    Map.delete(session_data, :open_vendor_creature_id)
  end
end
