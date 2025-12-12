defmodule BezgelorCore.Entity do
  @moduledoc """
  In-world entity representation.

  ## Overview

  Entities are anything that exists in the game world:
  - Players
  - Creatures (NPCs, mobs)
  - Objects (interactables, loot)
  - Vehicles

  Each entity has a unique GUID (globally unique identifier) and
  a position in the world.

  ## GUID Structure

  GUIDs are 64-bit identifiers combining:
  - Entity type (high 4 bits)
  - Server ID (next 12 bits)
  - Unique counter (low 48 bits)
  """

  @type entity_type :: :player | :creature | :object | :vehicle

  @type position :: {float(), float(), float()}
  @type rotation :: {float(), float(), float()}

  @type t :: %__MODULE__{
          guid: non_neg_integer(),
          type: entity_type(),
          name: String.t() | nil,
          display_info: non_neg_integer(),
          faction: non_neg_integer(),
          level: non_neg_integer(),
          world_id: non_neg_integer(),
          zone_id: non_neg_integer(),
          position: position(),
          rotation: rotation(),
          account_id: non_neg_integer() | nil,
          character_id: non_neg_integer() | nil,
          creature_id: non_neg_integer() | nil,
          health: non_neg_integer(),
          max_health: non_neg_integer(),
          flags: non_neg_integer(),
          target_guid: non_neg_integer() | nil,
          experience: non_neg_integer(),
          is_dead: boolean(),
          active_effects: map()
        }

  defstruct [
    :guid,
    :type,
    :name,
    display_info: 0,
    faction: 0,
    level: 1,
    world_id: 0,
    zone_id: 0,
    position: {0.0, 0.0, 0.0},
    rotation: {0.0, 0.0, 0.0},
    account_id: nil,
    character_id: nil,
    creature_id: nil,
    health: 100,
    max_health: 100,
    flags: 0,
    target_guid: nil,
    experience: 0,
    is_dead: false,
    active_effects: %{}
  ]

  # Entity type constants for GUID encoding
  @entity_type_player 1
  @entity_type_creature 2
  @entity_type_object 3
  @entity_type_vehicle 4

  @doc """
  Create a player entity from character database record.
  """
  @spec from_character(map(), non_neg_integer()) :: t()
  def from_character(character, guid) do
    %__MODULE__{
      guid: guid,
      type: :player,
      name: character.name,
      display_info: 0,
      faction: character.faction_id,
      level: character.level,
      world_id: character.world_id || 0,
      zone_id: character.world_zone_id || 0,
      position: {
        character.location_x || 0.0,
        character.location_y || 0.0,
        character.location_z || 0.0
      },
      rotation: {
        character.rotation_x || 0.0,
        character.rotation_y || 0.0,
        character.rotation_z || 0.0
      },
      account_id: character.account_id,
      character_id: character.id,
      health: 100,
      max_health: 100,
      flags: 0,
      active_effects: %{}
    }
  end

  @doc """
  Create a creature/NPC entity.
  """
  @spec create_creature(non_neg_integer(), String.t(), map()) :: t()
  def create_creature(guid, name, attrs) do
    %__MODULE__{
      guid: guid,
      type: :creature,
      name: name,
      display_info: Map.get(attrs, :display_info, 0),
      faction: Map.get(attrs, :faction, 0),
      level: Map.get(attrs, :level, 1),
      world_id: Map.get(attrs, :world_id, 0),
      zone_id: Map.get(attrs, :zone_id, 0),
      position: Map.get(attrs, :position, {0.0, 0.0, 0.0}),
      rotation: Map.get(attrs, :rotation, {0.0, 0.0, 0.0}),
      creature_id: Map.get(attrs, :creature_id),
      health: Map.get(attrs, :health, 100),
      max_health: Map.get(attrs, :max_health, 100),
      flags: Map.get(attrs, :flags, 0),
      active_effects: %{}
    }
  end

  @doc """
  Update entity position.
  """
  @spec update_position(t(), position(), rotation()) :: t()
  def update_position(entity, position, rotation) do
    %{entity | position: position, rotation: rotation}
  end

  @doc """
  Check if entity is a player.
  """
  @spec player?(t()) :: boolean()
  def player?(%__MODULE__{type: :player}), do: true
  def player?(_), do: false

  @doc """
  Get entity type as integer for packet serialization.
  """
  @spec type_to_int(entity_type()) :: non_neg_integer()
  def type_to_int(:player), do: @entity_type_player
  def type_to_int(:creature), do: @entity_type_creature
  def type_to_int(:object), do: @entity_type_object
  def type_to_int(:vehicle), do: @entity_type_vehicle
  def type_to_int(_), do: @entity_type_object

  @doc """
  Convert integer to entity type.
  """
  @spec int_to_type(non_neg_integer()) :: entity_type()
  def int_to_type(@entity_type_player), do: :player
  def int_to_type(@entity_type_creature), do: :creature
  def int_to_type(@entity_type_object), do: :object
  def int_to_type(@entity_type_vehicle), do: :vehicle
  def int_to_type(_), do: :object

  @doc """
  Get position X coordinate.
  """
  @spec position_x(t()) :: float()
  def position_x(%__MODULE__{position: {x, _, _}}), do: x

  @doc """
  Get position Y coordinate.
  """
  @spec position_y(t()) :: float()
  def position_y(%__MODULE__{position: {_, y, _}}), do: y

  @doc """
  Get position Z coordinate.
  """
  @spec position_z(t()) :: float()
  def position_z(%__MODULE__{position: {_, _, z}}), do: z

  @doc """
  Get rotation X.
  """
  @spec rotation_x(t()) :: float()
  def rotation_x(%__MODULE__{rotation: {x, _, _}}), do: x

  @doc """
  Get rotation Y.
  """
  @spec rotation_y(t()) :: float()
  def rotation_y(%__MODULE__{rotation: {_, y, _}}), do: y

  @doc """
  Get rotation Z.
  """
  @spec rotation_z(t()) :: float()
  def rotation_z(%__MODULE__{rotation: {_, _, z}}), do: z

  @doc """
  Apply damage to entity.

  Returns the updated entity. Damage cannot reduce health below 0.
  """
  @spec apply_damage(t(), non_neg_integer()) :: t()
  def apply_damage(%__MODULE__{} = entity, damage) when damage >= 0 do
    new_health = max(0, entity.health - damage)
    %{entity | health: new_health}
  end

  @doc """
  Apply healing to entity.

  Returns the updated entity. Healing cannot exceed max_health.
  """
  @spec apply_healing(t(), non_neg_integer()) :: t()
  def apply_healing(%__MODULE__{} = entity, healing) when healing >= 0 do
    new_health = min(entity.max_health, entity.health + healing)
    %{entity | health: new_health}
  end

  @doc """
  Set entity health directly.

  Clamps to valid range [0, max_health].
  """
  @spec set_health(t(), integer()) :: t()
  def set_health(%__MODULE__{} = entity, health) do
    new_health = health |> max(0) |> min(entity.max_health)
    %{entity | health: new_health}
  end

  @doc """
  Check if entity is dead (health <= 0).
  """
  @spec dead?(t()) :: boolean()
  def dead?(%__MODULE__{health: 0}), do: true
  def dead?(%__MODULE__{}), do: false

  @doc """
  Check if entity is alive (health > 0).
  """
  @spec alive?(t()) :: boolean()
  def alive?(%__MODULE__{health: health}) when health > 0, do: true
  def alive?(%__MODULE__{}), do: false

  @doc """
  Get health percentage (0.0 to 1.0).
  """
  @spec health_percent(t()) :: float()
  def health_percent(%__MODULE__{max_health: 0}), do: 0.0

  def health_percent(%__MODULE__{health: health, max_health: max_health}) do
    health / max_health
  end

  @doc """
  Restore entity to full health.
  """
  @spec restore_health(t()) :: t()
  def restore_health(%__MODULE__{max_health: max_health} = entity) do
    %{entity | health: max_health}
  end

  # Targeting functions

  @doc """
  Set entity's target.
  """
  @spec set_target(t(), non_neg_integer() | nil) :: t()
  def set_target(%__MODULE__{} = entity, target_guid) do
    %{entity | target_guid: target_guid}
  end

  @doc """
  Clear entity's target.
  """
  @spec clear_target(t()) :: t()
  def clear_target(%__MODULE__{} = entity) do
    %{entity | target_guid: nil}
  end

  @doc """
  Check if entity has a target.
  """
  @spec has_target?(t()) :: boolean()
  def has_target?(%__MODULE__{target_guid: nil}), do: false
  def has_target?(%__MODULE__{}), do: true

  # Experience functions

  @doc """
  Add experience to entity.
  """
  @spec add_experience(t(), non_neg_integer()) :: t()
  def add_experience(%__MODULE__{} = entity, xp) when xp >= 0 do
    %{entity | experience: entity.experience + xp}
  end

  @doc """
  Set entity's experience.
  """
  @spec set_experience(t(), non_neg_integer()) :: t()
  def set_experience(%__MODULE__{} = entity, xp) when xp >= 0 do
    %{entity | experience: xp}
  end

  @doc """
  Level up entity.
  """
  @spec level_up(t(), non_neg_integer(), non_neg_integer()) :: t()
  def level_up(%__MODULE__{} = entity, new_level, new_max_health) do
    %{entity | level: new_level, max_health: new_max_health, health: new_max_health}
  end

  # Death state functions

  @doc """
  Mark entity as dead.
  """
  @spec mark_dead(t()) :: t()
  def mark_dead(%__MODULE__{} = entity) do
    %{entity | is_dead: true, health: 0}
  end

  @doc """
  Respawn entity (clear death state, restore health).
  """
  @spec respawn(t()) :: t()
  def respawn(%__MODULE__{max_health: max_health} = entity) do
    %{entity | is_dead: false, health: max_health}
  end

  @doc """
  Respawn entity at a specific position.
  """
  @spec respawn_at(t(), position()) :: t()
  def respawn_at(%__MODULE__{max_health: max_health} = entity, position) do
    %{entity | is_dead: false, health: max_health, position: position}
  end

  # Buff/Debuff functions

  alias BezgelorCore.{BuffDebuff, ActiveEffect}

  @doc """
  Apply a buff or debuff to the entity.
  """
  @spec apply_buff(t(), BuffDebuff.t(), non_neg_integer(), integer()) :: t()
  def apply_buff(%__MODULE__{} = entity, %BuffDebuff{} = buff, caster_guid, now_ms) do
    effects = ActiveEffect.apply(entity.active_effects, buff, caster_guid, now_ms)
    %{entity | active_effects: effects}
  end

  @doc """
  Remove a buff or debuff from the entity.
  """
  @spec remove_buff(t(), non_neg_integer()) :: t()
  def remove_buff(%__MODULE__{} = entity, buff_id) do
    effects = ActiveEffect.remove(entity.active_effects, buff_id)
    %{entity | active_effects: effects}
  end

  @doc """
  Check if entity has an active buff/debuff.
  """
  @spec has_buff?(t(), non_neg_integer(), integer()) :: boolean()
  def has_buff?(%__MODULE__{} = entity, buff_id, now_ms) do
    ActiveEffect.active?(entity.active_effects, buff_id, now_ms)
  end

  @doc """
  Get a stat value with all active modifiers applied.
  """
  @spec get_modified_stat(t(), BuffDebuff.stat(), map(), integer()) :: number()
  def get_modified_stat(%__MODULE__{} = entity, stat, base_stats, now_ms) do
    base_value = Map.get(base_stats, stat, 0)
    modifier = ActiveEffect.get_stat_modifier(entity.active_effects, stat, now_ms)
    base_value + modifier
  end

  @doc """
  Apply damage with absorb shield processing.

  Returns `{updated_entity, absorbed_amount}`.
  """
  @spec apply_damage_with_absorb(t(), non_neg_integer(), integer()) :: {t(), non_neg_integer()}
  def apply_damage_with_absorb(%__MODULE__{} = entity, damage, now_ms) do
    {effects, absorbed, remaining_damage} =
      ActiveEffect.consume_absorb(entity.active_effects, damage, now_ms)

    entity = %{entity | active_effects: effects}
    entity = apply_damage(entity, remaining_damage)

    {entity, absorbed}
  end

  @doc """
  Clean up expired effects from the entity.
  """
  @spec cleanup_effects(t(), integer()) :: t()
  def cleanup_effects(%__MODULE__{} = entity, now_ms) do
    effects = ActiveEffect.cleanup(entity.active_effects, now_ms)
    %{entity | active_effects: effects}
  end

  @doc """
  List all active buffs (non-debuffs).
  """
  @spec list_buffs(t(), integer()) :: [map()]
  def list_buffs(%__MODULE__{} = entity, now_ms) do
    entity.active_effects
    |> ActiveEffect.list_active(now_ms)
    |> Enum.filter(fn %{buff: buff} -> BuffDebuff.buff?(buff) end)
  end

  @doc """
  List all active debuffs.
  """
  @spec list_debuffs(t(), integer()) :: [map()]
  def list_debuffs(%__MODULE__{} = entity, now_ms) do
    entity.active_effects
    |> ActiveEffect.list_active(now_ms)
    |> Enum.filter(fn %{buff: buff} -> BuffDebuff.debuff?(buff) end)
  end
end
