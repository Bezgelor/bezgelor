defmodule BezgelorProtocol.Packets.World.ServerBankBagsUpdate do
  @moduledoc """
  Bank storage update sent when player opens their bank.

  ## Wire Format

  ```
  unlocked_slots  : uint8 (number of unlocked bank slots, 0-6)
  bank_capacity   : uint16 (total bank slots available)
  bag_count       : uint8
  bags            : [BankBagEntry] * bag_count
  item_count      : uint16
  items           : [BankItemEntry] * item_count
  ```

  BankBagEntry:
    bank_slot   : uint8 (0-5)
    item_id     : uint32 (bag item ID, 0 for default bank slot)
    size        : uint8

  BankItemEntry:
    bank_slot   : uint8
    slot        : uint16
    item_id     : uint32
    quantity    : uint16
    durability  : uint8
    bound       : uint8 (bool)

  Opcode: TBD (custom packet)
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  @type bag_entry :: %{
          bank_slot: non_neg_integer(),
          item_id: non_neg_integer() | nil,
          size: pos_integer()
        }

  @type item_entry :: %{
          bank_slot: non_neg_integer(),
          slot: non_neg_integer(),
          item_id: non_neg_integer(),
          quantity: pos_integer(),
          durability: non_neg_integer(),
          bound: boolean()
        }

  @type t :: %__MODULE__{
          unlocked_slots: non_neg_integer(),
          bank_capacity: non_neg_integer(),
          bags: [bag_entry()],
          items: [item_entry()]
        }

  defstruct unlocked_slots: 1,
            bank_capacity: 12,
            bags: [],
            items: []

  @doc """
  Create a new ServerBankBagsUpdate packet.

  ## Parameters

  - `bags` - List of bank bag entries (from Inventory.get_bank_bags/1)
  - `items` - List of bank item entries (from Inventory.get_bank_items/1)
  - `opts` - Additional options

  ## Options

  - `:unlocked_slots` - Number of unlocked bank slots (default 1)
  """
  @spec new([bag_entry()], [item_entry()], keyword()) :: t()
  def new(bags, items, opts \\ []) do
    unlocked_slots = Keyword.get(opts, :unlocked_slots, length(bags))
    bank_capacity = Enum.reduce(bags, 0, fn bag, acc -> acc + bag.size end)

    %__MODULE__{
      unlocked_slots: unlocked_slots,
      bank_capacity: bank_capacity,
      bags: bags,
      items: items
    }
  end

  @impl true
  def opcode, do: :server_bank_bags_update

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_u8(packet.unlocked_slots)
      |> PacketWriter.write_u16(packet.bank_capacity)
      |> PacketWriter.write_u8(length(packet.bags))

    # Write bank bags
    writer =
      Enum.reduce(packet.bags, writer, fn bag, w ->
        w
        |> PacketWriter.write_u8(bag.bank_slot)
        |> PacketWriter.write_u32(bag.item_id || 0)
        |> PacketWriter.write_u8(bag.size)
      end)

    # Write bank items
    writer = PacketWriter.write_u16(writer, length(packet.items))

    writer =
      Enum.reduce(packet.items, writer, fn item, w ->
        w
        |> PacketWriter.write_u8(item.bank_slot)
        |> PacketWriter.write_u16(item.slot)
        |> PacketWriter.write_u32(item.item_id)
        |> PacketWriter.write_u16(item.quantity)
        |> PacketWriter.write_u8(item.durability || 100)
        |> PacketWriter.write_u8(if(item.bound, do: 1, else: 0))
      end)

    {:ok, writer}
  end

  @doc """
  Build bank bags from database Bag records.

  Converts `BezgelorDb.Schema.Bag` records into the format expected by this packet.
  Bank bags have bag_index >= 10, which maps to bank_slot 0-5.
  """
  @spec build_bags_from_db([map()]) :: [bag_entry()]
  def build_bags_from_db(db_bags) do
    Enum.map(db_bags, fn bag ->
      %{
        # Convert bag_index (10-15) to bank_slot (0-5)
        bank_slot: bag.bag_index - 10,
        item_id: bag.item_id,
        size: bag.size
      }
    end)
  end

  @doc """
  Build bank items from database InventoryItem records.

  Converts `BezgelorDb.Schema.InventoryItem` records into the format expected by this packet.
  """
  @spec build_items_from_db([map()]) :: [item_entry()]
  def build_items_from_db(db_items) do
    Enum.map(db_items, fn item ->
      %{
        # Convert bag_index (10-15) to bank_slot (0-5)
        bank_slot: item.bag_index - 10,
        slot: item.slot,
        item_id: item.item_id,
        quantity: item.quantity,
        durability: item.durability || 100,
        bound: item.bound || false
      }
    end)
  end
end
