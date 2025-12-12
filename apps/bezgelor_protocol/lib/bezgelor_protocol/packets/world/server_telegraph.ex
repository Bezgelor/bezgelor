defmodule BezgelorProtocol.Packets.World.ServerTelegraph do
  @moduledoc """
  Telegraph display packet.

  Tells clients to render a telegraph (damage area indicator).

  ## Overview

  WildStar's telegraph system is central to its action combat. Telegraphs
  show players where damage will land, giving them time to dodge. This
  packet sends the shape, position, duration, and color of a telegraph
  to render on the client.

  ## Wire Format

  ```
  caster_guid  : uint64  - Entity casting the spell
  spell_id     : uint32  - Spell ID (for reference)
  shape_type   : uint8   - Shape type (circle, cone, rectangle, donut)
  position_x   : float32 - X coordinate
  position_y   : float32 - Y coordinate
  position_z   : float32 - Z coordinate
  rotation     : float32 - Rotation in radians (for directional shapes)
  duration     : uint32  - Duration in milliseconds
  color        : uint8   - Color type (red, blue, yellow, green)
  params       : varies  - Shape-specific parameters
  ```

  ## Shape Types

  | Value | Type | Parameters |
  |-------|------|------------|
  | 0 | Circle | radius (float32) |
  | 1 | Cone | angle (float32), length (float32) |
  | 2 | Rectangle | width (float32), length (float32) |
  | 3 | Donut | inner_radius (float32), outer_radius (float32) |

  ## Colors

  | Value | Color | Usage |
  |-------|-------|-------|
  | 0 | Red | Enemy attacks |
  | 1 | Blue | Friendly abilities |
  | 2 | Yellow | Warning/neutral |
  | 3 | Green | Safe zones |
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  @shape_circle 0
  @shape_cone 1
  @shape_rectangle 2
  @shape_donut 3

  @color_red 0
  @color_blue 1
  @color_yellow 2
  @color_green 3

  defstruct [
    :caster_guid,
    :spell_id,
    :shape,
    :position,
    :rotation,
    :duration,
    :color,
    :params
  ]

  @type shape :: :circle | :cone | :rectangle | :donut
  @type color :: :red | :blue | :yellow | :green
  @type position :: {float(), float(), float()}

  @type t :: %__MODULE__{
          caster_guid: non_neg_integer(),
          spell_id: non_neg_integer() | nil,
          shape: shape(),
          position: position(),
          rotation: float() | nil,
          duration: non_neg_integer(),
          color: color(),
          params: map()
        }

  @impl true
  def opcode, do: :server_telegraph

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_uint64(packet.caster_guid)
      |> PacketWriter.write_uint32(packet.spell_id || 0)
      |> PacketWriter.write_byte(shape_to_int(packet.shape))
      |> write_position(packet.position)
      |> PacketWriter.write_float32(packet.rotation || 0.0)
      |> PacketWriter.write_uint32(packet.duration)
      |> PacketWriter.write_byte(color_to_int(packet.color))
      |> write_shape_params(packet.shape, packet.params)

    {:ok, writer}
  end

  # ============================================================================
  # Constructors
  # ============================================================================

  @doc """
  Create a circle telegraph.

  ## Parameters

  - `caster_guid` - Entity casting the ability
  - `position` - Center point {x, y, z}
  - `radius` - Circle radius
  - `duration` - How long to display in milliseconds
  - `color` - Telegraph color (:red, :blue, :yellow, :green)
  """
  @spec circle(non_neg_integer(), position(), float(), non_neg_integer(), color()) :: t()
  def circle(caster_guid, position, radius, duration, color) do
    %__MODULE__{
      caster_guid: caster_guid,
      shape: :circle,
      position: position,
      duration: duration,
      color: color,
      params: %{radius: radius}
    }
  end

  @doc """
  Create a cone telegraph.

  ## Parameters

  - `caster_guid` - Entity casting the ability
  - `position` - Cone origin point {x, y, z}
  - `angle` - Cone angle in degrees (e.g., 90 for quarter circle)
  - `length` - Cone length from origin
  - `rotation` - Direction the cone faces (radians)
  - `duration` - How long to display in milliseconds
  - `color` - Telegraph color
  """
  @spec cone(non_neg_integer(), position(), float(), float(), float(), non_neg_integer(), color()) ::
          t()
  def cone(caster_guid, position, angle, length, rotation, duration, color) do
    %__MODULE__{
      caster_guid: caster_guid,
      shape: :cone,
      position: position,
      rotation: rotation,
      duration: duration,
      color: color,
      params: %{angle: angle, length: length}
    }
  end

  @doc """
  Create a rectangle telegraph.

  ## Parameters

  - `caster_guid` - Entity casting the ability
  - `position` - Rectangle center point {x, y, z}
  - `width` - Rectangle width
  - `length` - Rectangle length
  - `rotation` - Direction the rectangle faces (radians)
  - `duration` - How long to display in milliseconds
  - `color` - Telegraph color
  """
  @spec rectangle(
          non_neg_integer(),
          position(),
          float(),
          float(),
          float(),
          non_neg_integer(),
          color()
        ) :: t()
  def rectangle(caster_guid, position, width, length, rotation, duration, color) do
    %__MODULE__{
      caster_guid: caster_guid,
      shape: :rectangle,
      position: position,
      rotation: rotation,
      duration: duration,
      color: color,
      params: %{width: width, length: length}
    }
  end

  @doc """
  Create a donut/ring telegraph.

  ## Parameters

  - `caster_guid` - Entity casting the ability
  - `position` - Donut center point {x, y, z}
  - `inner_radius` - Inner safe zone radius
  - `outer_radius` - Outer damage zone radius
  - `duration` - How long to display in milliseconds
  - `color` - Telegraph color
  """
  @spec donut(non_neg_integer(), position(), float(), float(), non_neg_integer(), color()) :: t()
  def donut(caster_guid, position, inner_radius, outer_radius, duration, color) do
    %__MODULE__{
      caster_guid: caster_guid,
      shape: :donut,
      position: position,
      duration: duration,
      color: color,
      params: %{inner_radius: inner_radius, outer_radius: outer_radius}
    }
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp write_position(writer, {x, y, z}) do
    writer
    |> PacketWriter.write_float32(x)
    |> PacketWriter.write_float32(y)
    |> PacketWriter.write_float32(z)
  end

  defp write_shape_params(writer, :circle, %{radius: radius}) do
    PacketWriter.write_float32(writer, radius)
  end

  defp write_shape_params(writer, :cone, %{angle: angle, length: length}) do
    writer
    |> PacketWriter.write_float32(angle)
    |> PacketWriter.write_float32(length)
  end

  defp write_shape_params(writer, :rectangle, %{width: width, length: length}) do
    writer
    |> PacketWriter.write_float32(width)
    |> PacketWriter.write_float32(length)
  end

  defp write_shape_params(writer, :donut, %{inner_radius: inner, outer_radius: outer}) do
    writer
    |> PacketWriter.write_float32(inner)
    |> PacketWriter.write_float32(outer)
  end

  defp shape_to_int(:circle), do: @shape_circle
  defp shape_to_int(:cone), do: @shape_cone
  defp shape_to_int(:rectangle), do: @shape_rectangle
  defp shape_to_int(:donut), do: @shape_donut
  defp shape_to_int(_), do: @shape_circle

  defp color_to_int(:red), do: @color_red
  defp color_to_int(:blue), do: @color_blue
  defp color_to_int(:yellow), do: @color_yellow
  defp color_to_int(:green), do: @color_green
  defp color_to_int(_), do: @color_red
end
