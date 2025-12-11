defmodule BezgelorProtocol.Packets.World.ClientCraftAddAdditive do
  @moduledoc """
  Client request to add an additive to the current craft.

  ## Wire Format
  item_id         : uint32  - Item ID of the additive
  quantity        : uint16  - Number of additives to use
  overcharge_level: uint8   - Overcharge level (0-3)
  """
  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:item_id, :quantity, :overcharge_level]

  @type t :: %__MODULE__{
          item_id: non_neg_integer(),
          quantity: non_neg_integer(),
          overcharge_level: non_neg_integer()
        }

  @impl true
  def opcode, do: :client_craft_add_additive

  @impl true
  def read(reader) do
    with {:ok, item_id, reader} <- PacketReader.read_uint32(reader),
         {:ok, quantity, reader} <- PacketReader.read_uint16(reader),
         {:ok, overcharge_level, reader} <- PacketReader.read_byte(reader) do
      packet = %__MODULE__{
        item_id: item_id,
        quantity: quantity,
        overcharge_level: min(overcharge_level, 3)
      }

      {:ok, packet, reader}
    end
  end
end
