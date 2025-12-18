defmodule BezgelorProtocol.Packets.World.ServerCurrencyUpdate do
  @moduledoc """
  Currency update sent when a player's currency changes.

  ## Wire Format

  Based on NexusForever's ServerAccountCurrencyGrant:
  ```
  currency_type : 5 bits (AccountCurrencyType enum)
  amount        : uint64 (new total amount)
  unknown0      : uint64 (always 0)
  unknown1      : uint64 (always 0)
  ```

  ## Currency Types

  | Value | Type |
  |-------|------|
  | 1 | Gold |
  | 2 | Elder Gems |
  | 3 | Renown |
  | 4 | Prestige |
  | 5 | Glory |
  | 6 | Crafting Vouchers |
  | 7 | War Coins |
  | 8 | Shade Silver |
  | 9 | Protostar Promissory Notes |

  Opcode: 0x0582 (ServerAccountCurrencyGrant)
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  @type t :: %__MODULE__{
          currency_type: atom(),
          amount: non_neg_integer()
        }

  defstruct currency_type: :gold,
            amount: 0

  # Currency type to integer mapping
  @currency_types %{
    gold: 1,
    elder_gems: 2,
    renown: 3,
    prestige: 4,
    glory: 5,
    crafting_vouchers: 6,
    war_coins: 7,
    shade_silver: 8,
    protostar_promissory_notes: 9
  }

  @doc """
  Create a new ServerCurrencyUpdate packet.
  """
  @spec new(atom(), non_neg_integer()) :: t()
  def new(currency_type, amount) do
    %__MODULE__{
      currency_type: currency_type,
      amount: amount
    }
  end

  @impl true
  def opcode, do: :server_currency_update

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    type_int = Map.get(@currency_types, packet.currency_type, 1)

    writer =
      writer
      # Currency type (5 bits)
      |> PacketWriter.write_bits(type_int, 5)
      # Amount (uint64)
      |> PacketWriter.write_u64(packet.amount)
      # Unknown0 (always 0)
      |> PacketWriter.write_u64(0)
      # Unknown1 (always 0)
      |> PacketWriter.write_u64(0)

    {:ok, writer}
  end

  @doc """
  Get the integer value for a currency type.
  """
  @spec currency_type_to_int(atom()) :: non_neg_integer()
  def currency_type_to_int(type) do
    Map.get(@currency_types, type, 1)
  end
end
