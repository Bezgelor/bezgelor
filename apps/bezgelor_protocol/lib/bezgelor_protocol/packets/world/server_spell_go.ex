defmodule BezgelorProtocol.Packets.World.ServerSpellGo do
  @moduledoc """
  Spell execution notification.

  ## Overview

  Sent when a spell finishes casting and executes its effects.
  Contains target information, effect results, and damage data.

  ## Wire Format (per NexusForever)

  ```
  server_unique_id     : uint32    - Matches casting_id from ServerSpellStart
  b_ignore_cooldown    : 1 bit     - Whether to ignore cooldown
  primary_destination  : Position  - Primary target position (3x float32)
  target_info_data     : list      - List of affected targets with effects
  initial_positions    : list      - Position data
  telegraph_positions  : list      - Telegraph data
  missile_info         : list      - Missile trajectory data
  phase                : int8      - Spell phase (-1 for single phase)
  ```
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  import Bitwise

  defstruct [
    :server_unique_id,
    :b_ignore_cooldown,
    :primary_destination,
    :target_info_data,
    :initial_positions,
    :telegraph_positions,
    :missile_info,
    :phase
  ]

  @type position :: {float(), float(), float()}

  @type damage_description :: %{
          raw_damage: non_neg_integer(),
          raw_scaled_damage: non_neg_integer(),
          absorbed_amount: non_neg_integer(),
          shield_absorb_amount: non_neg_integer(),
          adjusted_damage: non_neg_integer(),
          overkill_amount: non_neg_integer(),
          killed_target: boolean(),
          combat_result: non_neg_integer(),
          damage_type: non_neg_integer()
        }

  @type effect_info :: %{
          spell4_effect_id: non_neg_integer(),
          effect_unique_id: non_neg_integer(),
          delay_time: non_neg_integer(),
          time_remaining: integer(),
          info_type: non_neg_integer(),
          damage_description: damage_description() | nil
        }

  @type target_info :: %{
          unit_id: non_neg_integer(),
          ndx: non_neg_integer(),
          target_flags: non_neg_integer(),
          instance_count: non_neg_integer(),
          combat_result: non_neg_integer(),
          effect_info_data: [effect_info()]
        }

  @type initial_position :: %{
          unit_id: non_neg_integer(),
          target_flags: non_neg_integer(),
          position: position(),
          yaw: float(),
          pitch: float()
        }

  @type telegraph_position :: %{
          telegraph_id: non_neg_integer(),
          attached_unit_id: non_neg_integer(),
          target_flags: non_neg_integer(),
          position: position(),
          yaw: float(),
          pitch: float()
        }

  @type missile_info :: %{
          caster_position: position(),
          missile_travel_time: non_neg_integer(),
          target_id: non_neg_integer(),
          target_position: position(),
          hit_position: boolean()
        }

  @type t :: %__MODULE__{
          server_unique_id: non_neg_integer(),
          b_ignore_cooldown: boolean(),
          primary_destination: position(),
          target_info_data: [target_info()],
          initial_positions: [initial_position()],
          telegraph_positions: [telegraph_position()],
          missile_info: [missile_info()],
          phase: integer()
        }

  @impl true
  def opcode, do: :server_spell_go

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    {dest_x, dest_y, dest_z} = packet.primary_destination

    writer =
      writer
      |> PacketWriter.write_u32(packet.server_unique_id)
      |> PacketWriter.write_bits(if(packet.b_ignore_cooldown, do: 1, else: 0), 1)
      |> PacketWriter.write_f32(dest_x)
      |> PacketWriter.write_f32(dest_y)
      |> PacketWriter.write_f32(dest_z)
      # Target info count and data
      |> PacketWriter.write_bits(length(packet.target_info_data), 8)

    writer = Enum.reduce(packet.target_info_data, writer, &write_target_info/2)

    # Initial positions
    writer = PacketWriter.write_bits(writer, length(packet.initial_positions), 8)
    writer = Enum.reduce(packet.initial_positions, writer, &write_initial_position/2)

    # Telegraph positions
    writer = PacketWriter.write_bits(writer, length(packet.telegraph_positions), 8)
    writer = Enum.reduce(packet.telegraph_positions, writer, &write_telegraph_position/2)

    # Missile info
    writer = PacketWriter.write_bits(writer, length(packet.missile_info), 8)
    writer = Enum.reduce(packet.missile_info, writer, &write_missile_info/2)

    # Phase (signed byte - convert to unsigned for writing)
    phase_unsigned = packet.phase &&& 0xFF
    writer =
      writer
      |> PacketWriter.write_bits(phase_unsigned, 8)
      |> PacketWriter.flush_bits()

    {:ok, writer}
  end

  defp write_target_info(target, writer) do
    writer =
      writer
      |> PacketWriter.write_u32(target.unit_id)
      |> PacketWriter.write_u8(target.ndx)
      |> PacketWriter.write_u8(target.target_flags)
      |> PacketWriter.write_u16(target.instance_count)
      |> PacketWriter.write_bits(target.combat_result, 4)
      |> PacketWriter.write_bits(length(target.effect_info_data), 8)

    Enum.reduce(target.effect_info_data, writer, &write_effect_info/2)
  end

  defp write_effect_info(effect, writer) do
    writer =
      writer
      |> PacketWriter.write_bits(effect.spell4_effect_id, 19)
      |> PacketWriter.write_u32(effect.effect_unique_id)
      |> PacketWriter.write_u32(effect.delay_time)
      |> PacketWriter.write_i32(effect.time_remaining)
      |> PacketWriter.write_bits(effect.info_type, 2)

    if effect.info_type == 1 and effect.damage_description != nil do
      write_damage_description(effect.damage_description, writer)
    else
      # Write 1 bit for no data case
      PacketWriter.write_bits(writer, 0, 1)
    end
  end

  defp write_damage_description(dmg, writer) do
    writer
    |> PacketWriter.write_u32(dmg.raw_damage)
    |> PacketWriter.write_u32(dmg.raw_scaled_damage)
    |> PacketWriter.write_u32(dmg.absorbed_amount)
    |> PacketWriter.write_u32(dmg.shield_absorb_amount)
    |> PacketWriter.write_u32(dmg.adjusted_damage)
    |> PacketWriter.write_u32(dmg.overkill_amount)
    |> PacketWriter.write_u32(0)
    |> PacketWriter.write_bits(if(dmg.killed_target, do: 1, else: 0), 1)
    |> PacketWriter.write_bits(dmg.combat_result, 4)
    |> PacketWriter.write_bits(dmg.damage_type, 3)
    # Unknown structure count (0)
    |> PacketWriter.write_bits(0, 8)
  end

  defp write_initial_position(pos, writer) do
    {x, y, z} = pos.position

    writer
    |> PacketWriter.write_u32(pos.unit_id)
    |> PacketWriter.write_u8(pos.target_flags)
    |> PacketWriter.write_f32(x)
    |> PacketWriter.write_f32(y)
    |> PacketWriter.write_f32(z)
    |> PacketWriter.write_f32(pos.yaw)
    |> PacketWriter.write_f32(pos.pitch)
  end

  defp write_telegraph_position(pos, writer) do
    {x, y, z} = pos.position

    writer
    |> PacketWriter.write_u16(pos.telegraph_id)
    |> PacketWriter.write_u32(pos.attached_unit_id)
    |> PacketWriter.write_u8(pos.target_flags)
    |> PacketWriter.write_f32(x)
    |> PacketWriter.write_f32(y)
    |> PacketWriter.write_f32(z)
    |> PacketWriter.write_f32(pos.yaw)
    |> PacketWriter.write_f32(pos.pitch)
  end

  defp write_missile_info(missile, writer) do
    {cx, cy, cz} = missile.caster_position
    {tx, ty, tz} = missile.target_position

    writer
    |> PacketWriter.write_f32(cx)
    |> PacketWriter.write_f32(cy)
    |> PacketWriter.write_f32(cz)
    |> PacketWriter.write_u32(missile.missile_travel_time)
    |> PacketWriter.write_u32(missile.target_id)
    |> PacketWriter.write_f32(tx)
    |> PacketWriter.write_f32(ty)
    |> PacketWriter.write_f32(tz)
    |> PacketWriter.write_bits(if(missile.hit_position, do: 1, else: 0), 1)
  end

  @doc """
  Create a simple spell go packet for instant spell execution.
  """
  @spec new(map()) :: t()
  def new(opts) do
    caster_id = opts[:caster_id] || 0
    position = opts[:position] || {0.0, 0.0, 0.0}

    %__MODULE__{
      server_unique_id: opts[:casting_id] || 1,
      b_ignore_cooldown: opts[:ignore_cooldown] || false,
      primary_destination: opts[:destination] || position,
      target_info_data: opts[:target_info] || [],
      initial_positions:
        opts[:initial_positions] ||
          [
            %{
              unit_id: caster_id,
              target_flags: 3,
              position: position,
              yaw: opts[:yaw] || 0.0,
              pitch: 0.0
            }
          ],
      telegraph_positions: opts[:telegraph_positions] || [],
      missile_info: opts[:missile_info] || [],
      phase: opts[:phase] || -1
    }
  end

  @doc """
  Build a target info entry for a spell effect.
  """
  @spec build_target_info(non_neg_integer(), non_neg_integer(), [effect_info()]) :: target_info()
  def build_target_info(unit_id, spell4_effect_id, effects \\ []) do
    %{
      unit_id: unit_id,
      ndx: 0,
      target_flags: 1,
      instance_count: 1,
      # Hit
      combat_result: 2,
      effect_info_data:
        if effects == [] do
          [
            %{
              spell4_effect_id: spell4_effect_id,
              effect_unique_id: 1,
              delay_time: 0,
              time_remaining: -1,
              info_type: 0,
              damage_description: nil
            }
          ]
        else
          effects
        end
    }
  end
end
