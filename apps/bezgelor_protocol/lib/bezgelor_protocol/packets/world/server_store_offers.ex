defmodule BezgelorProtocol.Packets.World.ServerStoreOffers do
  @moduledoc """
  Server packet containing store offers.

  ## Packet Structure

  ```
  count        : uint32 - Number of offer groups
  offer_groups : OfferGroup[] - Offer group entries
  ```
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct offer_groups: []

  @type t :: %__MODULE__{
          offer_groups: list()
        }

  @impl true
  def opcode, do: :server_store_offers

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    offer_groups = packet.offer_groups || []

    writer =
      writer
      |> PacketWriter.write_u32(length(offer_groups))
      # No offer groups to write
      |> PacketWriter.flush_bits()

    {:ok, writer}
  end
end
