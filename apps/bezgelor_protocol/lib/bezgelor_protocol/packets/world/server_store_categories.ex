defmodule BezgelorProtocol.Packets.World.ServerStoreCategories do
  @moduledoc """
  Server packet containing store categories.

  ## Packet Structure

  ```
  count         : uint32 - Number of categories
  categories    : StoreCategory[] - Category entries
  real_currency : 4 bits - Currency type (USD=1)
  ```
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct categories: [],
            real_currency: 1

  @type t :: %__MODULE__{
          categories: list(),
          real_currency: non_neg_integer()
        }

  @impl true
  def opcode, do: :server_store_categories

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    categories = packet.categories || []

    writer =
      writer
      |> PacketWriter.write_uint32(length(categories))
      # No categories to write
      |> PacketWriter.write_bits(packet.real_currency, 4)
      |> PacketWriter.flush_bits()

    {:ok, writer}
  end
end
