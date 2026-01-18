defmodule BezgelorWorld.World.Instance.Creatures do
  @moduledoc """
  Creature management helpers for world instances.

  This module contains pure functions for:
  - Social aggro coordination across creatures
  - Creature respawn state building
  - Killer level lookup for XP calculations
  - Range-based creature filtering

  ## Relationship with CreatureState

  The CreatureState module handles individual creature state (building from spawn
  definitions, damage application, death handling). This module handles coordination
  across multiple creatures within an instance (social aggro, range queries).

  ## Social Aggro

  When a creature is attacked, nearby creatures of the same faction may join combat.
  The `find_social_aggro_targets/4` function identifies eligible creatures.
  """

  alias BezgelorCore.{AI, CreatureTemplate}
  alias BezgelorWorld.CreatureDeath

  require Logger

  @type creature_state :: map()
  @type position :: {float(), float(), float()}

  @doc """
  Find creatures eligible for social aggro when a creature is attacked.

  ## Parameters

  - `aggressor_state` - The creature that was attacked
  - `target_guid` - The GUID of the attacker (player/creature)
  - `creature_states` - Map of all creature states in the instance

  ## Returns

  List of `{guid, creature_state}` tuples for creatures that should aggro.
  """
  @spec find_social_aggro_targets(creature_state(), non_neg_integer(), map()) ::
          [{non_neg_integer(), creature_state()}]
  def find_social_aggro_targets(aggressor_state, _target_guid, creature_states) do
    aggressor_faction = aggressor_state.template.faction
    aggressor_pos = aggressor_state.entity.position
    social_range = CreatureTemplate.social_aggro_range(aggressor_state.template)

    creature_states
    |> Enum.filter(fn {guid, cs} ->
      guid != aggressor_state.entity.guid and
        cs.template.faction == aggressor_faction and
        cs.ai.state == :idle and
        AI.distance(aggressor_pos, cs.entity.position) <= social_range
    end)
  end

  @doc """
  Apply social aggro to a creature, making it attack the target.

  ## Parameters

  - `creature_state` - The creature to trigger aggro on
  - `target_guid` - The GUID of the target to attack

  ## Returns

  Updated creature_state with AI set to attack target.
  """
  @spec apply_social_aggro(creature_state(), non_neg_integer()) :: creature_state()
  def apply_social_aggro(creature_state, target_guid) do
    new_ai = AI.social_aggro(creature_state.ai, target_guid)
    %{creature_state | ai: new_ai}
  end

  @doc """
  Build respawned creature state from dead creature.

  Resets health to max, returns to spawn position, and resets AI.

  ## Parameters

  - `creature_state` - The dead creature to respawn

  ## Returns

  Updated creature_state ready for respawn.
  """
  @spec build_respawn_state(creature_state()) :: creature_state()
  def build_respawn_state(creature_state) do
    new_entity = %{
      creature_state.entity
      | health: creature_state.template.max_health,
        position: creature_state.spawn_position
    }

    new_ai = AI.respawn(creature_state.ai)

    %{
      creature_state
      | entity: new_entity,
        ai: new_ai,
        respawn_timer: nil
    }
  end

  @doc """
  Get the level of a killer entity for XP calculations.

  For player killers, looks up their level from entities.
  For non-player killers, returns the default level.

  ## Parameters

  - `killer_guid` - GUID of the killer
  - `default_level` - Level to use if killer not found or not a player
  - `entities` - Map of entity GUIDs to entities

  ## Returns

  The killer's level as an integer.
  """
  @spec get_killer_level(non_neg_integer(), non_neg_integer(), map()) :: non_neg_integer()
  def get_killer_level(killer_guid, default_level, entities) do
    if CreatureDeath.is_player_guid?(killer_guid) do
      case Map.get(entities, killer_guid) do
        nil -> default_level
        player_entity -> player_entity.level
      end
    else
      default_level
    end
  end

  @doc """
  Filter creatures in range of a position.

  ## Parameters

  - `creature_states` - Map of creature GUIDs to creature states
  - `position` - Center position for range check
  - `range` - Maximum distance

  ## Returns

  List of creature states within range.
  """
  @spec in_range(map(), position(), float()) :: [creature_state()]
  def in_range(creature_states, position, range) do
    creature_states
    |> Map.values()
    |> Enum.filter(fn cs ->
      AI.distance(cs.entity.position, position) <= range
    end)
  end

  @doc """
  Filter alive creatures in range of a position.

  Only returns creatures that are alive (not dead) and within range.

  ## Parameters

  - `creature_states` - Map of creature GUIDs to creature states
  - `position` - Center position for range check
  - `range` - Maximum distance

  ## Returns

  List of alive creature states within range.
  """
  @spec alive_in_range(map(), position(), float()) :: [creature_state()]
  def alive_in_range(creature_states, position, range) do
    creature_states
    |> Map.values()
    |> Enum.filter(fn %{entity: entity, ai: ai} ->
      not AI.dead?(ai) and AI.distance(entity.position, position) <= range
    end)
  end

  @doc """
  Log creature respawn event.

  ## Parameters

  - `name` - Creature name
  - `guid` - Creature GUID
  """
  @spec log_respawn(String.t(), non_neg_integer()) :: :ok
  def log_respawn(name, guid) do
    Logger.debug("Respawned creature #{name} (#{guid})")
  end
end
