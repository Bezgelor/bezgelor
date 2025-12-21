defmodule BezgelorProtocol.Packets.World.ServerBuffApply do
  @moduledoc """
  Buff/debuff application notification.

  ## Wire Format

  ```
  target_guid : uint64  - Entity receiving the buff
  caster_guid : uint64  - Entity that applied the buff
  buff_id     : uint32  - Unique buff instance ID
  spell_id    : uint32  - Spell that created this buff
  buff_type   : uint8   - Type (0=absorb, 1=stat_mod, etc.)
  amount      : int32   - Effect amount
  duration    : uint32  - Duration in milliseconds
  is_debuff   : uint8   - 1 if debuff, 0 if buff
  ```
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter
  alias BezgelorCore.BuffDebuff

  defstruct [
    :target_guid,
    :caster_guid,
    :buff_id,
    :spell_id,
    :buff_type,
    :amount,
    :duration,
    :is_debuff
  ]

  @type t :: %__MODULE__{
          target_guid: non_neg_integer(),
          caster_guid: non_neg_integer(),
          buff_id: non_neg_integer(),
          spell_id: non_neg_integer(),
          buff_type: non_neg_integer(),
          amount: integer(),
          duration: non_neg_integer(),
          is_debuff: boolean()
        }

  @impl true
  def opcode, do: :server_buff_apply

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    is_debuff_byte = if packet.is_debuff, do: 1, else: 0
    amount_bytes = <<packet.amount::32-little-signed>>

    writer =
      writer
      |> PacketWriter.write_u64(packet.target_guid)
      |> PacketWriter.write_u64(packet.caster_guid)
      |> PacketWriter.write_u32(packet.buff_id)
      |> PacketWriter.write_u32(packet.spell_id)
      |> PacketWriter.write_u8(packet.buff_type)
      |> PacketWriter.write_bytes_bits(amount_bytes)
      |> PacketWriter.write_u32(packet.duration)
      |> PacketWriter.write_u8(is_debuff_byte)

    {:ok, writer}
  end

  @doc """
  Create a new buff apply packet.
  """
  @spec new(
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          atom() | non_neg_integer(),
          integer(),
          non_neg_integer(),
          boolean()
        ) :: t()
  def new(target_guid, caster_guid, buff_id, spell_id, buff_type, amount, duration, is_debuff) do
    buff_type_int = if is_atom(buff_type), do: BuffDebuff.type_to_int(buff_type), else: buff_type

    %__MODULE__{
      target_guid: target_guid,
      caster_guid: caster_guid,
      buff_id: buff_id,
      spell_id: spell_id,
      buff_type: buff_type_int,
      amount: amount,
      duration: duration,
      is_debuff: is_debuff
    }
  end
end
