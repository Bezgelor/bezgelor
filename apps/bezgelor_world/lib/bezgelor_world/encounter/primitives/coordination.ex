defmodule BezgelorWorld.Encounter.Primitives.Coordination do
  @moduledoc """
  Group coordination mechanic primitives for boss encounters.

  These mechanics require players to work together, positioning
  themselves correctly or performing coordinated actions.

  ## Coordination Types

  - `:stack` - Players must group together
  - `:spread` - Players must spread apart
  - `:pair` - Players must pair up
  - `:soak` - X players must stand in area
  - `:chain` - Players must form a chain
  - `:pass` - Debuff must be passed between players
  - `:tether` - Players connected must manage distance

  ## Example Usage

      ability :shared_agony, cooldown: 45000 do
        coordination :stack, min_players: 3,
                    damage: 30000, split: true
      end

      ability :volatile_bomb, cooldown: 30000 do
        coordination :spread, required_distance: 8,
                    explosion_radius: 5, damage: 15000
      end

      ability :soul_link, cooldown: 60000 do
        coordination :tether, pairs: 2,
                    min_distance: 5, max_distance: 20,
                    too_close_damage: 5000, too_far_break: true
      end
  """

  @type coord_type :: :stack | :spread | :pair | :soak | :chain | :pass | :tether

  @doc """
  Defines a coordination mechanic for the current ability.

  ## Options vary by coordination type:

  ### Stack
    - `:min_players` - Minimum players needed
    - `:damage` - Total damage to split
    - `:split` - Whether damage is split (default: true)
    - `:failure_damage` - Damage if not enough players

  ### Spread
    - `:required_distance` - How far apart players must be
    - `:explosion_radius` - Damage radius if too close
    - `:damage` - Damage dealt
    - `:marks_count` - How many players are marked

  ### Pair
    - `:pairs` - Number of pairs to form
    - `:required_distance` - How close pairs must be
    - `:success_effect` - Effect on successful pairing
    - `:failure_damage` - Damage if pairing fails

  ### Soak
    - `:required_players` - Exact number needed
    - `:damage_per_missing` - Extra damage per missing player
    - `:base_damage` - Base damage to split
    - `:circle_radius` - Size of soak zone

  ### Chain
    - `:min_players` - Minimum in chain
    - `:max_distance` - Max distance between chain links
    - `:damage_per_break` - Damage when chain breaks

  ### Pass
    - `:duration` - How long before must pass
    - `:damage_on_expire` - Damage if not passed
    - `:stack_on_same` - Whether can pass to same player
    - `:max_passes` - Pass limit before it expires

  ### Tether
    - `:pairs` - Number of tethered pairs
    - `:min_distance` - Minimum safe distance
    - `:max_distance` - Maximum before break
    - `:too_close_damage` - Damage when too close
    - `:too_far_break` - Whether tether breaks when too far
    - `:break_damage` - Damage on break
  """
  defmacro coordination(type, opts \\ []) do
    quote do
      coord_data = build_coordination(unquote(type), unquote(opts))

      effect = %{
        type: :coordination,
        coord_type: unquote(type),
        params: coord_data
      }

      ability = Module.get_attribute(__MODULE__, :current_ability)
      updated = Map.update!(ability, :effects, &[effect | &1])
      Module.put_attribute(__MODULE__, :current_ability, updated)
    end
  end

  @doc """
  Builds coordination parameters based on type.
  """
  def build_coordination(:stack, opts) do
    %{
      min_players: Keyword.get(opts, :min_players, 2),
      damage: Keyword.fetch!(opts, :damage),
      split: Keyword.get(opts, :split, true),
      failure_damage: Keyword.get(opts, :failure_damage),
      stack_radius: Keyword.get(opts, :radius, 5),
      telegraph: Keyword.get(opts, :telegraph, true)
    }
  end

  def build_coordination(:spread, opts) do
    %{
      required_distance: Keyword.get(opts, :required_distance, 8),
      explosion_radius: Keyword.get(opts, :explosion_radius, 5),
      damage: Keyword.fetch!(opts, :damage),
      marks_count: Keyword.get(opts, :marks_count, :all),
      duration: Keyword.get(opts, :duration, 5000)
    }
  end

  def build_coordination(:pair, opts) do
    %{
      pairs: Keyword.get(opts, :pairs, 2),
      required_distance: Keyword.get(opts, :required_distance, 3),
      duration: Keyword.get(opts, :duration, 10000),
      success_effect: Keyword.get(opts, :success_effect, nil),
      failure_damage: Keyword.fetch!(opts, :failure_damage),
      pairing_rule: Keyword.get(opts, :pairing_rule, :debuff_match)
    }
  end

  def build_coordination(:soak, opts) do
    %{
      required_players: Keyword.get(opts, :required_players, 3),
      damage_per_missing: Keyword.get(opts, :damage_per_missing, 10000),
      base_damage: Keyword.fetch!(opts, :base_damage),
      circle_radius: Keyword.get(opts, :radius, 6),
      locations: Keyword.get(opts, :locations, [:random]),
      count: Keyword.get(opts, :count, 1)
    }
  end

  def build_coordination(:chain, opts) do
    %{
      min_players: Keyword.get(opts, :min_players, 3),
      max_distance: Keyword.get(opts, :max_distance, 10),
      damage_per_break: Keyword.fetch!(opts, :damage_per_break),
      source: Keyword.get(opts, :source, :boss),
      destination: Keyword.get(opts, :destination, :marked)
    }
  end

  def build_coordination(:pass, opts) do
    %{
      duration: Keyword.get(opts, :duration, 10000),
      damage_on_expire: Keyword.fetch!(opts, :damage_on_expire),
      stack_on_same: Keyword.get(opts, :stack_on_same, false),
      max_passes: Keyword.get(opts, :max_passes, nil),
      pass_range: Keyword.get(opts, :pass_range, 5),
      debuff_name: Keyword.get(opts, :debuff, :hot_potato)
    }
  end

  def build_coordination(:tether, opts) do
    %{
      pairs: Keyword.get(opts, :pairs, 2),
      min_distance: Keyword.get(opts, :min_distance, 5),
      max_distance: Keyword.get(opts, :max_distance, 30),
      too_close_damage: Keyword.get(opts, :too_close_damage, 0),
      too_close_tick: Keyword.get(opts, :too_close_tick, 1000),
      too_far_break: Keyword.get(opts, :too_far_break, true),
      break_damage: Keyword.get(opts, :break_damage, 0),
      visual: Keyword.get(opts, :visual, :lightning)
    }
  end

  @doc """
  Shorthand for stack points mechanic.
  """
  defmacro stack_point(opts \\ []) do
    quote do
      coordination(:stack, [
        damage: Keyword.fetch!(unquote(opts), :damage),
        min_players: Keyword.get(unquote(opts), :min_players, 5),
        telegraph: true
      ] ++ unquote(opts))
    end
  end

  @doc """
  Shorthand for spread mechanic.
  """
  defmacro spread_out(opts \\ []) do
    quote do
      coordination(:spread, [
        damage: Keyword.fetch!(unquote(opts), :damage),
        required_distance: Keyword.get(unquote(opts), :distance, 8)
      ] ++ unquote(opts))
    end
  end

  @doc """
  Creates a "bait" mechanic where players must position to control ability targeting.
  """
  defmacro bait_mechanic(opts \\ []) do
    quote do
      effect = %{
        type: :bait,
        target: Keyword.get(unquote(opts), :target, :farthest),
        telegraph_shape: Keyword.get(unquote(opts), :shape, :circle),
        telegraph_radius: Keyword.get(unquote(opts), :radius, 8),
        damage: Keyword.get(unquote(opts), :damage, 0),
        leaves_hazard: Keyword.get(unquote(opts), :leaves_hazard, false),
        hazard_type: Keyword.get(unquote(opts), :hazard_type, :void_zone)
      }

      ability = Module.get_attribute(__MODULE__, :current_ability)
      updated = Map.update!(ability, :effects, &[effect | &1])
      Module.put_attribute(__MODULE__, :current_ability, updated)
    end
  end

  @doc """
  Color matching mechanic - players must stand in matching colored zones.
  """
  defmacro color_match(opts \\ []) do
    quote do
      effect = %{
        type: :color_match,
        colors: Keyword.get(unquote(opts), :colors, [:red, :blue]),
        zones_per_color: Keyword.get(unquote(opts), :zones_per_color, 1),
        mismatch_damage: Keyword.fetch!(unquote(opts), :mismatch_damage),
        duration: Keyword.get(unquote(opts), :duration, 10000)
      }

      ability = Module.get_attribute(__MODULE__, :current_ability)
      updated = Map.update!(ability, :effects, &[effect | &1])
      Module.put_attribute(__MODULE__, :current_ability, updated)
    end
  end

  @doc """
  Line of sight mechanic - players must break LOS with boss.
  """
  defmacro line_of_sight(opts \\ []) do
    quote do
      effect = %{
        type: :line_of_sight,
        damage: Keyword.fetch!(unquote(opts), :damage),
        los_blockers: Keyword.get(unquote(opts), :blockers, :pillars),
        warn_time: Keyword.get(unquote(opts), :warn_time, 3000),
        destroys_blockers: Keyword.get(unquote(opts), :destroys_blockers, false)
      }

      ability = Module.get_attribute(__MODULE__, :current_ability)
      updated = Map.update!(ability, :effects, &[effect | &1])
      Module.put_attribute(__MODULE__, :current_ability, updated)
    end
  end

  @doc """
  Adds priority/kill order mechanic for adds.
  """
  defmacro kill_order(targets, opts \\ []) do
    quote do
      effect = %{
        type: :kill_order,
        targets: unquote(targets),
        time_between: Keyword.get(unquote(opts), :time_between, 10000),
        failure_effect: Keyword.get(unquote(opts), :failure_effect, :wipe),
        visual_indicator: Keyword.get(unquote(opts), :indicator, :number)
      }

      ability = Module.get_attribute(__MODULE__, :current_ability)
      updated = Map.update!(ability, :effects, &[effect | &1])
      Module.put_attribute(__MODULE__, :current_ability, updated)
    end
  end
end
