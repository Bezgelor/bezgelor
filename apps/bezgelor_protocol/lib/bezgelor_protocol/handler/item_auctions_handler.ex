defmodule BezgelorProtocol.Handler.ItemAuctionsHandler do
  @moduledoc """
  Handles ClientRequestOwnedItemAuctions packets (opcode 0x03ED).

  Sent by the client when opening the auction house to request
  the player's active item auctions.

  ## Packet Structure (from NexusForever)

  Zero-byte message - no payload data.

  ## Response

  Should respond with ServerItemAuctionsResponse containing
  the player's active auctions.
  """

  @behaviour BezgelorProtocol.Handler

  require Logger

  @impl true
  def handle(_payload, state) do
    Logger.debug("[ItemAuctions] Player requested owned item auctions")

    # TODO: Fetch player's auctions from database
    # TODO: Send ServerItemAuctionsResponse with auction list

    # For now, just acknowledge - auction house not implemented
    {:ok, state}
  end
end
