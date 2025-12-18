defmodule BezgelorProtocol.Packets.World.ClientItemMove do
  @moduledoc """
  Client request to move an item from one location to another.

  ## Wire Format
  from_location : 9 bits (InventoryLocation enum)
  from_bag_index : uint32
  to_location : 9 bits (InventoryLocation enum)
  to_bag_index : uint32
  """

  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:from_location, :from_bag_index, :to_location, :to_bag_index]

  @type t :: %__MODULE__{
          from_location: non_neg_integer(),
          from_bag_index: non_neg_integer(),
          to_location: non_neg_integer(),
          to_bag_index: non_neg_integer()
        }

  @impl true
  def opcode, do: :client_item_move

  @impl true
  @spec read(PacketReader.t()) :: {:ok, t(), PacketReader.t()} | {:error, term()}
  def read(reader) do
    # WildStar uses continuous bit-packing - no byte alignment between fields
    with {:ok, from_location, reader} <- PacketReader.read_bits(reader, 9),
         {:ok, from_bag_index, reader} <- PacketReader.read_bits(reader, 32),
         {:ok, to_location, reader} <- PacketReader.read_bits(reader, 9),
         {:ok, to_bag_index, reader} <- PacketReader.read_bits(reader, 32) do
      packet = %__MODULE__{
        from_location: from_location,
        from_bag_index: from_bag_index,
        to_location: to_location,
        to_bag_index: to_bag_index
      }

      {:ok, packet, reader}
    end
  end

  @doc "Convert location integer to atom (matching Ecto enum values)."
  def location_to_atom(0), do: :equipped
  def location_to_atom(1), do: :bag  # InventoryLocation.Inventory -> :bag in DB
  def location_to_atom(2), do: :bank
  def location_to_atom(4), do: :ability
  def location_to_atom(_), do: :bag  # Default to bag
end
