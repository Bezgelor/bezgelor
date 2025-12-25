defmodule BezgelorWorld.World.CreatureState do
  @moduledoc """
  Pure functions for creature state management and AI processing.

  This module contains creature-related logic extracted from World.Instance
  for better code organization, testability, and maintainability.

  ## Responsibilities

  - Creature spawning and template resolution
  - AI tick processing for individual creatures
  - Damage application and death handling
  - Combat state transitions
  - Movement path generation

  ## Usage

  This module provides pure functions that operate on creature state maps.
  World.Instance calls these functions and manages the overall state.

      # Build a creature from spawn definition
      {:ok, guid, creature_state} = CreatureState.build_from_spawn_def(spawn_def, world_id, spline_index)

      # Process AI tick for a creature
      {:updated, new_state} = CreatureState.process_ai_tick(creature_state, context)

      # Apply damage
      {:ok, result, new_state} = CreatureState.apply_damage(creature_state, attacker_guid, damage, opts)
  """

  alias BezgelorCore.{AI, CreatureTemplate, Entity, Movement}
  alias BezgelorData.Store
  alias BezgelorWorld.{CreatureDeath, WorldManager}

  require Logger

  @type creature_state :: %{
          entity: Entity.t(),
          template: CreatureTemplate.t(),
          ai: AI.t(),
          spawn_position: {float(), float(), float()},
          respawn_timer: reference() | nil,
          target_position: {float(), float(), float()} | nil,
          world_id: non_neg_integer(),
          spawn_def: map() | nil
        }

  @type ai_context :: %{
          entities: map(),
          players: MapSet.t(),
          world_id: non_neg_integer(),
          instance_id: non_neg_integer()
        }

  # =====================================================================
  # Creature Spawning
  # =====================================================================

  @doc """
  Build a creature state from a spawn definition.

  Returns `{:ok, guid, creature_state}` on success, `{:error, reason}` on failure.
  """
  @spec build_from_spawn_def(map(), non_neg_integer(), map()) ::
          {:ok, non_neg_integer(), creature_state()} | {:error, atom()}
  def build_from_spawn_def(spawn_def, world_id, spline_index) do
    creature_id = spawn_def.creature_id
    [x, y, z] = spawn_def.position
    position = {x, y, z}

    case get_template(creature_id, spawn_def) do
      {:error, reason} ->
        {:error, reason}

      {:ok, template, display_info, outfit_info} ->
        guid = WorldManager.generate_guid(:creature)

        entity = %Entity{
          guid: guid,
          type: :creature,
          name: template.name,
          display_info: display_info,
          outfit_info: outfit_info,
          faction: spawn_def[:faction1] || faction_to_int(template.faction),
          level: template.level,
          position: position,
          creature_id: creature_id,
          health: template.max_health,
          max_health: template.max_health
        }

        ai_opts = build_ai_options(spawn_def, world_id, position, spline_index)
        ai = AI.new(position, ai_opts)

        creature_state = %{
          entity: entity,
          template: template,
          ai: ai,
          spawn_position: position,
          respawn_timer: nil,
          spawn_def: spawn_def,
          world_id: world_id,
          target_position: nil
        }

        {:ok, guid, creature_state}
    end
  end

  @doc """
  Build a creature state from a template ID and position (for dynamic spawning).
  """
  @spec build_from_template(non_neg_integer(), {float(), float(), float()}, non_neg_integer()) ::
          {:ok, non_neg_integer(), creature_state()} | {:error, atom()}
  def build_from_template(template_id, position, world_id) do
    spawn_def = %{
      creature_id: template_id,
      position: Tuple.to_list(position)
    }

    build_from_spawn_def(spawn_def, world_id, %{})
  end

  # =====================================================================
  # AI Processing
  # =====================================================================

  @doc """
  Check if a creature needs AI processing this tick.
  """
  @spec needs_processing?(creature_state()) :: boolean()
  def needs_processing?(%{ai: ai, template: template}) do
    ai.state == :combat or
      ai.state == :evade or
      ai.state == :wandering or
      ai.state == :patrol or
      map_size(ai.threat_table) > 0 or
      (ai.state == :idle and ai.patrol_enabled) or
      (ai.state == :idle and template.ai_type == :aggressive and (template.aggro_range || 0.0) > 0)
  end

  @doc """
  Process AI tick for a single creature.

  Returns `{:no_change, creature_state}` or `{:updated, new_creature_state, actions}`
  where actions is a list of side effects to perform (e.g., broadcasts).
  """
  @spec process_ai_tick(creature_state(), ai_context(), non_neg_integer()) ::
          {:no_change, creature_state()} | {:updated, creature_state(), list()}
  def process_ai_tick(creature_state, context, now) do
    %{ai: ai, template: template} = creature_state

    # For idle aggressive creatures, check for nearby players to aggro
    if ai.state == :idle and template.ai_type == :aggressive and (template.aggro_range || 0.0) > 0 do
      case check_aggro_nearby_players(creature_state, context) do
        {:aggro, player_guid} ->
          new_ai = AI.enter_combat(ai, player_guid)
          {:updated, %{creature_state | ai: new_ai}, []}

        nil ->
          process_ai_tick_internal(creature_state, context, now)
      end
    else
      process_ai_tick_internal(creature_state, context, now)
    end
  end

  @doc """
  Check for players to aggro.

  Returns `{:aggro, player_guid}` or `nil`.
  """
  @spec check_aggro_nearby_players(creature_state(), ai_context()) ::
          {:aggro, non_neg_integer()} | nil
  def check_aggro_nearby_players(creature_state, context) do
    creature_pos = creature_state.entity.position
    aggro_range = creature_state.template.aggro_range || 15.0
    creature_faction = creature_state.template.faction || :hostile

    nearby_players = get_nearby_players(context, creature_pos, aggro_range)
    AI.check_aggro_with_faction(creature_state.ai, nearby_players, aggro_range, creature_faction)
  end

  # =====================================================================
  # Damage and Combat
  # =====================================================================

  @doc """
  Apply damage to a creature.

  Returns `{:ok, :damaged, info, new_state}` or `{:ok, :killed, info, new_state}`.
  """
  @spec apply_damage(creature_state(), non_neg_integer(), non_neg_integer(), keyword()) ::
          {:ok, :damaged | :killed, map(), creature_state()}
  def apply_damage(creature_state, attacker_guid, damage, opts \\ []) do
    entity = Entity.apply_damage(creature_state.entity, damage)
    ai = AI.add_threat(creature_state.ai, attacker_guid, damage)

    # Enter combat if not already
    ai =
      if not AI.in_combat?(ai) do
        AI.enter_combat(ai, attacker_guid)
      else
        ai
      end

    if Entity.dead?(entity) do
      killer_level = Keyword.get(opts, :killer_level, creature_state.template.level)

      # handle_death returns {{:ok, :killed, result_info}, new_creature_state}
      {{:ok, :killed, result_info}, new_creature_state} =
        CreatureDeath.handle_death(creature_state, entity, attacker_guid, killer_level)

      {:ok, :killed, result_info, new_creature_state}
    else
      new_creature_state = %{creature_state | entity: entity, ai: ai}

      result_info = %{
        remaining_health: entity.health,
        max_health: entity.max_health
      }

      {:ok, :damaged, result_info, new_creature_state}
    end
  end

  @doc """
  Enter combat with a target.
  """
  @spec enter_combat(creature_state(), non_neg_integer()) :: creature_state()
  def enter_combat(creature_state, target_guid) do
    if AI.dead?(creature_state.ai) do
      # Can't enter combat when dead
      creature_state
    else
      new_ai = AI.enter_combat(creature_state.ai, target_guid)
      %{creature_state | ai: new_ai}
    end
  end

  @doc """
  Check if a creature is targetable (alive and not despawned).
  """
  @spec targetable?(creature_state()) :: boolean()
  def targetable?(creature_state) do
    not AI.dead?(creature_state.ai) and creature_state.entity.health > 0
  end

  # =====================================================================
  # Template Resolution
  # =====================================================================

  @doc """
  Get creature template from ID.
  """
  @spec get_template(non_neg_integer(), map()) ::
          {:ok, CreatureTemplate.t(), non_neg_integer(), non_neg_integer()} | {:error, atom()}
  def get_template(creature_id, spawn_def) do
    case CreatureTemplate.get(creature_id) do
      nil ->
        # Fall back to BezgelorData
        case BezgelorData.get_creature(creature_id) do
          {:ok, creature_data} ->
            build_template_from_data(creature_id, creature_data, spawn_def)

          :error ->
            {:error, :template_not_found}
        end

      template ->
        display_info =
          if spawn_def[:display_info] && spawn_def.display_info > 0 do
            spawn_def.display_info
          else
            template.display_info
          end

        outfit_info = spawn_def[:outfit_info] || 0
        {:ok, template, display_info, outfit_info}
    end
  end

  # =====================================================================
  # Calculation Helpers (Pure Functions)
  # =====================================================================

  @doc """
  Convert tier ID to a random creature level within the tier's range.

  WildStar creatures have tiers that correspond to level ranges:

  | Tier | Level Range |
  |------|-------------|
  | 1    | 1-10        |
  | 2    | 10-20       |
  | 3    | 20-35       |
  | 4    | 35-50       |

  ## Examples

      iex> level = CreatureState.tier_to_level(1)
      iex> level in 1..10
      true

      iex> level = CreatureState.tier_to_level(3)
      iex> level in 20..35
      true
  """
  @spec tier_to_level(non_neg_integer()) :: non_neg_integer()
  def tier_to_level(tier_id) do
    case tier_id do
      1 -> Enum.random(1..10)
      2 -> Enum.random(10..20)
      3 -> Enum.random(20..35)
      4 -> Enum.random(35..50)
      _ -> Enum.random(1..50)
    end
  end

  @doc """
  Calculate max health from tier, difficulty, and level.
  """
  @spec calculate_max_health(non_neg_integer(), non_neg_integer(), non_neg_integer()) ::
          non_neg_integer()
  def calculate_max_health(tier_id, difficulty_id, level) do
    base_health = 50 + level * 20

    tier_mult =
      case tier_id do
        1 -> 1.0
        2 -> 1.5
        3 -> 2.0
        4 -> 3.0
        _ -> 1.0
      end

    difficulty_mult =
      case difficulty_id do
        1 -> 1.0
        2 -> 2.0
        3 -> 5.0
        4 -> 10.0
        _ -> 1.0
      end

    round(base_health * tier_mult * difficulty_mult)
  end

  @doc """
  Calculate damage range from level and difficulty.
  """
  @spec calculate_damage(non_neg_integer(), non_neg_integer()) ::
          {non_neg_integer(), non_neg_integer()}
  def calculate_damage(level, difficulty_id) do
    base_min = 5 + level
    base_max = 10 + level * 2

    mult =
      case difficulty_id do
        1 -> 1.0
        2 -> 1.5
        3 -> 2.0
        4 -> 3.0
        _ -> 1.0
      end

    {round(base_min * mult), round(base_max * mult)}
  end

  @doc """
  Convert creature archetype ID to AI behavior type.

  WildStar archetypes define creature behavior patterns. This function maps
  archetype IDs to simplified AI types used by the server:

  | Archetype ID | AI Type      | Behavior                                |
  |--------------|--------------|----------------------------------------|
  | 30           | `:passive`   | Never attacks, flees when damaged      |
  | 31           | `:defensive` | Only attacks when provoked             |
  | Other        | `:aggressive`| Attacks players within aggro range     |

  ## Examples

      iex> CreatureState.archetype_to_ai_type(30)
      :passive

      iex> CreatureState.archetype_to_ai_type(31)
      :defensive

      iex> CreatureState.archetype_to_ai_type(0)
      :aggressive
  """
  @spec archetype_to_ai_type(non_neg_integer()) :: atom()
  def archetype_to_ai_type(archetype_id) do
    case archetype_id do
      30 -> :passive
      31 -> :defensive
      _ -> :aggressive
    end
  end

  @doc """
  Convert faction atom to integer for protocol serialization.

  Factions determine how creatures interact with players:

  | Faction     | Integer | Behavior                                    |
  |-------------|---------|---------------------------------------------|
  | `:hostile`  | 0       | Red nameplate, can be attacked, may aggro  |
  | `:neutral`  | 1       | Yellow nameplate, attackable but no aggro  |
  | `:friendly` | 2       | Green nameplate, cannot be attacked         |

  Unknown factions default to `:hostile` (0) for safety.

  ## Examples

      iex> CreatureState.faction_to_int(:hostile)
      0

      iex> CreatureState.faction_to_int(:friendly)
      2

      iex> CreatureState.faction_to_int(:unknown)
      0
  """
  @spec faction_to_int(atom()) :: non_neg_integer()
  def faction_to_int(:hostile), do: 0
  def faction_to_int(:neutral), do: 1
  def faction_to_int(:friendly), do: 2
  def faction_to_int(_), do: 0

  # =====================================================================
  # Private Functions - AI Processing
  # =====================================================================

  defp process_ai_tick_internal(creature_state, context, now) do
    %{ai: ai, template: template, entity: entity} = creature_state

    if ai.state == :combat do
      current_pos = entity.position
      leash_range = template.leash_range || 40.0

      case AI.check_leash(ai, current_pos, leash_range) do
        :evade ->
          new_ai = AI.start_evade(ai)
          {:updated, %{creature_state | ai: new_ai}, []}

        :ok ->
          process_combat_ai_tick(creature_state, context)
      end
    else
      process_normal_ai_tick(creature_state, context, now)
    end
  end

  defp process_combat_ai_tick(creature_state, context) do
    %{ai: ai, template: template, entity: entity} = creature_state

    target_pos = get_target_position(creature_state, context)
    attack_range = CreatureTemplate.attack_range(template)

    case AI.combat_action(ai, target_pos, attack_range) do
      :none ->
        {:no_change, creature_state}

      :wait ->
        {:no_change, creature_state}

      {:attack, target_guid} ->
        current_pos = entity.position
        {tx, ty, tz} = target_pos
        {cx, cy, cz} = current_pos

        current_distance =
          :math.sqrt((tx - cx) * (tx - cx) + (ty - cy) * (ty - cy) + (tz - cz) * (tz - cz))

        min_range = if template.is_ranged, do: attack_range * 0.5, else: 0.0

        if template.is_ranged and current_distance < min_range do
          path = Movement.ranged_position_path(current_pos, target_pos, min_range, attack_range)

          if length(path) > 1 do
            path_length = Movement.path_length(path)
            duration = CreatureTemplate.movement_duration(template, path_length)
            new_ai = AI.start_chase(ai, path, duration)
            speed = CreatureTemplate.movement_speed(template)
            end_pos = List.last(path)
            new_entity = %{entity | position: end_pos}

            actions = [{:broadcast_movement, entity.guid, path, speed}]
            {:updated, %{creature_state | ai: new_ai, entity: new_entity}, actions}
          else
            {:no_change, creature_state}
          end
        else
          actions =
            if AI.chasing?(ai) do
              [{:broadcast_stop, entity.guid}]
            else
              []
            end

          new_ai = AI.record_attack(ai) |> AI.complete_chase()
          attack_action = {:creature_attack, entity, template, target_guid}
          {:updated, %{creature_state | ai: new_ai}, actions ++ [attack_action]}
        end

      {:chase, chase_target_pos} ->
        current_pos = entity.position

        path =
          if template.is_ranged do
            min_range = attack_range * 0.5
            Movement.ranged_position_path(current_pos, chase_target_pos, min_range, attack_range)
          else
            Movement.chase_path(current_pos, chase_target_pos, attack_range)
          end

        if length(path) > 1 do
          path_length = Movement.path_length(path)
          duration = CreatureTemplate.movement_duration(template, path_length)
          new_ai = AI.start_chase(ai, path, duration)
          speed = CreatureTemplate.movement_speed(template)
          end_pos = List.last(path)
          new_entity = %{entity | position: end_pos}

          actions = [{:broadcast_movement, entity.guid, path, speed}]
          {:updated, %{creature_state | ai: new_ai, entity: new_entity}, actions}
        else
          {:no_change, creature_state}
        end
    end
  end

  defp process_normal_ai_tick(creature_state, _context, _now) do
    %{ai: ai, template: template, entity: entity} = creature_state

    context = %{
      attack_speed: template.attack_speed,
      position: entity.position
    }

    case AI.tick(ai, context) do
      :none ->
        {:no_change, creature_state}

      {:move_to, target_pos} ->
        current_pos = entity.position
        dist_to_target = AI.distance(current_pos, target_pos)

        if dist_to_target < 2.0 do
          if ai.state == :evade do
            new_ai = AI.complete_evade(ai)

            new_entity = %{
              entity
              | health: template.max_health,
                position: target_pos
            }

            {:updated, %{creature_state | ai: new_ai, entity: new_entity}, []}
          else
            {:no_change, creature_state}
          end
        else
          new_pos = move_toward(current_pos, target_pos, 5.0)
          new_entity = %{entity | position: new_pos}
          {:updated, %{creature_state | entity: new_entity}, []}
        end

      {:start_wander, new_ai} ->
        end_position = List.last(new_ai.movement_path) || entity.position
        new_entity = %{entity | position: end_position}
        actions = [{:broadcast_movement, entity.guid, new_ai.movement_path, new_ai.wander_speed}]
        {:updated, %{creature_state | ai: new_ai, entity: new_entity}, actions}

      {:wander_complete, new_ai} ->
        {:updated, %{creature_state | ai: new_ai}, []}

      {:start_patrol, new_ai} ->
        end_position = List.last(new_ai.movement_path) || entity.position
        new_entity = %{entity | position: end_position}
        actions = [{:broadcast_movement, entity.guid, new_ai.movement_path, new_ai.patrol_speed}]
        {:updated, %{creature_state | ai: new_ai, entity: new_entity}, actions}

      {:patrol_segment_complete, new_ai} ->
        {:updated, %{creature_state | ai: new_ai}, []}

      _ ->
        {:no_change, creature_state}
    end
  end

  defp get_target_position(creature_state, context) do
    case Map.get(creature_state, :target_position) do
      nil ->
        target_guid = creature_state.ai.target_guid

        case Map.get(context.entities, target_guid) do
          nil -> creature_state.entity.position
          target -> target.position
        end

      pos ->
        pos
    end
  end

  defp get_nearby_players(context, position, range) do
    context.players
    |> MapSet.to_list()
    |> Enum.map(&Map.get(context.entities, &1))
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(fn e -> AI.distance(e.position, position) <= range end)
    |> Enum.map(fn e ->
      %{
        guid: e.guid,
        position: e.position,
        faction: Map.get(e, :faction, :exile)
      }
    end)
  end

  defp move_toward({x1, y1, z1}, {x2, y2, z2}, step_distance) do
    dx = x2 - x1
    dy = y2 - y1
    dz = z2 - z1
    length = :math.sqrt(dx * dx + dy * dy + dz * dz)

    if length <= step_distance do
      {x2, y2, z2}
    else
      ratio = step_distance / length
      {x1 + dx * ratio, y1 + dy * ratio, z1 + dz * ratio}
    end
  end

  # =====================================================================
  # Private Functions - Template Building
  # =====================================================================

  defp build_template_from_data(creature_id, creature_data, spawn_def) do
    name = get_creature_name(creature_data)
    tier_id = Map.get(creature_data, :tier_id, 1)
    difficulty_id = Map.get(creature_data, :difficulty_id, 1)
    level = tier_to_level(tier_id)
    max_health = calculate_max_health(tier_id, difficulty_id, level)
    {damage_min, damage_max} = calculate_damage(level, difficulty_id)
    ai_type = archetype_to_ai_type(Map.get(creature_data, :archetype_id, 0))

    template = %CreatureTemplate{
      id: creature_id,
      name: name,
      level: level,
      max_health: max_health,
      faction: :hostile,
      display_info: Map.get(creature_data, :display_group_id, 0),
      ai_type: ai_type,
      aggro_range: if(ai_type == :aggressive, do: 15.0, else: 0.0),
      leash_range: 40.0,
      respawn_time: 60_000,
      xp_reward: level * 10,
      loot_table_id: nil,
      damage_min: damage_min,
      damage_max: damage_max,
      attack_speed: 2000
    }

    display_info =
      if spawn_def[:display_info] && spawn_def.display_info > 0 do
        spawn_def.display_info
      else
        template.display_info
      end

    outfit_info =
      if spawn_def[:outfit_info] && spawn_def.outfit_info > 0 do
        spawn_def.outfit_info
      else
        Map.get(creature_data, :outfit_group_id, 0)
      end

    {:ok, template, display_info, outfit_info}
  end

  defp get_creature_name(creature_data) do
    name_text_id = Map.get(creature_data, :name_text_id, 0)

    case BezgelorData.get_text(name_text_id) do
      {:ok, text} -> text
      :error -> "Creature #{Map.get(creature_data, :id, 0)}"
    end
  end

  # =====================================================================
  # Private Functions - AI Options
  # =====================================================================

  defp build_ai_options(spawn_def, world_id, position, spline_index) do
    waypoints = Map.get(spawn_def, :patrol_waypoints)

    cond do
      is_list(waypoints) and length(waypoints) > 1 ->
        [
          patrol_waypoints: waypoints,
          patrol_speed: Map.get(spawn_def, :patrol_speed, 3.0),
          patrol_mode: Map.get(spawn_def, :patrol_mode, :cyclic)
        ]

      spline_id = Map.get(spawn_def, :spline_id) ->
        case Store.get_spline_as_patrol(spline_id) do
          {:ok, patrol_data} ->
            [
              patrol_waypoints: patrol_data.waypoints,
              patrol_speed: Map.get(spawn_def, :spline_speed, patrol_data.speed),
              patrol_mode: Map.get(spawn_def, :spline_mode, patrol_data.mode)
            ]

          :error ->
            []
        end

      path_name = Map.get(spawn_def, :patrol_path) ->
        case Store.get_patrol_path(path_name) do
          {:ok, patrol_data} ->
            [
              patrol_waypoints: patrol_data.waypoints,
              patrol_speed: patrol_data.speed,
              patrol_mode: patrol_data.mode
            ]

          :error ->
            []
        end

      Map.get(spawn_def, :auto_spline, true) ->
        find_auto_spline(spline_index, world_id, position)

      true ->
        []
    end
  end

  defp find_auto_spline(spline_index, world_id, position) do
    case Store.find_nearest_spline_indexed(spline_index, world_id, position, max_distance: 15.0) do
      {:ok, spline_id, _distance} ->
        case Store.get_spline_as_patrol(spline_id) do
          {:ok, patrol_data} ->
            [
              patrol_waypoints: patrol_data.waypoints,
              patrol_speed: patrol_data.speed,
              patrol_mode: patrol_data.mode
            ]

          :error ->
            []
        end

      :none ->
        []
    end
  end
end
