defmodule BezgelorWorld.World.Instance.Entities do
  @moduledoc """
  Entity management helpers for world instances.

  This module contains pure functions for:
  - Entity lookup with result wrapping
  - Creature ID extraction from entities
  - Position change detection
  - Entity range filtering

  ## Relationship with Instance

  The Instance GenServer manages entity state (entities map, SpatialGrid, type-
  specific sets). This module provides helper functions that can be called from
  handlers to maintain consistent patterns across entity operations.

  ## Entity Types

  Entities are tracked by type:
  - `:player` - Player characters, tracked in `players` MapSet
  - `:creature` - NPCs and mobs, tracked in `creatures` MapSet
  - Other types - Only tracked in entities map
  """

  require Logger

  @type entity :: map()
  @type position :: {float(), float(), float()}
  @type guid :: non_neg_integer()

  @doc """
  Look up an entity by GUID from the entities map.

  ## Parameters

  - `entities` - Map of GUIDs to entities
  - `guid` - The entity GUID to find

  ## Returns

  `{:ok, entity}` if found, `:error` if not found.
  """
  @spec lookup(map(), guid()) :: {:ok, entity()} | :error
  def lookup(entities, guid) do
    case Map.get(entities, guid) do
      nil -> :error
      entity -> {:ok, entity}
    end
  end

  @doc """
  Get the creature_id from an entity if it's a creature.

  ## Parameters

  - `entities` - Map of GUIDs to entities
  - `guid` - The entity GUID to check

  ## Returns

  `{:ok, creature_id}` if entity is a creature with a creature_id,
  `:error` otherwise.
  """
  @spec get_creature_id(map(), guid()) :: {:ok, non_neg_integer()} | :error
  def get_creature_id(entities, guid) do
    case Map.get(entities, guid) do
      nil ->
        :error

      %{type: :creature, creature_id: creature_id} when not is_nil(creature_id) ->
        {:ok, creature_id}

      _ ->
        :error
    end
  end

  @doc """
  Check if an entity's position has changed.

  ## Parameters

  - `old_entity` - The entity before update (may be nil)
  - `new_entity` - The entity after update

  ## Returns

  `true` if position changed, `false` otherwise.
  """
  @spec position_changed?(entity() | nil, entity()) :: boolean()
  def position_changed?(nil, _new_entity), do: false

  def position_changed?(old_entity, new_entity) do
    old_entity.position != new_entity.position
  end

  @doc """
  Filter entities from a list of GUIDs, removing any that don't exist.

  ## Parameters

  - `entities` - Map of GUIDs to entities
  - `guids` - List of GUIDs to look up

  ## Returns

  List of entities (nil values filtered out).
  """
  @spec filter_existing(map(), [guid()]) :: [entity()]
  def filter_existing(entities, guids) do
    guids
    |> Enum.map(&Map.get(entities, &1))
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Get all entities of a specific type from a set of GUIDs.

  ## Parameters

  - `entities` - Map of GUIDs to entities
  - `guid_set` - MapSet of GUIDs to look up

  ## Returns

  List of entities (nil values filtered out).
  """
  @spec from_set(map(), MapSet.t()) :: [entity()]
  def from_set(entities, guid_set) do
    guid_set
    |> MapSet.to_list()
    |> Enum.map(&Map.get(entities, &1))
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Apply batch entity updates to the entities map, tracking position changes.

  ## Parameters

  - `entities` - Current entities map
  - `updates` - List of {guid, entity} tuples to apply

  ## Returns

  `{updated_entities, changed_positions}` where `changed_positions` is a list
  of `{guid, new_position}` tuples for entities whose position changed.
  """
  @spec apply_batch_updates(map(), [{guid(), entity()}]) ::
          {map(), [{guid(), position()}]}
  def apply_batch_updates(entities, updates) do
    Enum.reduce(updates, {entities, []}, fn {guid, new_entity}, {ents, changes} ->
      old_entity = Map.get(ents, guid)
      new_ents = Map.put(ents, guid, new_entity)

      new_changes =
        if position_changed?(old_entity, new_entity) do
          [{guid, new_entity.position} | changes]
        else
          changes
        end

      {new_ents, new_changes}
    end)
  end

  @doc """
  Build updated entities map with a single entity update.

  ## Parameters

  - `entities` - Current entities map
  - `guid` - GUID of entity to update
  - `update_fn` - Function to apply to entity

  ## Returns

  `{:ok, updated_entity, updated_entities, position_changed}` if found,
  `:error` if entity not found.
  """
  @spec apply_update(map(), guid(), (entity() -> entity())) ::
          {:ok, entity(), map(), boolean()} | :error
  def apply_update(entities, guid, update_fn) do
    case Map.get(entities, guid) do
      nil ->
        :error

      entity ->
        updated_entity = update_fn.(entity)
        updated_entities = Map.put(entities, guid, updated_entity)
        changed = position_changed?(entity, updated_entity)
        {:ok, updated_entity, updated_entities, changed}
    end
  end

  @doc """
  Log entity addition.

  ## Parameters

  - `entity` - The entity that was added
  - `world_id` - World ID for context
  """
  @spec log_added(entity(), non_neg_integer()) :: :ok
  def log_added(entity, world_id) do
    Logger.debug("Entity #{entity.guid} (#{entity.type}) added to world #{world_id}")
  end

  @doc """
  Log entity removal.

  ## Parameters

  - `guid` - GUID of removed entity
  - `world_id` - World ID for context
  """
  @spec log_removed(guid(), non_neg_integer()) :: :ok
  def log_removed(guid, world_id) do
    Logger.debug("Entity #{guid} removed from world #{world_id}")
  end
end
