defmodule BezgelorWorld.Encounter.Primitives.Movement do
  @moduledoc """
  Movement primitives for boss abilities and mechanics.

  Handles forced player movement (knockbacks, pulls) and boss
  movement abilities (charges, teleports, jumps).

  ## Player Movement Types
  - `:knockback` - Push players away from source
  - `:pull` - Pull players toward source
  - `:grip` - Pull to specific location
  - `:throw` - Throw player to location

  ## Boss Movement Types
  - `:charge` - Rush toward target
  - `:leap` - Jump to target location
  - `:teleport` - Instant reposition
  - `:patrol` - Move between waypoints

  ## Example Usage

      ability :thunderclap, cooldown: 15000 do
        telegraph :circle, radius: 15
        damage 5000, type: :physical
        movement :knockback, distance: 10
      end

      ability :death_grip, cooldown: 30000, target: :farthest do
        movement :grip, to: :boss
        debuff :rooted, duration: 3000
      end
  """

  @type player_movement :: :knockback | :pull | :grip | :throw | :root | :slow
  @type boss_movement :: :charge | :leap | :teleport | :patrol | :reposition

  @doc """
  Applies forced movement to targets.

  ## Options

  ### Knockback
    - `:distance` - How far to push (required)
    - `:height` - Vertical component
    - `:source` - Knockback origin (:boss, :ability, :target)

  ### Pull/Grip
    - `:to` - Pull destination (:boss, :center, {x,y,z})
    - `:speed` - Pull speed

  ### Throw
    - `:to` - Throw destination
    - `:arc_height` - Height of throw arc
    - `:damage_on_land` - Damage when landing

  ### Root/Slow
    - `:duration` - Effect duration
    - `:slow_percent` - Speed reduction for slow
  """
  defmacro movement(type, opts \\ []) do
    quote do
      movement_data = build_movement(unquote(type), unquote(opts))

      effect = %{
        type: :movement,
        movement_type: unquote(type),
        params: movement_data
      }

      ability = Module.get_attribute(__MODULE__, :current_ability)
      updated = Map.update!(ability, :effects, &[effect | &1])
      Module.put_attribute(__MODULE__, :current_ability, updated)
    end
  end

  @doc """
  Builds movement parameters based on type.
  """
  def build_movement(:knockback, opts) do
    %{
      distance: Keyword.fetch!(opts, :distance),
      height: Keyword.get(opts, :height, 0),
      source: Keyword.get(opts, :source, :boss),
      damage_on_collision: Keyword.get(opts, :collision_damage, 0),
      stun_duration: Keyword.get(opts, :stun_duration, 0)
    }
  end

  def build_movement(:pull, opts) do
    %{
      to: Keyword.get(opts, :to, :boss),
      speed: Keyword.get(opts, :speed, 20),
      stop_distance: Keyword.get(opts, :stop_distance, 2)
    }
  end

  def build_movement(:grip, opts) do
    %{
      to: Keyword.fetch!(opts, :to),
      instant: Keyword.get(opts, :instant, false),
      root_after: Keyword.get(opts, :root_after, 0)
    }
  end

  def build_movement(:throw, opts) do
    %{
      to: Keyword.fetch!(opts, :to),
      arc_height: Keyword.get(opts, :arc_height, 10),
      travel_time: Keyword.get(opts, :travel_time, 1000),
      damage_on_land: Keyword.get(opts, :damage_on_land, 0),
      stun_on_land: Keyword.get(opts, :stun_on_land, 0)
    }
  end

  def build_movement(:root, opts) do
    %{
      duration: Keyword.fetch!(opts, :duration),
      breakable: Keyword.get(opts, :breakable, false),
      break_threshold: Keyword.get(opts, :break_threshold, 0)
    }
  end

  def build_movement(:slow, opts) do
    %{
      duration: Keyword.fetch!(opts, :duration),
      slow_percent: Keyword.get(opts, :slow_percent, 50),
      stacking: Keyword.get(opts, :stacking, false)
    }
  end

  @doc """
  Makes the boss perform a charge attack.

  ## Options
    - `:target` - Who to charge at
    - `:speed` - Charge speed
    - `:telegraph` - Whether to show path
    - `:damage` - Damage to targets in path
    - `:knockback` - Knockback targets hit
  """
  defmacro boss_charge(opts \\ []) do
    quote do
      effect = %{
        type: :boss_charge,
        target: Keyword.get(unquote(opts), :target, :tank),
        speed: Keyword.get(unquote(opts), :speed, 30),
        telegraph: Keyword.get(unquote(opts), :telegraph, true),
        telegraph_width: Keyword.get(unquote(opts), :width, 4),
        damage: Keyword.get(unquote(opts), :damage, 0),
        knockback_distance: Keyword.get(unquote(opts), :knockback, 0),
        stun_duration: Keyword.get(unquote(opts), :stun, 0),
        stop_at_target: Keyword.get(unquote(opts), :stop_at_target, true)
      }

      ability = Module.get_attribute(__MODULE__, :current_ability)
      updated = Map.update!(ability, :effects, &[effect | &1])
      Module.put_attribute(__MODULE__, :current_ability, updated)
    end
  end

  @doc """
  Makes the boss leap to a location.

  ## Options
    - `:target` - Where to leap (player or position)
    - `:travel_time` - Time in air
    - `:impact_radius` - AoE radius on landing
    - `:impact_damage` - Damage on landing
  """
  defmacro boss_leap(opts \\ []) do
    quote do
      effect = %{
        type: :boss_leap,
        target: Keyword.get(unquote(opts), :target, :random),
        travel_time: Keyword.get(unquote(opts), :travel_time, 1000),
        impact_radius: Keyword.get(unquote(opts), :impact_radius, 8),
        impact_damage: Keyword.get(unquote(opts), :impact_damage, 0),
        telegraph: Keyword.get(unquote(opts), :telegraph, true),
        leaves_void_zone: Keyword.get(unquote(opts), :leaves_void_zone, false)
      }

      ability = Module.get_attribute(__MODULE__, :current_ability)
      updated = Map.update!(ability, :effects, &[effect | &1])
      Module.put_attribute(__MODULE__, :current_ability, updated)
    end
  end

  @doc """
  Teleports the boss to a new location.

  ## Options
    - `:to` - Destination (position or :center, :edge, :random)
    - `:effect` - Visual effect on teleport
  """
  defmacro boss_teleport(opts \\ []) do
    quote do
      effect = %{
        type: :boss_teleport,
        to: Keyword.fetch!(unquote(opts), :to),
        fade_duration: Keyword.get(unquote(opts), :fade_duration, 500),
        visual_effect: Keyword.get(unquote(opts), :effect, :shadow)
      }

      ability = Module.get_attribute(__MODULE__, :current_ability)
      updated = Map.update!(ability, :effects, &[effect | &1])
      Module.put_attribute(__MODULE__, :current_ability, updated)
    end
  end

  @doc """
  Creates a series of waypoints for boss patrol/movement pattern.
  """
  defmacro boss_patrol(waypoints, opts \\ []) do
    quote do
      effect = %{
        type: :boss_patrol,
        waypoints: unquote(waypoints),
        speed: Keyword.get(unquote(opts), :speed, 5),
        loop: Keyword.get(unquote(opts), :loop, true),
        pause_at_waypoint: Keyword.get(unquote(opts), :pause, 0)
      }

      ability = Module.get_attribute(__MODULE__, :current_ability)
      updated = Map.update!(ability, :effects, &[effect | &1])
      Module.put_attribute(__MODULE__, :current_ability, updated)
    end
  end
end
