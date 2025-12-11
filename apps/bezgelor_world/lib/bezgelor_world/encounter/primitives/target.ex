defmodule BezgelorWorld.Encounter.Primitives.Target do
  @moduledoc """
  Target selection primitives for boss abilities.

  Defines how boss abilities select their targets. This is critical
  for encounter design as different targeting creates different
  strategic requirements.

  ## Target Types

  ### Single Target
  - `:tank` - Current highest threat target
  - `:healer` - Random healer in the group
  - `:random` - Random player
  - `:farthest` - Player furthest from boss
  - `:nearest` - Player closest to boss (excluding tank)
  - `:lowest_health` - Player with lowest HP percentage
  - `:highest_threat` - Explicit threat target
  - `:second_threat` - Second highest threat (off-tank mechanic)
  - `:marked` - Player with a specific debuff/mark

  ### Multi-Target
  - `:all` - All players
  - `:all_except_tank` - Everyone but current tank
  - `:random_n` - N random players
  - `:spread` - Targets that must spread apart
  - `:chain` - Chain lightning style (jumps between targets)

  ## Example Usage

      ability :tail_swipe, cooldown: 12000, target: :farthest do
        telegraph :cone, angle: 180, length: 20
        damage 6000, type: :physical
      end

      ability :chain_lightning, cooldown: 20000 do
        target :chain, initial: :random, jumps: 4, range: 10
        damage 3000, type: :magic
      end
  """

  @type target_type :: :tank | :healer | :random | :farthest | :nearest
                     | :lowest_health | :highest_threat | :second_threat
                     | :marked | :all | :all_except_tank | :random_n
                     | :spread | :chain | :self

  @doc """
  Defines explicit targeting for the current ability.

  ## Options vary by target type:

  ### :chain
    - `:initial` - How to select first target
    - `:jumps` - Number of chain jumps
    - `:range` - Maximum jump distance
    - `:damage_falloff` - Damage reduction per jump (0.0-1.0)

  ### :random_n
    - `:count` - Number of random targets
    - `:exclude_tank` - Whether to exclude tank

  ### :spread
    - `:count` - Number of targets
    - `:required_distance` - How far apart they must be

  ### :marked
    - `:debuff` - Debuff name that marks the target
  """
  defmacro target(type, opts \\ []) do
    quote do
      target_data = build_target(unquote(type), unquote(opts))

      effect = %{type: :targeting, target_type: unquote(type), params: target_data}

      ability = Module.get_attribute(__MODULE__, :current_ability)
      updated = Map.update!(ability, :effects, &[effect | &1])
      # Also update the ability's default target
      updated = Map.put(updated, :target, unquote(type))
      Module.put_attribute(__MODULE__, :current_ability, updated)
    end
  end

  @doc """
  Builds target parameters based on type.
  """
  def build_target(:chain, opts) do
    %{
      initial: Keyword.get(opts, :initial, :random),
      jumps: Keyword.get(opts, :jumps, 3),
      range: Keyword.get(opts, :range, 10),
      damage_falloff: Keyword.get(opts, :damage_falloff, 0.1)
    }
  end

  def build_target(:random_n, opts) do
    %{
      count: Keyword.fetch!(opts, :count),
      exclude_tank: Keyword.get(opts, :exclude_tank, false),
      exclude_roles: Keyword.get(opts, :exclude_roles, [])
    }
  end

  def build_target(:spread, opts) do
    %{
      count: Keyword.fetch!(opts, :count),
      required_distance: Keyword.get(opts, :required_distance, 8),
      failure_damage: Keyword.get(opts, :failure_damage, 0)
    }
  end

  def build_target(:marked, opts) do
    %{
      debuff: Keyword.fetch!(opts, :debuff)
    }
  end

  def build_target(:fixate, opts) do
    %{
      duration: Keyword.get(opts, :duration, 10000),
      initial_target: Keyword.get(opts, :initial, :random)
    }
  end

  def build_target(simple_type, _opts)
      when simple_type in [:tank, :healer, :random, :farthest, :nearest,
                           :lowest_health, :highest_threat, :second_threat,
                           :all, :all_except_tank, :self] do
    %{type: simple_type}
  end

  @doc """
  Marks targets with a debuff for later targeting.
  Used for mechanics like "marked players get hit by meteor".
  """
  defmacro mark_target(mark_name, opts \\ []) do
    quote do
      effect = %{
        type: :mark,
        name: unquote(mark_name),
        duration: Keyword.get(unquote(opts), :duration, 10000),
        visual: Keyword.get(unquote(opts), :visual, :skull),
        count: Keyword.get(unquote(opts), :count, 1),
        selection: Keyword.get(unquote(opts), :selection, :random)
      }

      ability = Module.get_attribute(__MODULE__, :current_ability)
      updated = Map.update!(ability, :effects, &[effect | &1])
      Module.put_attribute(__MODULE__, :current_ability, updated)
    end
  end

  @doc """
  Creates a fixate mechanic where the boss focuses on one target
  regardless of threat.
  """
  defmacro fixate(opts \\ []) do
    quote do
      effect = %{
        type: :fixate,
        duration: Keyword.get(unquote(opts), :duration, 10000),
        initial_target: Keyword.get(unquote(opts), :initial, :random),
        speed_modifier: Keyword.get(unquote(opts), :speed_modifier, 1.0),
        ignores_threat: true
      }

      ability = Module.get_attribute(__MODULE__, :current_ability)
      updated = Map.update!(ability, :effects, &[effect | &1])
      Module.put_attribute(__MODULE__, :current_ability, updated)
    end
  end

  @doc """
  Tank swap mechanic - forces tank swap via debuff.
  """
  defmacro tank_swap(debuff_name, opts \\ []) do
    quote do
      effect = %{
        type: :tank_swap,
        debuff: unquote(debuff_name),
        stacks_for_swap: Keyword.get(unquote(opts), :stacks, 3),
        duration: Keyword.get(unquote(opts), :duration, 30000),
        swap_damage: Keyword.get(unquote(opts), :swap_damage, 0)
      }

      ability = Module.get_attribute(__MODULE__, :current_ability)
      updated = Map.update!(ability, :effects, &[effect | &1])
      Module.put_attribute(__MODULE__, :current_ability, updated)
    end
  end

  @doc """
  Shared damage mechanic - damage split among players in area.
  """
  defmacro shared_damage(opts \\ []) do
    quote do
      effect = %{
        type: :shared_damage,
        min_players: Keyword.get(unquote(opts), :min_players, 2),
        base_damage: Keyword.fetch!(unquote(opts), :damage),
        telegraph_shape: Keyword.get(unquote(opts), :shape, :circle),
        telegraph_radius: Keyword.get(unquote(opts), :radius, 5)
      }

      ability = Module.get_attribute(__MODULE__, :current_ability)
      updated = Map.update!(ability, :effects, &[effect | &1])
      Module.put_attribute(__MODULE__, :current_ability, updated)
    end
  end
end
