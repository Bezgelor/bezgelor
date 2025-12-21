defmodule BezgelorWorld.Handler.StorefrontHandler do
  @moduledoc """
  Handles store browsing, purchasing, gifting, and promo codes.

  ## Packets Handled
  - ClientStoreBrowse - Browse store catalog
  - ClientStorePurchase - Purchase an item
  - ClientStoreGetDailyDeals - Get today's daily deals
  - ClientGiftItem - Gift item to another player
  - ClientRedeemCode - Redeem a promotional code

  ## Packets Sent
  - ServerStoreCatalog - Store item list
  - ServerStorePurchaseResult - Purchase result
  - ServerStoreBalance - Account currency balance
  - ServerStoreDailyDeals - Today's daily deals
  - ServerPromoCodeResult - Promo code redemption result
  """

  @behaviour BezgelorProtocol.Handler

  require Logger

  alias BezgelorDb.Storefront
  alias BezgelorDb.Accounts
  alias BezgelorDb.Schema.StoreItem
  alias BezgelorProtocol.PacketReader
  alias BezgelorProtocol.PacketWriter

  alias BezgelorProtocol.Packets.World.{
    ClientStoreBrowse,
    ClientStorePurchase,
    ClientStoreGetDailyDeals,
    ClientGiftItem,
    ClientRedeemCode,
    ServerStoreCatalog,
    ServerStorePurchaseResult,
    ServerStoreBalance,
    ServerStoreDailyDeals,
    ServerPromoCodeResult
  }

  @impl true
  def handle(payload, state) do
    reader = PacketReader.new(payload)

    with {:error, _} <- try_browse(reader, state),
         {:error, _} <- try_purchase(reader, state),
         {:error, _} <- try_get_daily_deals(reader, state),
         {:error, _} <- try_gift_item(reader, state),
         {:error, _} <- try_redeem_code(reader, state) do
      {:error, :unknown_store_packet}
    end
  end

  # Browse store catalog

  defp try_browse(reader, state) do
    case ClientStoreBrowse.read(reader) do
      {:ok, packet, _} -> handle_browse(packet, state)
      error -> error
    end
  end

  defp handle_browse(packet, state) do
    account_id = state.session_data[:account_id]

    # Get categories and items
    categories = Storefront.list_categories()

    items =
      if packet.category_id == 0 do
        Storefront.list_available_items()
      else
        Storefront.list_items_by_category(packet.category_id)
      end

    # Mark items as new
    items_with_new =
      Enum.map(items, fn item ->
        Map.put(item, :is_new, StoreItem.is_new?(item))
      end)

    Logger.debug(
      "Sending store catalog: #{length(categories)} categories, #{length(items)} items"
    )

    response = %ServerStoreCatalog{
      categories: categories,
      items: items_with_new
    }

    writer = PacketWriter.new()
    {:ok, writer} = ServerStoreCatalog.write(response, writer)
    packet_data = PacketWriter.to_binary(writer)

    # Also send balance
    send_balance(state.connection_pid, account_id)

    {:reply, :server_store_catalog, packet_data, state}
  end

  # Purchase item

  defp try_purchase(reader, state) do
    case ClientStorePurchase.read(reader) do
      {:ok, packet, _} -> handle_purchase(packet, state)
      error -> error
    end
  end

  defp handle_purchase(packet, state) do
    account_id = state.session_data[:account_id]
    character_id = state.session_data[:character_id]

    opts = [character_id: character_id]
    opts = if packet.promo_code, do: Keyword.put(opts, :promo_code, packet.promo_code), else: opts

    result = Storefront.purchase_item(account_id, packet.item_id, packet.currency_type, opts)

    response =
      case result do
        {:ok, purchase} ->
          Logger.info(
            "Account #{account_id} purchased store item #{packet.item_id} for #{purchase.amount_paid}"
          )

          ServerStorePurchaseResult.success(
            packet.item_id,
            purchase.amount_paid,
            purchase.discount_applied || 0,
            packet.currency_type
          )

        {:error, :not_found} ->
          Logger.warning("Store item #{packet.item_id} not found")
          ServerStorePurchaseResult.error(:not_found, packet.item_id)

        {:error, :insufficient_funds} ->
          Logger.debug("Account #{account_id} has insufficient funds for item #{packet.item_id}")
          ServerStorePurchaseResult.error(:insufficient_funds, packet.item_id)

        {:error, {:invalid_promo, _reason}} ->
          Logger.debug("Invalid promo code for account #{account_id}")
          ServerStorePurchaseResult.error(:invalid_promo, packet.item_id)

        {:error, :no_price} ->
          Logger.warning("Store item #{packet.item_id} has no price for #{packet.currency_type}")
          ServerStorePurchaseResult.error(:no_price, packet.item_id)

        {:error, reason} ->
          Logger.error("Store purchase failed: #{inspect(reason)}")
          ServerStorePurchaseResult.error(:error, packet.item_id)
      end

    writer = PacketWriter.new()
    {:ok, writer} = ServerStorePurchaseResult.write(response, writer)
    packet_data = PacketWriter.to_binary(writer)

    # Send updated balance after purchase
    if match?({:ok, _}, result) do
      send_balance(state.connection_pid, account_id)
    end

    {:reply, :server_store_purchase_result, packet_data, state}
  end

  # Get daily deals

  defp try_get_daily_deals(reader, state) do
    case ClientStoreGetDailyDeals.read(reader) do
      {:ok, _packet, _} -> handle_get_daily_deals(state)
      error -> error
    end
  end

  defp handle_get_daily_deals(state) do
    deals = Storefront.get_daily_deals()

    Logger.debug("Sending #{length(deals)} daily deals")

    response = %ServerStoreDailyDeals{deals: deals}

    writer = PacketWriter.new()
    {:ok, writer} = ServerStoreDailyDeals.write(response, writer)
    packet_data = PacketWriter.to_binary(writer)

    {:reply, :server_store_daily_deals, packet_data, state}
  end

  # Gift item

  defp try_gift_item(reader, state) do
    case ClientGiftItem.read(reader) do
      {:ok, packet, _} -> handle_gift_item(packet, state)
      error -> error
    end
  end

  defp handle_gift_item(packet, state) do
    account_id = state.session_data[:account_id]

    # Look up recipient by character name
    recipient_result = Accounts.get_account_by_character_name(packet.recipient_name)

    result =
      case recipient_result do
        {:ok, recipient_account} ->
          Storefront.gift_item(
            account_id,
            recipient_account.id,
            packet.item_id,
            packet.currency_type,
            packet.message
          )

        {:error, :not_found} ->
          {:error, :recipient_not_found}
      end

    response =
      case result do
        {:ok, purchase} ->
          Logger.info(
            "Account #{account_id} gifted item #{packet.item_id} to #{packet.recipient_name}"
          )

          ServerStorePurchaseResult.success(
            packet.item_id,
            purchase.amount_paid,
            0,
            packet.currency_type
          )

        {:error, :not_found} ->
          Logger.warning("Store item #{packet.item_id} not found for gift")
          ServerStorePurchaseResult.error(:not_found, packet.item_id)

        {:error, :recipient_not_found} ->
          Logger.debug("Gift recipient #{packet.recipient_name} not found")
          ServerStorePurchaseResult.error(:not_found, packet.item_id)

        {:error, :insufficient_funds} ->
          Logger.debug("Account #{account_id} has insufficient funds for gift")
          ServerStorePurchaseResult.error(:insufficient_funds, packet.item_id)

        {:error, reason} ->
          Logger.error("Gift failed: #{inspect(reason)}")
          ServerStorePurchaseResult.error(:error, packet.item_id)
      end

    writer = PacketWriter.new()
    {:ok, writer} = ServerStorePurchaseResult.write(response, writer)
    packet_data = PacketWriter.to_binary(writer)

    # Send updated balance after gift
    if match?({:ok, _}, result) do
      send_balance(state.connection_pid, account_id)
    end

    {:reply, :server_store_purchase_result, packet_data, state}
  end

  # Redeem promo code

  defp try_redeem_code(reader, state) do
    case ClientRedeemCode.read(reader) do
      {:ok, packet, _} -> handle_redeem_code(packet, state)
      error -> error
    end
  end

  defp handle_redeem_code(packet, state) do
    account_id = state.session_data[:account_id]

    result = Storefront.redeem_promo_code(packet.code, account_id)

    response =
      case result do
        {:ok, promo_code} ->
          Logger.info("Account #{account_id} redeemed promo code: #{packet.code}")

          case promo_code.code_type do
            "item" ->
              ServerPromoCodeResult.success_item(promo_code.granted_item_id || 0)

            "currency" ->
              currency_type =
                String.to_existing_atom(promo_code.granted_currency_type || "premium")

              ServerPromoCodeResult.success_currency(
                promo_code.granted_currency_amount || 0,
                currency_type
              )

            _ ->
              ServerPromoCodeResult.success_discount()
          end

        {:error, :not_found} ->
          Logger.debug("Promo code #{packet.code} not found")
          ServerPromoCodeResult.error(:not_found)

        {:error, :expired} ->
          Logger.debug("Promo code #{packet.code} expired")
          ServerPromoCodeResult.error(:expired)

        {:error, :already_redeemed} ->
          Logger.debug("Promo code #{packet.code} already redeemed by account #{account_id}")
          ServerPromoCodeResult.error(:already_redeemed)

        {:error, :not_redeemable} ->
          Logger.debug("Promo code #{packet.code} is not directly redeemable (discount code)")
          ServerPromoCodeResult.error(:not_found)

        {:error, reason} ->
          Logger.error("Promo code redemption failed: #{inspect(reason)}")
          ServerPromoCodeResult.error(:error)
      end

    writer = PacketWriter.new()
    {:ok, writer} = ServerPromoCodeResult.write(response, writer)
    packet_data = PacketWriter.to_binary(writer)

    # Send updated balance if currency was granted
    if match?({:ok, %{code_type: "currency"}}, result) do
      send_balance(state.connection_pid, account_id)
    end

    {:reply, :server_promo_code_result, packet_data, state}
  end

  # Helper functions

  defp send_balance(connection_pid, account_id) do
    case Storefront.get_account_balance(account_id) do
      {:ok, %{premium: premium, bonus: bonus}} ->
        response = ServerStoreBalance.new(premium, bonus)

        writer = PacketWriter.new()
        {:ok, writer} = ServerStoreBalance.write(response, writer)
        packet_data = PacketWriter.to_binary(writer)

        send(connection_pid, {:send_packet, :server_store_balance, packet_data})

      {:error, :not_found} ->
        # No currency record exists yet, send zeros
        response = ServerStoreBalance.new(0, 0)

        writer = PacketWriter.new()
        {:ok, writer} = ServerStoreBalance.write(response, writer)
        packet_data = PacketWriter.to_binary(writer)

        send(connection_pid, {:send_packet, :server_store_balance, packet_data})
    end
  end

  # Public API

  @doc """
  Send store balance to client on login.
  """
  @spec send_store_balance(pid(), integer()) :: :ok
  def send_store_balance(connection_pid, account_id) do
    send_balance(connection_pid, account_id)
    :ok
  end
end
