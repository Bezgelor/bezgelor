defmodule BezgelorWorld.Creature.ZoneManager do
  @moduledoc """
  Per-zone creature manager.

  Each zone instance has its own ZoneManager handling creature AI, spawns,
  and state for that zone only. This distributes AI processing across multiple
  processes instead of having a single global CreatureManager bottleneck.

  ## Architecture

  - One ZoneManager per active zone instance
  - Started by World.InstanceSupervisor alongside World.Instance
  - Handles all creatures within its zone
  - Communicates with World.Instance for entity tracking

  ## Usage

      # Spawn a creature in a specific zone
      {:ok, guid} = ZoneManager.spawn_creature(zone_id, instance_id, template_id, position)

      # Apply damage to a creature
      {:ok, :damaged, info} = ZoneManager.damage_creature(zone_id, instance_id, guid, attacker, 100)
  """

  use GenServer

  require Logger

  alias BezgelorCore.{AI, CreatureTemplate, Entity}
  alias BezgelorWorld.{CombatBroadcaster, CreatureDeath, TickScheduler, WorldManager}
  alias BezgelorData.Store

  alias BezgelorWorld.World.Instance, as: WorldInstance

  @type creature_state :: %{
          entity: Entity.t(),
          template: CreatureTemplate.t(),
          ai: AI.t(),
          spawn_position: {float(), float(), float()},
          respawn_timer: reference() | nil
        }

  @type state :: %{
          zone_id: non_neg_integer(),
          instance_id: non_neg_integer(),
          creatures: %{non_neg_integer() => creature_state()},
          spawn_definitions: [map()]
        }

  # Combat timeout - creatures exit combat after this many ms without activity
  @combat_timeout_ms 30_000

  ## Client API

  @doc "Start a ZoneManager for a specific zone instance."
  def start_link(opts) do
    zone_id = Keyword.fetch!(opts, :zone_id)
    instance_id = Keyword.fetch!(opts, :instance_id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(zone_id, instance_id))
  end

  @doc "Registry lookup for zone-specific creature manager."
  def via_tuple(zone_id, instance_id) do
    {:via, Registry, {BezgelorWorld.Creature.Registry, {zone_id, instance_id}}}
  end

  @doc "Spawn a creature in a zone instance."
  @spec spawn_creature(
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          {float(), float(), float()}
        ) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def spawn_creature(zone_id, instance_id, template_id, position) do
    GenServer.call(via_tuple(zone_id, instance_id), {:spawn_creature, template_id, position})
  end

  @doc "Get a creature by GUID from a zone instance."
  @spec get_creature(non_neg_integer(), non_neg_integer(), non_neg_integer()) ::
          creature_state() | nil
  def get_creature(zone_id, instance_id, guid) do
    GenServer.call(via_tuple(zone_id, instance_id), {:get_creature, guid})
  end

  @doc "Get all creatures in a zone instance."
  @spec list_creatures(non_neg_integer(), non_neg_integer()) :: [creature_state()]
  def list_creatures(zone_id, instance_id) do
    GenServer.call(via_tuple(zone_id, instance_id), :list_creatures)
  end

  @doc "Get creatures within range of a position in a zone instance."
  @spec get_creatures_in_range(
          non_neg_integer(),
          non_neg_integer(),
          {float(), float(), float()},
          float()
        ) ::
          [creature_state()]
  def get_creatures_in_range(zone_id, instance_id, position, range) do
    GenServer.call(via_tuple(zone_id, instance_id), {:get_creatures_in_range, position, range})
  end

  @doc "Apply damage to a creature in a zone instance."
  @spec damage_creature(
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer()
        ) ::
          {:ok, :damaged | :killed, map()} | {:error, term()}
  def damage_creature(zone_id, instance_id, creature_guid, attacker_guid, damage) do
    GenServer.call(
      via_tuple(zone_id, instance_id),
      {:damage_creature, creature_guid, attacker_guid, damage}
    )
  end

  @doc "Set creature's target (for player targeting creature)."
  @spec creature_enter_combat(
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer()
        ) :: :ok
  def creature_enter_combat(zone_id, instance_id, creature_guid, target_guid) do
    GenServer.cast(
      via_tuple(zone_id, instance_id),
      {:creature_enter_combat, creature_guid, target_guid}
    )
  end

  @doc "Check if a creature is alive and targetable."
  @spec creature_targetable?(non_neg_integer(), non_neg_integer(), non_neg_integer()) :: boolean()
  def creature_targetable?(zone_id, instance_id, guid) do
    GenServer.call(via_tuple(zone_id, instance_id), {:creature_targetable, guid})
  end

  @doc "Get creature count in a zone instance."
  @spec creature_count(non_neg_integer(), non_neg_integer()) :: non_neg_integer()
  def creature_count(zone_id, instance_id) do
    GenServer.call(via_tuple(zone_id, instance_id), :creature_count)
  end

  @doc "Load all creature spawns for the zone from static data."
  @spec load_zone_spawns(non_neg_integer(), non_neg_integer()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def load_zone_spawns(zone_id, instance_id) do
    GenServer.call(via_tuple(zone_id, instance_id), :load_zone_spawns, 30_000)
  end

  @doc "Clear all spawned creatures."
  @spec clear_all_creatures(non_neg_integer(), non_neg_integer()) :: :ok
  def clear_all_creatures(zone_id, instance_id) do
    GenServer.call(via_tuple(zone_id, instance_id), :clear_all_creatures)
  end

  @doc "Lookup creature manager for a zone, returns nil if not running."
  @spec whereis(non_neg_integer(), non_neg_integer()) :: pid() | nil
  def whereis(zone_id, instance_id) do
    case Registry.lookup(BezgelorWorld.Creature.Registry, {zone_id, instance_id}) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  ## Server Callbacks

  @impl true
  def init(opts) do
    zone_id = Keyword.fetch!(opts, :zone_id)
    instance_id = Keyword.fetch!(opts, :instance_id)

    # Build spatial index for efficient spline lookups during spawn
    # This is done once at startup rather than per-creature for performance
    spline_index = Store.build_spline_spatial_index()

    state = %{
      zone_id: zone_id,
      instance_id: instance_id,
      creatures: %{},
      spawn_definitions: [],
      spline_index: spline_index
    }

    # Register with TickScheduler to receive tick notifications
    # This ensures all systems (buffs, AI, etc.) tick in sync
    # In tests, TickScheduler may not be running, so we handle that gracefully
    try do
      TickScheduler.register_listener(self())

      Logger.info(
        "Creature.ZoneManager started for zone #{zone_id} instance #{instance_id}, registered with TickScheduler"
      )
    catch
      :exit, _ ->
        Logger.info(
          "Creature.ZoneManager started for zone #{zone_id} instance #{instance_id} (TickScheduler not available)"
        )
    end

    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call({:spawn_creature, template_id, position}, _from, state) do
    case CreatureTemplate.get(template_id) do
      nil ->
        {:reply, {:error, :template_not_found}, state}

      template ->
        guid = WorldManager.generate_guid(:creature)

        entity = %Entity{
          guid: guid,
          type: :creature,
          name: template.name,
          display_info: template.display_info,
          faction: faction_to_int(template.faction),
          level: template.level,
          position: position,
          health: template.max_health,
          max_health: template.max_health
        }

        ai = AI.new(position)

        creature_state = %{
          entity: entity,
          template: template,
          ai: ai,
          spawn_position: position,
          respawn_timer: nil
        }

        creatures = Map.put(state.creatures, guid, creature_state)

        Logger.debug(
          "Zone #{state.zone_id}/#{state.instance_id}: Spawned creature #{template.name} (#{guid}) at #{inspect(position)}"
        )

        {:reply, {:ok, guid}, %{state | creatures: creatures}}
    end
  end

  @impl true
  def handle_call({:get_creature, guid}, _from, state) do
    {:reply, Map.get(state.creatures, guid), state}
  end

  @impl true
  def handle_call(:list_creatures, _from, state) do
    {:reply, Map.values(state.creatures), state}
  end

  @impl true
  def handle_call({:get_creatures_in_range, position, range}, _from, state) do
    creatures =
      state.creatures
      |> Map.values()
      |> Enum.filter(fn %{entity: entity, ai: ai} ->
        not AI.dead?(ai) and AI.distance(entity.position, position) <= range
      end)

    {:reply, creatures, state}
  end

  @impl true
  def handle_call({:damage_creature, creature_guid, attacker_guid, damage}, _from, state) do
    case Map.get(state.creatures, creature_guid) do
      nil ->
        {:reply, {:error, :creature_not_found}, state}

      %{ai: ai} when ai.state == :dead ->
        {:reply, {:error, :creature_dead}, state}

      creature_state ->
        {result, new_creature_state, state} =
          apply_damage_to_creature(creature_state, attacker_guid, damage, state)

        creatures = Map.put(state.creatures, creature_guid, new_creature_state)
        {:reply, result, %{state | creatures: creatures}}
    end
  end

  @impl true
  def handle_call({:creature_targetable, guid}, _from, state) do
    result =
      case Map.get(state.creatures, guid) do
        nil -> false
        %{ai: ai} -> AI.targetable?(ai)
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call(:creature_count, _from, state) do
    {:reply, map_size(state.creatures), state}
  end

  @impl true
  def handle_call(:load_zone_spawns, _from, state) do
    case Store.get_creature_spawns(state.zone_id) do
      {:ok, zone_data} ->
        {spawned_count, new_state} = spawn_from_definitions(zone_data.creature_spawns, state)

        Logger.info(
          "Zone #{state.zone_id}/#{state.instance_id}: Loaded #{spawned_count} creature spawns"
        )

        {:reply, {:ok, spawned_count}, new_state}

      :error ->
        Logger.warning("Zone #{state.zone_id}/#{state.instance_id}: No spawn data found")
        {:reply, {:error, :no_spawn_data}, state}
    end
  end

  @impl true
  def handle_call(:clear_all_creatures, _from, state) do
    # Cancel any pending respawn timers
    for {_guid, %{respawn_timer: timer}} <- state.creatures, timer != nil do
      Process.cancel_timer(timer)
    end

    Logger.info(
      "Zone #{state.zone_id}/#{state.instance_id}: Cleared #{map_size(state.creatures)} creatures"
    )

    {:reply, :ok, %{state | creatures: %{}, spawn_definitions: []}}
  end

  @impl true
  def handle_cast({:creature_enter_combat, creature_guid, target_guid}, state) do
    state =
      case Map.get(state.creatures, creature_guid) do
        nil ->
          state

        %{ai: ai} when ai.state == :dead ->
          state

        creature_state ->
          ai = AI.enter_combat(creature_state.ai, target_guid)
          new_creature_state = %{creature_state | ai: ai}
          %{state | creatures: Map.put(state.creatures, creature_guid, new_creature_state)}
      end

    {:noreply, state}
  end

  @impl true
  def handle_info({:tick, _tick_number}, state) do
    # Process AI for all creatures in this zone on the shared tick
    # This keeps creature AI in sync with buffs and other periodic effects
    {state, entity_updates} = process_ai_tick(state)

    # Push entity updates to World.Instance for broadcasting
    if entity_updates != [] do
      WorldInstance.update_creature_entities(
        state.zone_id,
        state.instance_id,
        entity_updates
      )
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:respawn_creature, guid}, state) do
    state =
      case Map.get(state.creatures, guid) do
        nil ->
          state

        creature_state ->
          # Respawn the creature
          new_entity = %{
            creature_state.entity
            | health: creature_state.template.max_health,
              position: creature_state.spawn_position
          }

          new_ai = AI.respawn(creature_state.ai)

          new_creature_state = %{
            creature_state
            | entity: new_entity,
              ai: new_ai,
              respawn_timer: nil
          }

          Logger.debug(
            "Zone #{state.zone_id}/#{state.instance_id}: Respawned creature #{new_entity.name} (#{guid})"
          )

          %{state | creatures: Map.put(state.creatures, guid, new_creature_state)}
      end

    {:noreply, state}
  end

  ## Private Functions

  defp apply_damage_to_creature(creature_state, attacker_guid, damage, state) do
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
      # Creature died
      handle_creature_death(creature_state, entity, attacker_guid, state)
    else
      # Still alive
      new_creature_state = %{creature_state | entity: entity, ai: ai}

      result_info = %{
        remaining_health: entity.health,
        max_health: entity.max_health
      }

      {{:ok, :damaged, result_info}, new_creature_state, state}
    end
  end

  defp handle_creature_death(creature_state, entity, killer_guid, state) do
    # Get killer level for loot scaling
    killer_level = get_killer_level(killer_guid, creature_state.template.level, state)

    # Delegate to shared death handling logic with zone context for logging
    {result, new_creature_state} =
      CreatureDeath.handle_death(creature_state, entity, killer_guid, killer_level,
        zone_id: state.zone_id,
        instance_id: state.instance_id
      )

    {result, new_creature_state, state}
  end

  # Get the level of the killer for loot scaling
  # If the killer is a player, try to get their level from zone state
  # Falls back to default_level if not found
  defp get_killer_level(killer_guid, default_level, state) do
    # Check if killer is a player (type bits = 1 in bits 60-63)
    if CreatureDeath.is_player_guid?(killer_guid) do
      # Try to get player entity from our zone state
      case Map.get(state.entities, killer_guid) do
        nil -> default_level
        player_entity -> Map.get(player_entity, :level, default_level)
      end
    else
      default_level
    end
  end

  defp process_ai_tick(state) do
    now = System.monotonic_time(:millisecond)

    # Filter to only creatures that need AI processing
    creatures_needing_update =
      state.creatures
      |> Enum.filter(fn {_guid, creature_state} ->
        needs_ai_processing?(creature_state, now)
      end)

    # Process creatures in parallel across available CPU cores
    # Collect both updated creatures and entity updates for World.Instance
    {creatures, entity_updates} =
      creatures_needing_update
      |> Task.async_stream(
        fn {guid, creature_state} ->
          case process_creature_ai(creature_state, state, now) do
            {:no_change, _} ->
              nil

            {:updated, new_creature_state} ->
              # Return both the guid/state and the entity for World.Instance update
              {guid, new_creature_state, new_creature_state.entity}
          end
        end,
        max_concurrency: System.schedulers_online(),
        timeout: 500,
        on_timeout: :kill_task
      )
      |> Enum.reduce({state.creatures, []}, fn
        {:ok, nil}, acc ->
          acc

        {:ok, {guid, new_creature_state, entity}}, {creatures, updates} ->
          {Map.put(creatures, guid, new_creature_state), [{guid, entity} | updates]}

        {:exit, _reason}, acc ->
          # Task timed out or crashed - skip this creature
          acc
      end)

    {%{state | creatures: creatures}, entity_updates}
  end

  # Determine if a creature needs AI processing this tick
  defp needs_ai_processing?(%{ai: ai}, _now) do
    ai.state == :combat or
      ai.state == :evade or
      ai.state == :patrol or
      (ai.state == :idle and ai.patrol_enabled) or
      map_size(ai.threat_table) > 0
  end

  defp process_creature_ai(
         %{ai: ai, template: template, entity: entity} = creature_state,
         state,
         now
       ) do
    # Check for combat timeout
    ai =
      if ai.state == :combat and ai.combat_start_time do
        combat_duration = now - ai.combat_start_time

        if combat_duration > @combat_timeout_ms and map_size(ai.threat_table) == 0 do
          AI.exit_combat(ai)
        else
          ai
        end
      else
        ai
      end

    context = %{
      attack_speed: template.attack_speed
    }

    case AI.tick(ai, context) do
      :none ->
        # Check for evade completion
        if ai.state == :evade do
          distance = AI.distance(entity.position, ai.spawn_position)

          if distance < 1.0 do
            # Reached spawn, complete evade and restore health
            new_ai = AI.complete_evade(ai)

            new_entity = %{
              entity
              | health: template.max_health,
                position: ai.spawn_position
            }

            {:updated, %{creature_state | ai: new_ai, entity: new_entity}}
          else
            {:no_change, creature_state}
          end
        else
          {:no_change, creature_state}
        end

      {:attack, target_guid} ->
        # Record attack time
        new_ai = AI.record_attack(ai)

        # Apply damage to target
        apply_creature_attack(entity, template, target_guid, state)

        {:updated, %{creature_state | ai: new_ai}}

      {:move_to, _position} ->
        {:no_change, creature_state}
    end
  end

  defp faction_to_int(:hostile), do: 0
  defp faction_to_int(:neutral), do: 1
  defp faction_to_int(:friendly), do: 2
  defp faction_to_int(_), do: 0

  # Spawn creatures from static data definitions
  defp spawn_from_definitions(spawn_defs, state) do
    # Store definitions for reference
    state = %{state | spawn_definitions: state.spawn_definitions ++ spawn_defs}

    # Spawn each creature
    {spawned_count, creatures} =
      Enum.reduce(spawn_defs, {0, state.creatures}, fn spawn_def, {count, creatures} ->
        case spawn_creature_from_def(spawn_def, state) do
          {:ok, guid, creature_state} ->
            {count + 1, Map.put(creatures, guid, creature_state)}

          {:error, reason} ->
            Logger.warning(
              "Zone #{state.zone_id}/#{state.instance_id}: Failed to spawn creature #{spawn_def.creature_id}: #{inspect(reason)}"
            )

            {count, creatures}
        end
      end)

    {spawned_count, %{state | creatures: creatures}}
  end

  # Spawn a single creature from a spawn definition
  defp spawn_creature_from_def(spawn_def, state) do
    creature_id = spawn_def.creature_id
    [x, y, z] = spawn_def.position
    position = {x, y, z}

    case get_creature_template(creature_id, spawn_def) do
      {:error, reason} ->
        {:error, reason}

      {:ok, template, display_info} ->
        guid = WorldManager.generate_guid(:creature)

        entity = %Entity{
          guid: guid,
          type: :creature,
          name: template.name,
          display_info: display_info,
          faction: spawn_def[:faction1] || faction_to_int(template.faction),
          level: template.level,
          position: position,
          creature_id: creature_id,
          health: template.max_health,
          max_health: template.max_health
        }

        # Build AI options, including patrol path if specified
        # Pass zone_id, position, and spline_index for efficient automatic spline matching
        ai_opts = build_ai_options(spawn_def, state.zone_id, position, state.spline_index)
        ai = AI.new(position, ai_opts)

        creature_state = %{
          entity: entity,
          template: template,
          ai: ai,
          spawn_position: position,
          respawn_timer: nil,
          spawn_def: spawn_def
        }

        Logger.debug(
          "Zone #{state.zone_id}/#{state.instance_id}: Spawned creature #{template.name} (#{guid}) from creature_id #{spawn_def.creature_id}"
        )

        {:ok, guid, creature_state}
    end
  end

  # Build AI options from spawn definition
  # Supports:
  #   - patrol_waypoints: [...] - pre-enriched patrol waypoints from entity_spline matching
  #   - patrol_path: "path_name" - named patrol path from patrol_paths.json
  #   - spline_id: 123 - numeric spline ID from client Spline2.tbl data
  #   - auto_spline: true - automatically find nearest spline within threshold
  #   - (default) - automatic spline matching when no explicit patrol is set
  defp build_ai_options(spawn_def, world_id, position, spline_index) do
    # Check for pre-enriched patrol data first (from entity_spline matching during load)
    waypoints = Map.get(spawn_def, :patrol_waypoints)

    cond do
      # Pre-enriched patrol waypoints from entity_spline matching
      is_list(waypoints) and length(waypoints) > 1 ->
        [
          patrol_waypoints: waypoints,
          patrol_speed: Map.get(spawn_def, :patrol_speed, 3.0),
          patrol_mode: Map.get(spawn_def, :patrol_mode, :cyclic)
        ]

      # Check for explicit spline_id (numeric client spline)
      spline_id = Map.get(spawn_def, :spline_id) ->
        case Store.get_spline_as_patrol(spline_id) do
          {:ok, patrol_data} ->
            [
              patrol_waypoints: patrol_data.waypoints,
              patrol_speed: Map.get(spawn_def, :spline_speed, patrol_data.speed),
              patrol_mode: Map.get(spawn_def, :spline_mode, patrol_data.mode)
            ]

          :error ->
            Logger.warning("Spline #{spline_id} not found for creature spawn")
            []
        end

      # Check for named patrol_path
      path_name = Map.get(spawn_def, :patrol_path) ->
        case Store.get_patrol_path(path_name) do
          {:ok, patrol_data} ->
            [
              patrol_waypoints: patrol_data.waypoints,
              patrol_speed: patrol_data.speed,
              patrol_mode: patrol_data.mode
            ]

          :error ->
            Logger.warning("Patrol path '#{path_name}' not found for creature spawn")
            []
        end

      # Auto-match to nearest spline within threshold (default behavior)
      # Only triggers for creatures without explicit spline/patrol assignments
      Map.get(spawn_def, :auto_spline, true) ->
        find_auto_spline(spline_index, world_id, position)

      true ->
        []
    end
  end

  # Find the nearest spline to the spawn position for automatic patrol assignment
  # Uses pre-built spatial index for efficient O(n) lookup instead of O(n*m)
  defp find_auto_spline(spline_index, world_id, position) do
    # 15-unit threshold balances coverage (~11.6% of spawns) with accuracy
    # Tighter than 50 units (which catches incidental proximity)
    case Store.find_nearest_spline_indexed(spline_index, world_id, position, max_distance: 15.0) do
      {:ok, spline_id, distance} ->
        case Store.get_spline_as_patrol(spline_id) do
          {:ok, patrol_data} ->
            Logger.debug(
              "Auto-assigned spline #{spline_id} to creature at #{inspect(position)} (distance: #{Float.round(distance, 1)})"
            )

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

  # Get creature template - first try hardcoded test templates, then BezgelorData
  defp get_creature_template(creature_id, spawn_def) do
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
        # Use display_info from spawn if provided, otherwise from template
        display_info =
          if spawn_def[:display_info] && spawn_def.display_info > 0 do
            spawn_def.display_info
          else
            template.display_info
          end

        {:ok, template, display_info}
    end
  end

  # Build a CreatureTemplate-compatible struct from BezgelorData creature
  defp build_template_from_data(creature_id, creature_data, spawn_def) do
    # Get creature name from text data
    name = get_creature_name(creature_data)

    # Calculate stats based on tier/difficulty (simplified)
    tier_id = Map.get(creature_data, :tier_id, 1)
    difficulty_id = Map.get(creature_data, :difficulty_id, 1)

    # Base level from zone or default (levels scale with tier)
    level = tier_to_level(tier_id)

    # Health scales with tier and difficulty
    max_health = calculate_max_health(tier_id, difficulty_id, level)

    # Damage scales with level
    {damage_min, damage_max} = calculate_damage(level, difficulty_id)

    # Determine AI type from archetype
    ai_type = archetype_to_ai_type(Map.get(creature_data, :archetype_id, 0))

    # Build the template struct
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

    # Use display_info from spawn if provided
    display_info =
      if spawn_def[:display_info] && spawn_def.display_info > 0 do
        spawn_def.display_info
      else
        template.display_info
      end

    {:ok, template, display_info}
  end

  defp get_creature_name(creature_data) do
    name_text_id = Map.get(creature_data, :name_text_id, 0)

    case BezgelorData.get_text(name_text_id) do
      {:ok, text} -> text
      :error -> "Creature #{Map.get(creature_data, :id, 0)}"
    end
  end

  # Convert tier to approximate level (simplified)
  defp tier_to_level(tier_id) do
    case tier_id do
      1 -> Enum.random(1..10)
      2 -> Enum.random(10..20)
      3 -> Enum.random(20..35)
      4 -> Enum.random(35..50)
      _ -> Enum.random(1..50)
    end
  end

  # Calculate max health based on tier, difficulty, and level
  defp calculate_max_health(tier_id, difficulty_id, level) do
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

  # Calculate damage range based on level and difficulty
  defp calculate_damage(level, difficulty_id) do
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

  # Convert archetype to AI type (simplified)
  defp archetype_to_ai_type(archetype_id) do
    # Archetype IDs vary - assume most are aggressive
    # 29 = hostile, 30 = neutral/passive, etc.
    case archetype_id do
      30 -> :passive
      31 -> :defensive
      _ -> :aggressive
    end
  end

  # Apply creature attack damage to a target
  defp apply_creature_attack(creature_entity, template, target_guid, state) do
    # Only attack players for now
    if CreatureDeath.is_player_guid?(target_guid) do
      # Roll damage from template
      damage = CreatureTemplate.roll_damage(template)

      # Apply damage to player in this zone instance
      zone_key = {state.zone_id, state.instance_id}

      try do
        case WorldInstance.update_entity(zone_key, target_guid, fn player_entity ->
               Entity.apply_damage(player_entity, damage)
             end) do
          :ok ->
            # Send damage effect to player
            send_creature_attack_effect(creature_entity.guid, target_guid, damage)

            # Check if player died
            case WorldInstance.get_entity(zone_key, target_guid) do
              {:ok, player_entity} when player_entity.health == 0 ->
                handle_player_death(player_entity, creature_entity.guid)

              _ ->
                :ok
            end

            Logger.debug(
              "Zone #{state.zone_id}/#{state.instance_id}: Creature #{creature_entity.name} dealt #{damage} damage to player #{target_guid}"
            )

          :error ->
            Logger.debug("Failed to apply damage to player #{target_guid} (not in zone)")
        end
      catch
        :exit, _ ->
          Logger.debug("Zone instance not available for creature attack")
      end
    end

    :ok
  end

  defp send_creature_attack_effect(creature_guid, player_guid, damage) do
    effect = %{type: :damage, amount: damage, is_crit: false}
    CombatBroadcaster.send_spell_effect(creature_guid, player_guid, 0, effect, [player_guid])
  end

  defp handle_player_death(player_entity, killer_guid) do
    Logger.info(
      "Player #{player_entity.name} (#{player_entity.guid}) killed by creature #{killer_guid}"
    )

    CombatBroadcaster.broadcast_entity_death(player_entity.guid, killer_guid, [player_entity.guid])

    :ok
  end
end
