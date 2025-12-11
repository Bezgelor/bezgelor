defmodule BezgelorWorld.Encounter.Primitives.Telegraph do
  @moduledoc """
  Telegraph primitives for boss ability area indicators.

  Telegraphs are visual warnings that show players where damage will occur.
  WildStar is famous for its telegraph system, making this a critical
  component of encounter design.

  ## Telegraph Shapes

  - `:circle` - Circular AoE, defined by radius
  - `:cone` - Frontal cone, defined by angle and length
  - `:line` - Linear AoE, defined by width and length
  - `:donut` - Ring shape, defined by inner and outer radius
  - `:cross` - Plus-shaped AoE, defined by width and length
  - `:room_wide` - Entire room (typically used for "get in safe zone")
  - `:rectangle` - Rectangular area
  - `:wave` - Expanding wave from center

  ## Telegraph Colors

  - `:red` - Hostile damage (default)
  - `:blue` - Friendly/heal areas
  - `:yellow` - Warning/debuff areas
  - `:green` - Safe zones

  ## Example Usage

      ability :cleave, cooldown: 8000 do
        telegraph :cone, angle: 90, length: 15, color: :red, duration: 2000
        damage 8000, type: :physical
      end

      ability :meteor, cooldown: 30000, target: :random do
        telegraph :circle, radius: 8, color: :red, duration: 3000
        damage 15000, type: :fire
      end
  """

  @type shape :: :circle | :cone | :line | :donut | :cross | :room_wide | :rectangle | :wave
  @type color :: :red | :blue | :yellow | :green | :purple | :orange

  @doc """
  Defines a telegraph for the current ability.

  ## Shape Options

  ### Circle
    - `:radius` - Radius in meters (required)

  ### Cone
    - `:angle` - Cone angle in degrees (required)
    - `:length` - Cone length in meters (required)

  ### Line
    - `:width` - Line width in meters (required)
    - `:length` - Line length in meters (required)

  ### Donut
    - `:inner_radius` - Inner safe zone radius (required)
    - `:outer_radius` - Outer damage radius (required)

  ### Cross
    - `:width` - Arm width in meters (required)
    - `:length` - Arm length in meters (required)

  ### Rectangle
    - `:width` - Rectangle width (required)
    - `:length` - Rectangle length (required)

  ## Common Options
    - `:duration` - How long telegraph is visible in ms (default: 2000)
    - `:color` - Telegraph color (default: :red)
    - `:offset` - Offset from cast position
    - `:rotation` - Telegraph rotation in degrees
    - `:delay` - Delay before damage hits after telegraph ends (default: 0)
  """
  defmacro telegraph(shape, opts \\ []) do
    quote do
      telegraph_data = build_telegraph(unquote(shape), unquote(opts))

      effect = %{
        type: :telegraph,
        shape: unquote(shape),
        params: telegraph_data,
        duration: Keyword.get(unquote(opts), :duration, 2000),
        color: Keyword.get(unquote(opts), :color, :red),
        delay: Keyword.get(unquote(opts), :delay, 0)
      }

      ability = Module.get_attribute(__MODULE__, :current_ability)
      updated = Map.update!(ability, :effects, &[effect | &1])
      Module.put_attribute(__MODULE__, :current_ability, updated)
    end
  end

  @doc """
  Builds telegraph parameters based on shape type.
  """
  def build_telegraph(:circle, opts) do
    %{
      radius: Keyword.fetch!(opts, :radius),
      segments: Keyword.get(opts, :segments, 32)
    }
  end

  def build_telegraph(:cone, opts) do
    %{
      angle: Keyword.fetch!(opts, :angle),
      length: Keyword.fetch!(opts, :length),
      segments: Keyword.get(opts, :segments, 16)
    }
  end

  def build_telegraph(:line, opts) do
    %{
      width: Keyword.fetch!(opts, :width),
      length: Keyword.fetch!(opts, :length)
    }
  end

  def build_telegraph(:donut, opts) do
    %{
      inner_radius: Keyword.fetch!(opts, :inner_radius),
      outer_radius: Keyword.fetch!(opts, :outer_radius),
      segments: Keyword.get(opts, :segments, 32)
    }
  end

  def build_telegraph(:cross, opts) do
    %{
      width: Keyword.fetch!(opts, :width),
      length: Keyword.fetch!(opts, :length)
    }
  end

  def build_telegraph(:rectangle, opts) do
    %{
      width: Keyword.fetch!(opts, :width),
      length: Keyword.fetch!(opts, :length)
    }
  end

  def build_telegraph(:wave, opts) do
    %{
      start_radius: Keyword.get(opts, :start_radius, 0),
      end_radius: Keyword.fetch!(opts, :end_radius),
      width: Keyword.get(opts, :width, 3),
      speed: Keyword.get(opts, :speed, 10)
    }
  end

  def build_telegraph(:room_wide, _opts) do
    %{full_room: true}
  end

  @doc """
  Creates a multi-telegraph pattern (multiple telegraphs in sequence or parallel).
  """
  defmacro telegraph_pattern(pattern_type, opts \\ [], do: block) do
    quote do
      pattern_data = %{
        type: unquote(pattern_type),
        delay_between: Keyword.get(unquote(opts), :delay, 500),
        telegraphs: []
      }

      Module.put_attribute(__MODULE__, :current_pattern, pattern_data)
      unquote(block)
      pattern = Module.get_attribute(__MODULE__, :current_pattern)
      Module.delete_attribute(__MODULE__, :current_pattern)

      effect = %{type: :telegraph_pattern, pattern: pattern}
      ability = Module.get_attribute(__MODULE__, :current_ability)
      updated = Map.update!(ability, :effects, &[effect | &1])
      Module.put_attribute(__MODULE__, :current_ability, updated)
    end
  end

  @doc """
  Adds a telegraph to the current pattern.
  """
  defmacro pattern_telegraph(shape, opts \\ []) do
    quote do
      telegraph_data = build_telegraph(unquote(shape), unquote(opts))

      tele = %{
        shape: unquote(shape),
        params: telegraph_data,
        duration: Keyword.get(unquote(opts), :duration, 2000),
        color: Keyword.get(unquote(opts), :color, :red),
        offset: Keyword.get(unquote(opts), :offset, {0, 0, 0})
      }

      pattern = Module.get_attribute(__MODULE__, :current_pattern)
      updated = Map.update!(pattern, :telegraphs, &[tele | &1])
      Module.put_attribute(__MODULE__, :current_pattern, updated)
    end
  end

  @doc """
  Creates a safe zone telegraph (inverted - stand inside to avoid damage).
  """
  defmacro telegraph_safe_zone(shape, opts \\ []) do
    quote do
      # Safe zones are telegraphs with inverted damage logic
      telegraph_data = build_telegraph(unquote(shape), unquote(opts))

      effect = %{
        type: :safe_zone,
        shape: unquote(shape),
        params: telegraph_data,
        duration: Keyword.get(unquote(opts), :duration, 2000),
        color: Keyword.get(unquote(opts), :color, :green)
      }

      ability = Module.get_attribute(__MODULE__, :current_ability)
      updated = Map.update!(ability, :effects, &[effect | &1])
      Module.put_attribute(__MODULE__, :current_ability, updated)
    end
  end

  @doc """
  Creates a rotating telegraph that sweeps around.
  """
  defmacro rotating_telegraph(shape, opts \\ []) do
    quote do
      telegraph_data = build_telegraph(unquote(shape), unquote(opts))

      effect = %{
        type: :rotating_telegraph,
        shape: unquote(shape),
        params: telegraph_data,
        duration: Keyword.get(unquote(opts), :duration, 5000),
        color: Keyword.get(unquote(opts), :color, :red),
        rotation_speed: Keyword.get(unquote(opts), :rotation_speed, 45),
        rotations: Keyword.get(unquote(opts), :rotations, 1)
      }

      ability = Module.get_attribute(__MODULE__, :current_ability)
      updated = Map.update!(ability, :effects, &[effect | &1])
      Module.put_attribute(__MODULE__, :current_ability, updated)
    end
  end
end
