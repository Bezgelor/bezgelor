defmodule BezgelorCore.AI do
  @moduledoc """
  AI state machine for creature behavior.

  ## States

  - `:idle` - Standing at spawn, not in combat
  - `:patrol` - Following patrol path (future)
  - `:combat` - Engaged with target
  - `:evade` - Returning to spawn (leashed)
  - `:dead` - Waiting for respawn

  ## Transitions

  - idle + player_in_range -> combat (if aggressive)
  - combat + target_dead -> idle
  - combat + target_out_of_leash -> evade
  - evade + at_spawn -> idle
  - any + health=0 -> dead
  - dead + respawn_timer -> idle
  """

  @type state :: :idle | :patrol | :combat | :evade | :dead

  @type t :: %__MODULE__{
          state: state(),
          target_guid: non_neg_integer() | nil,
          spawn_position: {float(), float(), float()},
          last_attack_time: integer() | nil,
          combat_start_time: integer() | nil,
          threat_table: %{non_neg_integer() => non_neg_integer()},
          combat_participants: MapSet.t(non_neg_integer())
        }

  defstruct state: :idle,
            target_guid: nil,
            spawn_position: {0.0, 0.0, 0.0},
            last_attack_time: nil,
            combat_start_time: nil,
            threat_table: %{},
            combat_participants: MapSet.new()

  @doc """
  Create new AI state for a creature.
  """
  @spec new(position :: {float(), float(), float()}) :: t()
  def new(spawn_position) do
    %__MODULE__{
      spawn_position: spawn_position
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

  @doc """
  Process AI tick - returns action to take.

  Actions:
  - {:attack, target_guid} - Attack the target
  - {:move_to, position} - Move towards position
  - :none - No action needed
  """
  @spec tick(t(), map()) ::
          {:attack, non_neg_integer()} | {:move_to, {float(), float(), float()}} | :none
  def tick(%__MODULE__{state: :dead}, _context), do: :none

  def tick(%__MODULE__{state: :idle}, _context), do: :none

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
end
