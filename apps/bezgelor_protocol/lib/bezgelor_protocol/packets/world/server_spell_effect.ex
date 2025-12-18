defmodule BezgelorProtocol.Packets.World.ServerSpellEffect do
  @moduledoc """
  Spell effect applied notification.

  ## Overview

  Sent when a spell effect is applied to a target. This includes
  damage, healing, buffs, and debuffs. Multiple effects can be
  sent for a single spell cast.

  ## Wire Format

  ```
  caster_guid  : uint64  - Entity that cast the spell
  target_guid  : uint64  - Entity affected
  spell_id     : uint32  - Spell that caused the effect
  effect_type  : uint8   - Type of effect (0=damage, 1=heal, etc.)
  amount       : int32   - Effect amount (damage/healing)
  flags        : uint8   - Effect flags (crit, absorb, miss, etc.)
  ```

  ## Effect Types

  | Value | Type | Description |
  |-------|------|-------------|
  | 0 | damage | Direct damage |
  | 1 | heal | Direct healing |
  | 2 | buff | Beneficial effect applied |
  | 3 | debuff | Harmful effect applied |
  | 4 | dot | Damage over time tick |
  | 5 | hot | Healing over time tick |

  ## Flags

  | Bit | Name | Description |
  |-----|------|-------------|
  | 0x01 | crit | Critical hit/heal |
  | 0x02 | absorb | Damage absorbed by shield |
  | 0x04 | miss | Attack missed |
  | 0x08 | dodge | Target dodged |
  | 0x10 | resist | Spell partially resisted |
  """

  @behaviour BezgelorProtocol.Packet.Writable

  import Bitwise

  alias BezgelorProtocol.PacketWriter
  alias BezgelorCore.SpellEffect

  # Effect flags
  @flag_crit 0x01
  @flag_absorb 0x02
  @flag_miss 0x04
  @flag_dodge 0x08
  @flag_resist 0x10

  defstruct [:caster_guid, :target_guid, :spell_id, :effect_type, :amount, :flags]

  @type effect_type :: :damage | :heal | :buff | :debuff | :dot | :hot
  @type flag :: :crit | :absorb | :miss | :dodge | :resist

  @type t :: %__MODULE__{
          caster_guid: non_neg_integer(),
          target_guid: non_neg_integer(),
          spell_id: non_neg_integer(),
          effect_type: effect_type(),
          amount: integer(),
          flags: [flag()]
        }

  @impl true
  def opcode, do: :server_spell_effect

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    effect_type_int = SpellEffect.type_to_int(packet.effect_type)
    flags_int = flags_to_int(packet.flags || [])

    # For signed int32, we write as bytes with signed encoding
    amount_bytes = <<packet.amount::32-little-signed>>

    writer =
      writer
      |> PacketWriter.write_u64(packet.caster_guid)
      |> PacketWriter.write_u64(packet.target_guid)
      |> PacketWriter.write_u32(packet.spell_id)
      |> PacketWriter.write_u8(effect_type_int)
      |> PacketWriter.write_bytes_bits(amount_bytes)
      |> PacketWriter.write_u8(flags_int)

    {:ok, writer}
  end

  @doc """
  Create a damage effect packet.
  """
  @spec damage(non_neg_integer(), non_neg_integer(), non_neg_integer(), integer(), boolean()) ::
          t()
  def damage(caster_guid, target_guid, spell_id, amount, is_crit \\ false) do
    flags = if is_crit, do: [:crit], else: []

    %__MODULE__{
      caster_guid: caster_guid,
      target_guid: target_guid,
      spell_id: spell_id,
      effect_type: :damage,
      amount: amount,
      flags: flags
    }
  end

  @doc """
  Create a healing effect packet.
  """
  @spec heal(non_neg_integer(), non_neg_integer(), non_neg_integer(), integer(), boolean()) ::
          t()
  def heal(caster_guid, target_guid, spell_id, amount, is_crit \\ false) do
    flags = if is_crit, do: [:crit], else: []

    %__MODULE__{
      caster_guid: caster_guid,
      target_guid: target_guid,
      spell_id: spell_id,
      effect_type: :heal,
      amount: amount,
      flags: flags
    }
  end

  @doc """
  Create a miss effect packet.
  """
  @spec miss(non_neg_integer(), non_neg_integer(), non_neg_integer()) :: t()
  def miss(caster_guid, target_guid, spell_id) do
    %__MODULE__{
      caster_guid: caster_guid,
      target_guid: target_guid,
      spell_id: spell_id,
      effect_type: :damage,
      amount: 0,
      flags: [:miss]
    }
  end

  @doc """
  Create a buff applied packet.
  """
  @spec buff(non_neg_integer(), non_neg_integer(), non_neg_integer(), integer()) :: t()
  def buff(caster_guid, target_guid, spell_id, amount \\ 0) do
    %__MODULE__{
      caster_guid: caster_guid,
      target_guid: target_guid,
      spell_id: spell_id,
      effect_type: :buff,
      amount: amount,
      flags: []
    }
  end

  # Private helpers

  defp flags_to_int(flags) when is_list(flags) do
    Enum.reduce(flags, 0, fn flag, acc ->
      acc ||| flag_to_int(flag)
    end)
  end

  defp flag_to_int(:crit), do: @flag_crit
  defp flag_to_int(:absorb), do: @flag_absorb
  defp flag_to_int(:miss), do: @flag_miss
  defp flag_to_int(:dodge), do: @flag_dodge
  defp flag_to_int(:resist), do: @flag_resist
  defp flag_to_int(_), do: 0

  @doc """
  Convert integer flags to list of atoms.
  """
  @spec int_to_flags(non_neg_integer()) :: [flag()]
  def int_to_flags(value) do
    []
    |> maybe_add_flag(value, @flag_crit, :crit)
    |> maybe_add_flag(value, @flag_absorb, :absorb)
    |> maybe_add_flag(value, @flag_miss, :miss)
    |> maybe_add_flag(value, @flag_dodge, :dodge)
    |> maybe_add_flag(value, @flag_resist, :resist)
  end

  defp maybe_add_flag(flags, value, bit, flag) do
    if (value &&& bit) != 0, do: [flag | flags], else: flags
  end
end
