defmodule BezgelorProtocol.Packets.World.ServerCombatLog do
  @moduledoc """
  Combat log entry packet.

  ## Overview

  Sent when combat events occur (damage, healing, death, etc.).
  The client uses these packets to display damage numbers, combat log entries,
  and trigger visual feedback.

  IMPORTANT: This packet must be sent BEFORE ServerSpellGo for damage to display correctly.

  ## Wire Format (per NexusForever)

  ```
  type      : 6 bits   - CombatLogType enum value
  data      : varies   - Type-specific combat log data
  ```

  ## Combat Log Types

  - 0: Absorption
  - 3: Damage (most common for spells)
  - 12: Heal
  - 22: Death
  - See CombatLogType enum for full list
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  # Combat log types (from NexusForever CombatLogType enum)
  @type_absorption 0
  @type_damage 3
  @type_heal 12
  @type_death 22
  @type_experience 27

  defstruct [:type, :data]

  @type combat_result :: non_neg_integer()
  @type damage_type :: non_neg_integer()
  @type effect_type :: non_neg_integer()

  @type cast_data :: %{
          caster_id: non_neg_integer(),
          target_id: non_neg_integer(),
          spell_id: non_neg_integer(),
          combat_result: combat_result()
        }

  @type damage_data :: %{
          mitigated_damage: non_neg_integer(),
          raw_damage: non_neg_integer(),
          shield: non_neg_integer(),
          absorption: non_neg_integer(),
          overkill: non_neg_integer(),
          glance: non_neg_integer(),
          target_vulnerable: boolean(),
          killed: boolean(),
          periodic: boolean(),
          damage_type: damage_type(),
          effect_type: effect_type(),
          cast_data: cast_data()
        }

  @type heal_data :: %{
          heal_amount: non_neg_integer(),
          overheal: non_neg_integer(),
          absorption: non_neg_integer(),
          periodic: boolean(),
          cast_data: cast_data()
        }

  @type t :: %__MODULE__{
          type: non_neg_integer(),
          data: damage_data() | heal_data() | map()
        }

  @impl true
  def opcode, do: :server_combat_log

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_bits(packet.type, 6)

    writer = write_combat_log_data(packet.type, packet.data, writer)
    writer = PacketWriter.flush_bits(writer)

    {:ok, writer}
  end

  # Write damage combat log data
  defp write_combat_log_data(@type_damage, data, writer) do
    writer
    |> PacketWriter.write_u32(data.mitigated_damage)
    |> PacketWriter.write_u32(data.raw_damage)
    |> PacketWriter.write_u32(data.shield)
    |> PacketWriter.write_u32(data.absorption)
    |> PacketWriter.write_u32(data.overkill)
    |> PacketWriter.write_u32(data.glance)
    |> PacketWriter.write_bits(if(data.target_vulnerable, do: 1, else: 0), 1)
    |> PacketWriter.write_bits(if(data.killed, do: 1, else: 0), 1)
    |> PacketWriter.write_bits(if(data.periodic, do: 1, else: 0), 1)
    |> PacketWriter.write_bits(data.damage_type, 3)
    |> PacketWriter.write_bits(data.effect_type, 8)
    |> write_cast_data(data.cast_data)
  end

  # Write heal combat log data
  defp write_combat_log_data(@type_heal, data, writer) do
    writer
    |> PacketWriter.write_u32(data.heal_amount)
    |> PacketWriter.write_u32(data.overheal)
    |> PacketWriter.write_u32(data.absorption)
    |> PacketWriter.write_bits(if(data.periodic, do: 1, else: 0), 1)
    |> write_cast_data(data.cast_data)
  end

  # Fallback for unknown types
  defp write_combat_log_data(_type, _data, writer), do: writer

  # Write cast data (caster, target, spell, result)
  defp write_cast_data(writer, cast_data) do
    writer
    |> PacketWriter.write_u32(cast_data.caster_id)
    |> PacketWriter.write_u32(cast_data.target_id)
    |> PacketWriter.write_bits(cast_data.spell_id, 18)
    |> PacketWriter.write_bits(cast_data.combat_result, 4)
  end

  # Helper functions to create combat log packets

  @doc """
  Create a damage combat log packet.

  ## Parameters

  - caster_id: Unit ID of the damage source
  - target_id: Unit ID of the damage target
  - spell_id: Spell4 ID that caused the damage
  - damage: Amount of damage dealt
  - opts: Additional options
    - :damage_type - Type of damage (0=physical, 1=magic, 2=tech)
    - :effect_type - SpellEffectType enum (8=Damage, 10=Heal, etc.)
    - :combat_result - Result (1=crit, 2=hit)
    - :killed - Whether target was killed
    - :overkill - Damage beyond target's health
  """
  @spec damage(non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer(), keyword()) ::
          t()
  def damage(caster_id, target_id, spell_id, damage, opts \\ []) do
    combat_result = Keyword.get(opts, :combat_result, 2)
    # DamageType enum: 1=Physical, 3=Magic (default to magic for spells)
    damage_type = Keyword.get(opts, :damage_type, 3)
    # SpellEffectType.Damage = 0x0008 = 8 in WildStar
    effect_type = Keyword.get(opts, :effect_type, 8)
    killed = Keyword.get(opts, :killed, false)
    overkill = Keyword.get(opts, :overkill, 0)

    %__MODULE__{
      type: @type_damage,
      data: %{
        mitigated_damage: damage,
        raw_damage: damage,
        shield: 0,
        absorption: 0,
        overkill: overkill,
        glance: 0,
        target_vulnerable: false,
        killed: killed,
        periodic: false,
        damage_type: damage_type,
        effect_type: effect_type,
        cast_data: %{
          caster_id: caster_id,
          target_id: target_id,
          spell_id: spell_id,
          combat_result: combat_result
        }
      }
    }
  end

  @doc """
  Create a heal combat log packet.
  """
  @spec heal(non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer(), keyword()) ::
          t()
  def heal(caster_id, target_id, spell_id, amount, opts \\ []) do
    combat_result = Keyword.get(opts, :combat_result, 2)
    overheal = Keyword.get(opts, :overheal, 0)

    %__MODULE__{
      type: @type_heal,
      data: %{
        heal_amount: amount,
        overheal: overheal,
        absorption: 0,
        periodic: false,
        cast_data: %{
          caster_id: caster_id,
          target_id: target_id,
          spell_id: spell_id,
          combat_result: combat_result
        }
      }
    }
  end

  # Public accessors for type constants
  def type_damage, do: @type_damage
  def type_heal, do: @type_heal
  def type_death, do: @type_death
  def type_experience, do: @type_experience
  def type_absorption, do: @type_absorption
end
