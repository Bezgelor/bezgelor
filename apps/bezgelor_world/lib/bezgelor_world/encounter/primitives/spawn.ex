defmodule BezgelorWorld.Encounter.Primitives.Spawn do
  @moduledoc """
  Add spawning primitives for boss encounters.

  Many boss encounters involve spawning additional creatures (adds)
  that must be handled by the group. This module provides various
  spawn patterns and behaviors.

  ## Spawn Types

  - `:add` - Single add or group of identical adds
  - `:wave` - Sequential waves of adds
  - `:portal` - Adds spawn from portals that must be destroyed
  - `:split` - Boss splits into multiple smaller versions
  - `:summon` - Channeled summon that can be interrupted

  ## Example Usage

      ability :call_reinforcements, cooldown: 60000 do
        spawn :add, creature_id: 2001, count: 4, spread: true
      end

      ability :open_portal, cooldown: 45000 do
        spawn :portal, creature_id: 2002, portal_hp: 50000,
              spawn_rate: 5000, spawn_creature: 2003
      end
  """

  @doc """
  Spawns creatures as part of an ability.

  ## Options

  ### Common
    - `:creature_id` - ID of creature to spawn (required)
    - `:count` - Number to spawn (default: 1)
    - `:delay` - Delay before spawn in ms (default: 0)

  ### Positioning
    - `:position` - Specific position {x, y, z}
    - `:spread` - Spawn spread around boss (boolean or radius)
    - `:positions` - List of specific positions for each add
    - `:formation` - Spawn in formation (:circle, :line, :random)

  ### Behavior
    - `:aggro` - Initial aggro behavior (:random, :healer, :tank, :fixate)
    - `:despawn_on_boss_death` - Whether adds despawn when boss dies
    - `:must_kill` - Whether adds must die for phase to progress
  """
  defmacro spawn(type, opts \\ []) do
    quote do
      spawn_data = build_spawn(unquote(type), unquote(opts))

      effect = %{
        type: :spawn,
        spawn_type: unquote(type),
        params: spawn_data
      }

      ability = Module.get_attribute(__MODULE__, :current_ability)
      updated = Map.update!(ability, :effects, &[effect | &1])
      Module.put_attribute(__MODULE__, :current_ability, updated)
    end
  end

  @doc """
  Builds spawn parameters based on type.
  """
  def build_spawn(:add, opts) do
    %{
      creature_id: Keyword.fetch!(opts, :creature_id),
      count: Keyword.get(opts, :count, 1),
      delay: Keyword.get(opts, :delay, 0),
      spread: Keyword.get(opts, :spread, false),
      spread_radius: Keyword.get(opts, :spread_radius, 10),
      formation: Keyword.get(opts, :formation, :random),
      positions: Keyword.get(opts, :positions, []),
      aggro: Keyword.get(opts, :aggro, :random),
      despawn_on_boss_death: Keyword.get(opts, :despawn_on_boss_death, true),
      must_kill: Keyword.get(opts, :must_kill, false),
      health_scale: Keyword.get(opts, :health_scale, 1.0)
    }
  end

  def build_spawn(:wave, opts) do
    %{
      creature_id: Keyword.fetch!(opts, :creature_id),
      waves: Keyword.get(opts, :waves, 3),
      per_wave: Keyword.get(opts, :per_wave, 2),
      wave_interval: Keyword.get(opts, :wave_interval, 10000),
      aggro: Keyword.get(opts, :aggro, :random),
      despawn_on_boss_death: Keyword.get(opts, :despawn_on_boss_death, true)
    }
  end

  def build_spawn(:portal, opts) do
    %{
      portal_creature_id: Keyword.fetch!(opts, :creature_id),
      portal_hp: Keyword.get(opts, :portal_hp, 50000),
      spawn_creature_id: Keyword.fetch!(opts, :spawn_creature),
      spawn_rate: Keyword.get(opts, :spawn_rate, 5000),
      max_spawns: Keyword.get(opts, :max_spawns, 10),
      despawn_adds_on_close: Keyword.get(opts, :despawn_adds_on_close, false)
    }
  end

  def build_spawn(:split, opts) do
    %{
      creature_id: Keyword.fetch!(opts, :creature_id),
      count: Keyword.get(opts, :count, 2),
      health_share: Keyword.get(opts, :health_share, 0.5),
      rejoin_at_health: Keyword.get(opts, :rejoin_at_health, nil),
      must_kill_together: Keyword.get(opts, :must_kill_together, false),
      together_window: Keyword.get(opts, :together_window, 10000)
    }
  end

  def build_spawn(:summon, opts) do
    %{
      creature_id: Keyword.fetch!(opts, :creature_id),
      cast_time: Keyword.get(opts, :cast_time, 5000),
      interruptible: Keyword.get(opts, :interruptible, true),
      on_complete: Keyword.get(opts, :on_complete, nil),
      channel_damage: Keyword.get(opts, :channel_damage, 0)
    }
  end

  @doc """
  Despawns all adds of a specific type.
  """
  defmacro despawn(opts \\ []) do
    quote do
      effect = %{
        type: :despawn,
        creature_id: Keyword.get(unquote(opts), :creature_id, :all),
        delay: Keyword.get(unquote(opts), :delay, 0)
      }

      ability = Module.get_attribute(__MODULE__, :current_ability)
      updated = Map.update!(ability, :effects, &[effect | &1])
      Module.put_attribute(__MODULE__, :current_ability, updated)
    end
  end

  @doc """
  Defines a spawn point that can be reused.
  """
  defmacro spawn_point(name, opts) do
    quote do
      spawn_point_data = %{
        name: unquote(name),
        position: Keyword.fetch!(unquote(opts), :position),
        facing: Keyword.get(unquote(opts), :facing, 0)
      }

      phase = Module.get_attribute(__MODULE__, :current_phase)

      spawn_points = Map.get(phase, :spawn_points, [])
      updated_phase = Map.put(phase, :spawn_points, [spawn_point_data | spawn_points])
      Module.put_attribute(__MODULE__, :current_phase, updated_phase)
    end
  end

  @doc """
  Spawns at a named spawn point.
  """
  defmacro spawn_at(point_name, opts \\ []) do
    quote do
      effect = %{
        type: :spawn_at_point,
        point: unquote(point_name),
        creature_id: Keyword.fetch!(unquote(opts), :creature_id),
        count: Keyword.get(unquote(opts), :count, 1)
      }

      ability = Module.get_attribute(__MODULE__, :current_ability)
      updated = Map.update!(ability, :effects, &[effect | &1])
      Module.put_attribute(__MODULE__, :current_ability, updated)
    end
  end

  @doc """
  Creates an egg/cocoon that hatches after a duration.
  """
  defmacro spawn_egg(opts \\ []) do
    quote do
      effect = %{
        type: :spawn_egg,
        egg_creature_id: Keyword.fetch!(unquote(opts), :egg_creature_id),
        hatched_creature_id: Keyword.fetch!(unquote(opts), :hatches_into),
        hatch_time: Keyword.get(unquote(opts), :hatch_time, 10000),
        can_kill_egg: Keyword.get(unquote(opts), :killable, true),
        egg_hp: Keyword.get(unquote(opts), :egg_hp, 10000),
        count: Keyword.get(unquote(opts), :count, 1)
      }

      ability = Module.get_attribute(__MODULE__, :current_ability)
      updated = Map.update!(ability, :effects, &[effect | &1])
      Module.put_attribute(__MODULE__, :current_ability, updated)
    end
  end
end
