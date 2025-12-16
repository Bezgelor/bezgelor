defmodule BezgelorCore.AI do
  @moduledoc """
  AI state machine for creature behavior.

  ## States

  - `:idle` - Standing at spawn, not in combat
  - `:wandering` - Random wandering within leash radius
  - `:patrol` - Following patrol path (future)
  - `:combat` - Engaged with target
  - `:evade` - Returning to spawn (leashed)
  - `:dead` - Waiting for respawn

  ## Transitions

  - idle -> wandering (random chance each tick)
  - wandering + path_complete -> idle
  - idle/wandering + player_in_range -> combat (if aggressive)
  - combat + target_dead -> idle
  - combat + target_out_of_leash -> evade
  - evade + at_spawn -> idle
  - any + health=0 -> dead
  - dead + respawn_timer -> idle
  """

  @type state :: :idle | :wandering | :patrol | :combat | :evade | :dead

  @type t :: %__MODULE__{
          state: state(),
          target_guid: non_neg_integer() | nil,
          spawn_position: {float(), float(), float()},
          last_attack_time: integer() | nil,
          combat_start_time: integer() | nil,
          threat_table: %{non_neg_integer() => non_neg_integer()},
          combat_participants: MapSet.t(non_neg_integer()),
          # Wandering fields
          wander_enabled: boolean(),
          wander_range: float(),
          wander_speed: float(),
          last_wander_time: integer() | nil,
          wander_cooldown: non_neg_integer(),
          # Movement fields (shared by wander and patrol)
          movement_path: [{float(), float(), float()}],
          movement_start_time: integer() | nil,
          movement_duration: non_neg_integer(),
          # Patrol fields
          patrol_enabled: boolean(),
          patrol_waypoints: [map()],
          patrol_current_index: non_neg_integer(),
          patrol_speed: float(),
          patrol_mode:
            :cyclic
            | :cyclic_reverse
            | :one_shot
            | :one_shot_reverse
            | :back_and_forth
            | :back_and_forth_reverse,
          patrol_direction: :forward | :backward,
          patrol_pause_until: integer() | nil
        }

  defstruct state: :idle,
            target_guid: nil,
            spawn_position: {0.0, 0.0, 0.0},
            last_attack_time: nil,
            combat_start_time: nil,
            threat_table: %{},
            combat_participants: MapSet.new(),
            # Wandering defaults
            wander_enabled: true,
            wander_range: 15.0,
            wander_speed: 2.5,
            last_wander_time: nil,
            wander_cooldown: 3000,
            # Movement (shared)
            movement_path: [],
            movement_start_time: nil,
            movement_duration: 0,
            # Patrol defaults
            patrol_enabled: false,
            patrol_waypoints: [],
            patrol_current_index: 0,
            patrol_speed: 2.0,
            patrol_mode: :cyclic,
            patrol_direction: :forward,
            patrol_pause_until: nil

  @doc """
  Create new AI state for a creature.

  ## Options

  - `:wander_enabled` - Enable random wandering (default: true)
  - `:wander_range` - Maximum wander distance from spawn (default: 10.0)
  - `:wander_speed` - Movement speed while wandering (default: 2.0)
  - `:wander_cooldown` - Minimum ms between wanders (default: 5000)
  - `:patrol_waypoints` - List of waypoint maps with :position and :pause_ms keys
  - `:patrol_speed` - Movement speed while patrolling (default: 2.0)
  - `:patrol_mode` - :cyclic or :back_and_forth (default: :cyclic)
  """
  @spec new(position :: {float(), float(), float()}, opts :: keyword()) :: t()
  def new(spawn_position, opts \\ []) do
    patrol_waypoints = Keyword.get(opts, :patrol_waypoints, [])
    patrol_enabled = length(patrol_waypoints) > 1

    %__MODULE__{
      spawn_position: spawn_position,
      # Wandering - disabled if patrol is enabled
      wander_enabled: Keyword.get(opts, :wander_enabled, true) and not patrol_enabled,
      wander_range: Keyword.get(opts, :wander_range, 10.0),
      wander_speed: Keyword.get(opts, :wander_speed, 2.0),
      wander_cooldown: Keyword.get(opts, :wander_cooldown, 5000),
      # Patrol
      patrol_enabled: patrol_enabled,
      patrol_waypoints: patrol_waypoints,
      patrol_speed: Keyword.get(opts, :patrol_speed, 2.0),
      patrol_mode: Keyword.get(opts, :patrol_mode, :cyclic)
    }
  end

  @doc """
  Get current AI state.
  """
  @spec get_state(t()) :: state()
  def get_state(%__MODULE__{state: state}), do: state

  @doc """
  Check if creature is in combat.
  """
  @spec in_combat?(t()) :: boolean()
  def in_combat?(%__MODULE__{state: :combat}), do: true
  def in_combat?(_), do: false

  @doc """
  Check for players in aggro range.

  Only checks when creature is idle (not in combat, evading, or dead).
  Returns the closest player if any are within aggro range.

  ## Parameters

  - `ai` - The AI state
  - `nearby_players` - List of %{guid: integer, position: {x, y, z}} maps
  - `aggro_range` - Aggro detection radius

  ## Returns

  - `{:aggro, player_guid}` if a player is detected
  - `nil` if no players in range or AI is busy
  """
  @spec check_aggro(t(), [map()], float()) :: {:aggro, non_neg_integer()} | nil
  def check_aggro(%__MODULE__{state: state}, _nearby_players, _aggro_range)
      when state in [:combat, :evade, :dead] do
    nil
  end

  def check_aggro(%__MODULE__{spawn_position: spawn_pos}, nearby_players, aggro_range) do
    nearby_players
    |> Enum.map(fn player ->
      dist = distance(spawn_pos, player.position)
      {dist, player.guid}
    end)
    |> Enum.filter(fn {dist, _guid} -> dist <= aggro_range end)
    |> Enum.min_by(fn {dist, _guid} -> dist end, fn -> nil end)
    |> case do
      nil -> nil
      {_dist, guid} -> {:aggro, guid}
    end
  end

  @doc """
  Check for players in aggro range, filtering by faction hostility.

  Only returns players that are hostile to the creature's faction.
  """
  @spec check_aggro_with_faction(t(), [map()], float(), Faction.faction()) ::
          {:aggro, non_neg_integer()} | nil
  def check_aggro_with_faction(%__MODULE__{state: state}, _nearby_players, _aggro_range, _faction)
      when state in [:combat, :evade, :dead] do
    nil
  end

  def check_aggro_with_faction(%__MODULE__{spawn_position: spawn_pos}, nearby_players, aggro_range, creature_faction) do
    alias BezgelorCore.Faction

    nearby_players
    |> Enum.filter(fn player ->
      player_faction = Map.get(player, :faction, :exile)
      Faction.hostile?(creature_faction, player_faction)
    end)
    |> Enum.map(fn player ->
      dist = distance(spawn_pos, player.position)
      {dist, player.guid}
    end)
    |> Enum.filter(fn {dist, _guid} -> dist <= aggro_range end)
    |> Enum.min_by(fn {dist, _guid} -> dist end, fn -> nil end)
    |> case do
      nil -> nil
      {_dist, guid} -> {:aggro, guid}
    end
  end

  @doc """
  Check if creature is dead.
  """
  @spec dead?(t()) :: boolean()
  def dead?(%__MODULE__{state: :dead}), do: true
  def dead?(_), do: false

  @doc """
  Check if creature can be targeted.
  """
  @spec targetable?(t()) :: boolean()
  def targetable?(%__MODULE__{state: :dead}), do: false
  def targetable?(_), do: true

  @doc """
  Enter combat with a target.
  """
  @spec enter_combat(t(), non_neg_integer()) :: t()
  def enter_combat(%__MODULE__{state: :dead} = ai, _target_guid), do: ai

  def enter_combat(%__MODULE__{} = ai, target_guid) do
    now = System.monotonic_time(:millisecond)

    %{
      ai
      | state: :combat,
        target_guid: target_guid,
        combat_start_time: now,
        threat_table: Map.put(ai.threat_table, target_guid, 100),
        combat_participants: MapSet.put(ai.combat_participants, target_guid)
    }
  end

  @doc """
  Exit combat, return to idle.
  Clears threat and participants since combat ended without death.
  """
  @spec exit_combat(t()) :: t()
  def exit_combat(%__MODULE__{} = ai) do
    %{
      ai
      | state: :idle,
        target_guid: nil,
        combat_start_time: nil,
        threat_table: %{},
        combat_participants: MapSet.new()
    }
  end

  @doc """
  Start evading (returning to spawn).
  """
  @spec start_evade(t()) :: t()
  def start_evade(%__MODULE__{} = ai) do
    %{ai | state: :evade, target_guid: nil}
  end

  @doc """
  Complete evade, return to idle at spawn.
  Clears threat and participants since combat ended without death.
  """
  @spec complete_evade(t()) :: t()
  def complete_evade(%__MODULE__{} = ai) do
    %{
      ai
      | state: :idle,
        threat_table: %{},
        combat_participants: MapSet.new()
    }
  end

  @doc """
  Set creature as dead.
  Note: combat_participants is preserved for quest credit purposes.
  """
  @spec set_dead(t()) :: t()
  def set_dead(%__MODULE__{} = ai) do
    %{
      ai
      | state: :dead,
        target_guid: nil,
        combat_start_time: nil,
        threat_table: %{}
        # combat_participants preserved intentionally for quest credit
    }
  end

  @doc """
  Respawn creature (transition from dead to idle).
  Clears combat participants for fresh combat tracking.
  """
  @spec respawn(t()) :: t()
  def respawn(%__MODULE__{} = ai) do
    %{ai | state: :idle, combat_participants: MapSet.new()}
  end

  @doc """
  Add threat for a target. Also tracks them as a combat participant.
  """
  @spec add_threat(t(), non_neg_integer(), non_neg_integer()) :: t()
  def add_threat(%__MODULE__{} = ai, target_guid, amount) do
    new_threat = Map.get(ai.threat_table, target_guid, 0) + amount

    %{
      ai
      | threat_table: Map.put(ai.threat_table, target_guid, new_threat),
        combat_participants: MapSet.put(ai.combat_participants, target_guid)
    }
  end

  @doc """
  Get all combat participants (entity GUIDs that dealt damage).
  This is preserved even after death for quest credit purposes.
  """
  @spec get_combat_participants(t()) :: [non_neg_integer()]
  def get_combat_participants(%__MODULE__{combat_participants: participants}) do
    MapSet.to_list(participants)
  end

  @doc """
  Get the highest threat target.
  """
  @spec highest_threat_target(t()) :: non_neg_integer() | nil
  def highest_threat_target(%__MODULE__{threat_table: table}) when map_size(table) == 0, do: nil

  def highest_threat_target(%__MODULE__{threat_table: table}) do
    table
    |> Enum.max_by(fn {_, threat} -> threat end)
    |> elem(0)
  end

  @doc """
  Remove a target from threat table (e.g., when they die).
  """
  @spec remove_threat_target(t(), non_neg_integer()) :: t()
  def remove_threat_target(%__MODULE__{} = ai, target_guid) do
    new_table = Map.delete(ai.threat_table, target_guid)
    # If current target was removed, switch to highest threat
    new_target =
      if ai.target_guid == target_guid do
        highest_threat_target(%{ai | threat_table: new_table})
      else
        ai.target_guid
      end

    # If no targets left, exit combat
    if map_size(new_table) == 0 do
      exit_combat(ai)
    else
      %{ai | threat_table: new_table, target_guid: new_target}
    end
  end

  @doc """
  Check if creature can attack (attack speed cooldown).
  """
  @spec can_attack?(t(), non_neg_integer()) :: boolean()
  def can_attack?(%__MODULE__{last_attack_time: nil}, _attack_speed), do: true

  def can_attack?(%__MODULE__{last_attack_time: last}, attack_speed) do
    now = System.monotonic_time(:millisecond)
    now - last >= attack_speed
  end

  @doc """
  Record an attack.
  """
  @spec record_attack(t()) :: t()
  def record_attack(%__MODULE__{} = ai) do
    %{ai | last_attack_time: System.monotonic_time(:millisecond)}
  end

  @doc """
  Calculate distance between two positions.
  """
  @spec distance({float(), float(), float()}, {float(), float(), float()}) :: float()
  def distance({x1, y1, z1}, {x2, y2, z2}) do
    dx = x2 - x1
    dy = y2 - y1
    dz = z2 - z1
    :math.sqrt(dx * dx + dy * dy + dz * dz)
  end

  @doc """
  Check if position is within leash range of spawn.
  """
  @spec within_leash?(t(), {float(), float(), float()}, float()) :: boolean()
  def within_leash?(%__MODULE__{spawn_position: spawn}, current_position, leash_range) do
    distance(spawn, current_position) <= leash_range
  end

  @doc """
  Check if a target is within aggro range.
  """
  @spec in_aggro_range?({float(), float(), float()}, {float(), float(), float()}, float()) ::
          boolean()
  def in_aggro_range?(creature_pos, target_pos, aggro_range) do
    distance(creature_pos, target_pos) <= aggro_range
  end

  # Wandering functions

  @doc """
  Check if creature can start wandering.

  Returns true if:
  - Wandering is enabled
  - Creature is idle
  - Cooldown has elapsed since last wander
  """
  @spec can_wander?(t(), integer()) :: boolean()
  def can_wander?(%__MODULE__{wander_enabled: false}, _now), do: false
  def can_wander?(%__MODULE__{state: state}, _now) when state != :idle, do: false
  def can_wander?(%__MODULE__{last_wander_time: nil}, _now), do: true

  def can_wander?(%__MODULE__{last_wander_time: last, wander_cooldown: cooldown}, now) do
    now - last >= cooldown
  end

  @doc """
  Start wandering along a path.

  ## Parameters
    - `ai` - AI state
    - `path` - List of waypoint positions
    - `duration` - Time to complete path in milliseconds
    - `now` - Current timestamp
  """
  @spec start_wander(t(), [{float(), float(), float()}], non_neg_integer(), integer()) :: t()
  def start_wander(%__MODULE__{} = ai, path, duration, now) do
    %{
      ai
      | state: :wandering,
        movement_path: path,
        movement_start_time: now,
        movement_duration: duration,
        last_wander_time: now
    }
  end

  @doc """
  Complete wandering, return to idle.
  """
  @spec complete_wander(t()) :: t()
  def complete_wander(%__MODULE__{} = ai) do
    %{
      ai
      | state: :idle,
        movement_path: [],
        movement_start_time: nil,
        movement_duration: 0
    }
  end

  @doc """
  Check if wandering movement is complete.
  """
  @spec wander_complete?(t(), integer()) :: boolean()
  def wander_complete?(%__MODULE__{state: :wandering, movement_start_time: start, movement_duration: duration}, now) do
    now - start >= duration
  end

  def wander_complete?(_, _), do: false

  @doc """
  Get current position along movement path based on progress.
  """
  @spec get_movement_position(t(), integer()) :: {float(), float(), float()} | nil
  def get_movement_position(%__MODULE__{movement_path: []}, _now), do: nil
  def get_movement_position(%__MODULE__{movement_path: [single]}, _now), do: single

  def get_movement_position(
        %__MODULE__{movement_path: path, movement_start_time: start, movement_duration: duration},
        now
      ) do
    elapsed = now - start
    progress = min(1.0, elapsed / max(1, duration))

    # Use Movement module for interpolation
    BezgelorCore.Movement.interpolate_path(path, progress)
  end

  @doc """
  Process AI tick - returns action to take.

  Actions:
  - {:attack, target_guid} - Attack the target
  - {:move_to, position} - Move towards position
  - {:start_wander, ai} - Start wandering (returns updated AI with path)
  - {:wander_complete, ai} - Wandering finished (returns updated AI)
  - {:start_patrol, ai} - Start patrol movement (returns updated AI with path)
  - {:patrol_segment_complete, ai} - Patrol segment done, may pause or continue
  - :none - No action needed
  """
  @spec tick(t(), map()) ::
          {:attack, non_neg_integer()}
          | {:move_to, {float(), float(), float()}}
          | {:start_wander, t()}
          | {:wander_complete, t()}
          | {:start_patrol, t()}
          | {:patrol_segment_complete, t()}
          | :none
  def tick(%__MODULE__{state: :dead}, _context), do: :none

  def tick(%__MODULE__{state: :idle, patrol_enabled: true} = ai, context) do
    # Patrol takes priority over wandering
    now = System.monotonic_time(:millisecond)
    current_position = Map.get(context, :position, ai.spawn_position)
    start_next_patrol_segment(ai, current_position, now)
  end

  def tick(%__MODULE__{state: :idle} = ai, context) do
    now = System.monotonic_time(:millisecond)
    current_position = Map.get(context, :position, ai.spawn_position)

    # Check if creature should start wandering
    if can_wander?(ai, now) and should_wander?(ai, now) do
      # Generate random path
      path =
        BezgelorCore.Movement.random_path(
          current_position,
          ai.spawn_position,
          ai.wander_range
        )

      if length(path) > 1 do
        duration = BezgelorCore.Movement.path_duration(path, ai.wander_speed)
        new_ai = start_wander(ai, path, duration, now)
        {:start_wander, new_ai}
      else
        :none
      end
    else
      :none
    end
  end

  def tick(%__MODULE__{state: :wandering} = ai, _context) do
    now = System.monotonic_time(:millisecond)

    if wander_complete?(ai, now) do
      {:wander_complete, complete_wander(ai)}
    else
      :none
    end
  end

  def tick(%__MODULE__{state: :patrol} = ai, context) do
    now = System.monotonic_time(:millisecond)

    cond do
      # Still paused at waypoint
      ai.patrol_pause_until != nil and now < ai.patrol_pause_until ->
        :none

      # Pause ended, start next segment
      ai.patrol_pause_until != nil ->
        current_position = Map.get(context, :position, ai.spawn_position)
        new_ai = %{ai | patrol_pause_until: nil}
        start_next_patrol_segment(new_ai, current_position, now)

      # Movement complete, handle waypoint arrival
      patrol_segment_complete?(ai, now) ->
        handle_patrol_waypoint_arrival(ai, now)

      # No active movement and not paused - start next segment
      # This handles the case after patrol_segment_complete when no pause was set
      ai.movement_start_time == nil ->
        current_position = Map.get(context, :position, ai.spawn_position)
        start_next_patrol_segment(ai, current_position, now)

      # Still moving
      true ->
        :none
    end
  end

  def tick(%__MODULE__{state: :evade, spawn_position: spawn}, _context) do
    {:move_to, spawn}
  end

  def tick(%__MODULE__{state: :combat, target_guid: nil}, _context), do: :none

  def tick(%__MODULE__{state: :combat, target_guid: target_guid} = ai, context) do
    attack_speed = Map.get(context, :attack_speed, 2000)

    if can_attack?(ai, attack_speed) do
      {:attack, target_guid}
    else
      :none
    end
  end

  # Random chance to start wandering (50% per tick when cooldown elapsed)
  # Higher chance makes creatures more active for testing
  defp should_wander?(_ai, _now) do
    :rand.uniform() < 0.50
  end

  # Patrol helper functions

  defp patrol_segment_complete?(%__MODULE__{movement_start_time: nil}, _now), do: false

  defp patrol_segment_complete?(
         %__MODULE__{movement_start_time: start, movement_duration: duration},
         now
       ) do
    now - start >= duration
  end

  defp start_next_patrol_segment(%__MODULE__{patrol_waypoints: []} = _ai, _current_pos, _now) do
    # No waypoints, can't patrol
    :none
  end

  defp start_next_patrol_segment(%__MODULE__{} = ai, current_position, now) do
    {next_index, new_direction} = get_next_patrol_state(ai)
    waypoint = Enum.at(ai.patrol_waypoints, next_index)

    if waypoint do
      target_position = waypoint_position(waypoint)

      # Generate direct path to next waypoint
      path = BezgelorCore.Movement.direct_path(current_position, target_position)

      if length(path) > 1 do
        duration = BezgelorCore.Movement.path_duration(path, ai.patrol_speed)

        new_ai = %{
          ai
          | state: :patrol,
            movement_path: path,
            movement_start_time: now,
            movement_duration: duration,
            patrol_current_index: next_index,
            patrol_direction: new_direction
        }

        {:start_patrol, new_ai}
      else
        # Already at waypoint, handle arrival
        handle_patrol_waypoint_arrival(
          %{ai | patrol_current_index: next_index, patrol_direction: new_direction},
          now
        )
      end
    else
      :none
    end
  end

  defp handle_patrol_waypoint_arrival(%__MODULE__{} = ai, now) do
    current_waypoint = Enum.at(ai.patrol_waypoints, ai.patrol_current_index)
    pause_ms = if current_waypoint, do: Map.get(current_waypoint, :pause_ms, 0), else: 0

    new_ai =
      if pause_ms > 0 do
        # Pause at this waypoint
        %{
          ai
          | state: :patrol,
            movement_path: [],
            movement_start_time: nil,
            movement_duration: 0,
            patrol_pause_until: now + pause_ms
        }
      else
        # Continue immediately - advance index for next tick
        %{
          ai
          | movement_path: [],
            movement_start_time: nil,
            movement_duration: 0
        }
      end

    {:patrol_segment_complete, new_ai}
  end

  # Returns {next_index, new_direction}
  defp get_next_patrol_state(%__MODULE__{
         patrol_waypoints: waypoints,
         patrol_current_index: current,
         patrol_mode: mode,
         patrol_direction: direction
       }) do
    max_index = length(waypoints) - 1

    case {mode, direction} do
      # Cyclic modes - loop forever in one direction
      {:cyclic, :forward} ->
        {rem(current + 1, length(waypoints)), :forward}

      {:cyclic, :backward} ->
        index = if current <= 0, do: max_index, else: current - 1
        {index, :backward}

      {:cyclic_reverse, :forward} ->
        {rem(current + 1, length(waypoints)), :forward}

      {:cyclic_reverse, :backward} ->
        index = if current <= 0, do: max_index, else: current - 1
        {index, :backward}

      # One-shot modes - play through once then stop
      {:one_shot, :forward} when current >= max_index ->
        # Reached end, stay at end (patrol complete)
        {max_index, :forward}

      {:one_shot, :forward} ->
        {current + 1, :forward}

      {:one_shot, :backward} when current <= 0 ->
        # Reached start, stay at start
        {0, :backward}

      {:one_shot, :backward} ->
        {current - 1, :backward}

      {:one_shot_reverse, :forward} when current >= max_index ->
        {max_index, :forward}

      {:one_shot_reverse, :forward} ->
        {current + 1, :forward}

      {:one_shot_reverse, :backward} when current <= 0 ->
        {0, :backward}

      {:one_shot_reverse, :backward} ->
        {current - 1, :backward}

      # Back-and-forth modes - bounce between ends, changing direction
      {:back_and_forth, :forward} when current >= max_index ->
        # At end, reverse direction
        {max(0, current - 1), :backward}

      {:back_and_forth, :forward} ->
        {current + 1, :forward}

      {:back_and_forth, :backward} when current <= 0 ->
        # At start, go forward
        {min(max_index, current + 1), :forward}

      {:back_and_forth, :backward} ->
        {current - 1, :backward}

      {:back_and_forth_reverse, :forward} when current >= max_index ->
        {max(0, current - 1), :backward}

      {:back_and_forth_reverse, :forward} ->
        {current + 1, :forward}

      {:back_and_forth_reverse, :backward} when current <= 0 ->
        {min(max_index, current + 1), :forward}

      {:back_and_forth_reverse, :backward} ->
        {current - 1, :backward}

      # Default fallback - treat as cyclic forward
      _ ->
        {rem(current + 1, length(waypoints)), direction}
    end
  end

  defp waypoint_position(%{position: [x, y, z]}), do: {x, y, z}
  defp waypoint_position(%{position: {_, _, _} = pos}), do: pos
  defp waypoint_position(_), do: {0.0, 0.0, 0.0}

  @doc """
  Check if creature is currently patrolling.
  """
  @spec patrolling?(t()) :: boolean()
  def patrolling?(%__MODULE__{state: :patrol}), do: true
  def patrolling?(_), do: false

  @doc """
  Resume patrol after combat/evade ends.
  """
  @spec resume_patrol(t()) :: t()
  def resume_patrol(%__MODULE__{patrol_enabled: true} = ai) do
    %{ai | state: :idle, patrol_pause_until: nil}
  end

  def resume_patrol(%__MODULE__{} = ai), do: %{ai | state: :idle}
end
