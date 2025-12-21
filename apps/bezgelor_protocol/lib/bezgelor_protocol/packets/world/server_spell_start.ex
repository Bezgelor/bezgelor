defmodule BezgelorProtocol.Packets.World.ServerSpellStart do
  @moduledoc """
  Spell cast started notification.

  ## Overview

  Sent when a spell cast begins. Used to show the cast bar on clients.
  Instant spells (cast_time = 0) may skip this and go directly to ServerSpellGo.

  ## Wire Format (per NexusForever)

  ```
  casting_id           : uint32    - Unique cast ID for this spell instance
  spell4_id            : 18 bits   - Spell ID
  root_spell4_id       : 18 bits   - Root spell ID (0 if not chained)
  parent_spell4_id     : 18 bits   - Parent spell ID (0 if not chained)
  caster_id            : uint32    - Entity ID of caster
  unknown20            : uint16    - Unknown field
  primary_target_id    : uint32    - Target entity ID
  field_position       : Position  - Caster position (3x float32)
  yaw                  : float32   - Caster rotation
  initial_positions    : list      - List of initial position data
  telegraph_positions  : list      - List of telegraph position data
  user_initiated       : 1 bit     - True if player initiated cast
  use_creature_overrides : 1 bit   - Creature override flag
  ```
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [
    :casting_id,
    :spell4_id,
    :root_spell4_id,
    :parent_spell4_id,
    :caster_id,
    :unknown20,
    :primary_target_id,
    :field_position,
    :yaw,
    :initial_positions,
    :telegraph_positions,
    :user_initiated,
    :use_creature_overrides
  ]

  @type position :: {float(), float(), float()}

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

  @type t :: %__MODULE__{
          casting_id: non_neg_integer(),
          spell4_id: non_neg_integer(),
          root_spell4_id: non_neg_integer(),
          parent_spell4_id: non_neg_integer(),
          caster_id: non_neg_integer(),
          unknown20: non_neg_integer(),
          primary_target_id: non_neg_integer(),
          field_position: position(),
          yaw: float(),
          initial_positions: [initial_position()],
          telegraph_positions: [telegraph_position()],
          user_initiated: boolean(),
          use_creature_overrides: boolean()
        }

  @impl true
  def opcode, do: :server_spell_start

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    {pos_x, pos_y, pos_z} = packet.field_position

    writer =
      writer
      |> PacketWriter.write_u32(packet.casting_id)
      |> PacketWriter.write_bits(packet.spell4_id, 18)
      |> PacketWriter.write_bits(packet.root_spell4_id, 18)
      |> PacketWriter.write_bits(packet.parent_spell4_id, 18)
      |> PacketWriter.write_u32(packet.caster_id)
      |> PacketWriter.write_u16(packet.unknown20)
      |> PacketWriter.write_u32(packet.primary_target_id)
      # Position
      |> PacketWriter.write_f32(pos_x)
      |> PacketWriter.write_f32(pos_y)
      |> PacketWriter.write_f32(pos_z)
      |> PacketWriter.write_f32(packet.yaw)
      # Initial positions count and data
      |> PacketWriter.write_bits(length(packet.initial_positions), 8)

    writer = Enum.reduce(packet.initial_positions, writer, &write_initial_position/2)

    # Telegraph positions count and data
    writer = PacketWriter.write_bits(writer, length(packet.telegraph_positions), 8)
    writer = Enum.reduce(packet.telegraph_positions, writer, &write_telegraph_position/2)

    # Flags (1 bit each)
    writer =
      writer
      |> PacketWriter.write_bits(if(packet.user_initiated, do: 1, else: 0), 1)
      |> PacketWriter.write_bits(if(packet.use_creature_overrides, do: 1, else: 0), 1)
      |> PacketWriter.flush_bits()

    {:ok, writer}
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

  @doc """
  Create a spell start packet for a player-initiated spell.
  """
  @spec new(map()) :: t()
  def new(opts) do
    caster_id = opts[:caster_id] || 0
    position = opts[:position] || {0.0, 0.0, 0.0}

    %__MODULE__{
      casting_id: opts[:casting_id] || 1,
      spell4_id: opts[:spell4_id] || 0,
      root_spell4_id: opts[:root_spell4_id] || 0,
      parent_spell4_id: opts[:parent_spell4_id] || 0,
      caster_id: caster_id,
      unknown20: opts[:unknown20] || 0,
      primary_target_id: opts[:primary_target_id] || caster_id,
      field_position: position,
      yaw: opts[:yaw] || 0.0,
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
      user_initiated: opts[:user_initiated] || true,
      use_creature_overrides: opts[:use_creature_overrides] || false
    }
  end
end
