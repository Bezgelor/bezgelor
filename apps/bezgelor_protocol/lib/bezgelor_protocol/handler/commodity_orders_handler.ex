defmodule BezgelorProtocol.Handler.CommodityOrdersHandler do
  @moduledoc """
  Handles ClientRequestOwnedCommodityOrders packets (opcode 0x03EC).

  Sent by the client when opening the commodity exchange to request
  the player's active buy/sell orders.

  ## Packet Structure (from NexusForever)

  Zero-byte message - no payload data.

  ## Response

  Should respond with ServerCommodityOrdersResponse containing
  the player's active commodity orders.
  """

  @behaviour BezgelorProtocol.Handler

  require Logger

  @impl true
  def handle(_payload, state) do
    Logger.debug("[CommodityOrders] Player requested owned commodity orders")

    # TODO: Fetch player's commodity orders from database
    # TODO: Send ServerCommodityOrdersResponse with order list

    # For now, just acknowledge - marketplace not implemented
    {:ok, state}
  end
end
