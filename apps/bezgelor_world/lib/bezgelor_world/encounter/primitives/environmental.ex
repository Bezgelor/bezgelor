defmodule BezgelorWorld.Encounter.Primitives.Environmental do
  @moduledoc """
  Environmental hazard primitives for boss encounters.

  Many boss encounters feature environmental hazards that persist
  in the arena, creating positional challenges and area denial.

  ## Hazard Types

  - `:void_zone` - Persistent damage area on ground
  - `:fire` - Fire that spreads or persists
  - `:poison_cloud` - AoE damage that may expand
  - `:falling_debris` - Random danger from above
  - `:terrain_change` - Arena modifications
  - `:environmental_damage` - Room-wide periodic damage

  ## Example Usage

      ability :corruption, cooldown: 20000, target: :random do
        environmental :void_zone, radius: 5, duration: 30000,
                     damage_per_tick: 2000, tick_interval: 1000
      end

      phase :three, health_below: 30 do
        environmental :falling_debris,
                     frequency: 2000, damage: 10000, radius: 4
      end
  """

  @type hazard_type :: :void_zone | :fire | :poison_cloud | :falling_debris
                     | :terrain_change | :environmental_damage | :lava
                     | :ice | :lightning_field | :wind

  @doc """
  Creates an environmental hazard.

  ## Options vary by hazard type:

  ### Void Zone / Fire / Poison
    - `:radius` - Size of the hazard
    - `:duration` - How long it persists (nil for permanent)
    - `:damage_per_tick` - Damage each tick
    - `:tick_interval` - Time between damage ticks
    - `:grows` - Whether the zone expands over time
    - `:growth_rate` - How fast it grows per second

  ### Falling Debris
    - `:frequency` - How often debris falls
    - `:damage` - Damage per hit
    - `:radius` - Impact radius
    - `:telegraph_duration` - Warning time before impact

  ### Terrain Change
    - `:effect` - Type of change (:raise, :lower, :break, :block)
    - `:area` - Affected area
    - `:duration` - How long the change lasts
  """
  defmacro environmental(type, opts \\ []) do
    quote do
      env_data = build_environmental(unquote(type), unquote(opts))

      effect = %{
        type: :environmental,
        hazard_type: unquote(type),
        params: env_data
      }

      ability = Module.get_attribute(__MODULE__, :current_ability)
      updated = Map.update!(ability, :effects, &[effect | &1])
      Module.put_attribute(__MODULE__, :current_ability, updated)
    end
  end

  @doc """
  Builds environmental hazard parameters.
  """
  def build_environmental(:void_zone, opts) do
    %{
      radius: Keyword.fetch!(opts, :radius),
      duration: Keyword.get(opts, :duration),
      damage_per_tick: Keyword.get(opts, :damage_per_tick, 1000),
      tick_interval: Keyword.get(opts, :tick_interval, 1000),
      grows: Keyword.get(opts, :grows, false),
      growth_rate: Keyword.get(opts, :growth_rate, 0.5),
      max_radius: Keyword.get(opts, :max_radius, 20),
      visual: Keyword.get(opts, :visual, :shadow),
      stacking: Keyword.get(opts, :stacking, false)
    }
  end

  def build_environmental(:fire, opts) do
    %{
      radius: Keyword.fetch!(opts, :radius),
      duration: Keyword.get(opts, :duration),
      damage_per_tick: Keyword.get(opts, :damage_per_tick, 1500),
      tick_interval: Keyword.get(opts, :tick_interval, 500),
      spreads: Keyword.get(opts, :spreads, false),
      spread_rate: Keyword.get(opts, :spread_rate, 1.0),
      can_extinguish: Keyword.get(opts, :can_extinguish, false)
    }
  end

  def build_environmental(:poison_cloud, opts) do
    %{
      radius: Keyword.fetch!(opts, :radius),
      duration: Keyword.get(opts, :duration, 15000),
      damage_per_tick: Keyword.get(opts, :damage_per_tick, 800),
      tick_interval: Keyword.get(opts, :tick_interval, 1000),
      stacking_debuff: Keyword.get(opts, :stacking_debuff, nil),
      reduces_healing: Keyword.get(opts, :reduces_healing, 0),
      visual: Keyword.get(opts, :visual, :green_cloud)
    }
  end

  def build_environmental(:falling_debris, opts) do
    %{
      frequency: Keyword.get(opts, :frequency, 3000),
      damage: Keyword.fetch!(opts, :damage),
      radius: Keyword.get(opts, :radius, 4),
      telegraph_duration: Keyword.get(opts, :telegraph_duration, 2000),
      count: Keyword.get(opts, :count, 1),
      pattern: Keyword.get(opts, :pattern, :random),
      safe_zones: Keyword.get(opts, :safe_zones, [])
    }
  end

  def build_environmental(:terrain_change, opts) do
    %{
      effect: Keyword.fetch!(opts, :effect),
      area: Keyword.get(opts, :area, :platform),
      duration: Keyword.get(opts, :duration),
      blocks_los: Keyword.get(opts, :blocks_los, false),
      blocks_movement: Keyword.get(opts, :blocks_movement, false),
      damage_on_touch: Keyword.get(opts, :damage_on_touch, 0)
    }
  end

  def build_environmental(:environmental_damage, opts) do
    %{
      damage_per_tick: Keyword.fetch!(opts, :damage_per_tick),
      tick_interval: Keyword.get(opts, :tick_interval, 2000),
      avoidable: Keyword.get(opts, :avoidable, true),
      safe_zone: Keyword.get(opts, :safe_zone, nil),
      damage_type: Keyword.get(opts, :damage_type, :nature)
    }
  end

  def build_environmental(:lava, opts) do
    %{
      areas: Keyword.fetch!(opts, :areas),
      damage_per_tick: Keyword.get(opts, :damage_per_tick, 5000),
      tick_interval: Keyword.get(opts, :tick_interval, 500),
      instant_death: Keyword.get(opts, :instant_death, false)
    }
  end

  def build_environmental(:lightning_field, opts) do
    %{
      radius: Keyword.fetch!(opts, :radius),
      damage_per_tick: Keyword.get(opts, :damage_per_tick, 2000),
      tick_interval: Keyword.get(opts, :tick_interval, 500),
      chain_damage: Keyword.get(opts, :chain_damage, 0),
      chain_range: Keyword.get(opts, :chain_range, 5)
    }
  end

  @doc """
  Creates a hazard that spawns at player locations (drop on feet).
  """
  defmacro drop_hazard(type, opts \\ []) do
    quote do
      env_data = build_environmental(unquote(type), unquote(opts))

      effect = %{
        type: :drop_hazard,
        hazard_type: unquote(type),
        params: env_data,
        target: Keyword.get(unquote(opts), :target, :all),
        delay: Keyword.get(unquote(opts), :delay, 0)
      }

      ability = Module.get_attribute(__MODULE__, :current_ability)
      updated = Map.update!(ability, :effects, &[effect | &1])
      Module.put_attribute(__MODULE__, :current_ability, updated)
    end
  end

  @doc """
  Removes/clears environmental hazards.
  """
  defmacro clear_hazards(opts \\ []) do
    quote do
      effect = %{
        type: :clear_hazards,
        hazard_type: Keyword.get(unquote(opts), :type, :all),
        area: Keyword.get(unquote(opts), :area, :all)
      }

      ability = Module.get_attribute(__MODULE__, :current_ability)
      updated = Map.update!(ability, :effects, &[effect | &1])
      Module.put_attribute(__MODULE__, :current_ability, updated)
    end
  end

  @doc """
  Creates safe zones during room-wide damage.
  """
  defmacro safe_zone(opts \\ []) do
    quote do
      effect = %{
        type: :safe_zone,
        shape: Keyword.get(unquote(opts), :shape, :circle),
        radius: Keyword.get(unquote(opts), :radius, 5),
        position: Keyword.get(unquote(opts), :position, :center),
        duration: Keyword.get(unquote(opts), :duration, 5000),
        visual: Keyword.get(unquote(opts), :visual, :green_glow)
      }

      ability = Module.get_attribute(__MODULE__, :current_ability)
      updated = Map.update!(ability, :effects, &[effect | &1])
      Module.put_attribute(__MODULE__, :current_ability, updated)
    end
  end

  @doc """
  Creates a platform/arena phase mechanic.
  """
  defmacro platform_phase(opts \\ []) do
    quote do
      effect = %{
        type: :platform_phase,
        platforms: Keyword.fetch!(unquote(opts), :platforms),
        collapse_order: Keyword.get(unquote(opts), :collapse_order, []),
        collapse_interval: Keyword.get(unquote(opts), :collapse_interval, 30000),
        respawn: Keyword.get(unquote(opts), :respawn, false)
      }

      ability = Module.get_attribute(__MODULE__, :current_ability)
      updated = Map.update!(ability, :effects, &[effect | &1])
      Module.put_attribute(__MODULE__, :current_ability, updated)
    end
  end
end
