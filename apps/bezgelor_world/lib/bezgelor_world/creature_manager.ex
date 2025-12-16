defmodule BezgelorWorld.CreatureManager do
  @moduledoc """
  Manages creature spawns, AI, and state in the world.

  ## Overview

  The CreatureManager is responsible for:
  - Spawning creatures from templates at defined locations
  - Tracking creature health and AI state
  - Processing AI ticks and combat
  - Handling death and respawning

  ## Creature State

  Each spawned creature has:
  - Entity data (GUID, position, health)
  - AI state (combat, targeting, threat)
  - Template reference (for stats and behavior)
  - Spawn point (for respawning/leashing)

  ## AI Processing

  AI is processed on a tick timer. Each tick:
  - Check for aggro (aggressive creatures)
  - Process combat (attack if in range)
  - Handle evade (return to spawn if leashed)
  """

  use GenServer

  require Logger

  alias BezgelorCore.{AI, CreatureTemplate, Entity}
  alias BezgelorWorld.{CombatBroadcaster, CreatureDeath, TickScheduler, WorldManager}
  alias BezgelorData.Store
  alias BezgelorWorld.Zone.Instance, as: ZoneInstance
  alias BezgelorWorld.Zone.InstanceSupervisor

  @type creature_state :: %{
          entity: Entity.t(),
          template: CreatureTemplate.t(),
          ai: AI.t(),
          spawn_position: {float(), float(), float()},
          respawn_timer: reference() | nil
        }

  @type state :: %{
          creatures: %{non_neg_integer() => creature_state()},
          spawn_definitions: [map()]
        }

  # NOTE: Removed @max_creatures_per_tick - the needs_ai_processing? filter
  # already limits to creatures that actually need updates. Batching with
  # Enum.take() was causing most creatures to never get processed.

  # Combat timeout - creatures exit combat after this many ms without activity
  @combat_timeout_ms 30_000

  ## Client API

  @doc "Start the CreatureManager."
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Spawn a creature from a template at a position."
  @spec spawn_creature(non_neg_integer(), {float(), float(), float()}) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def spawn_creature(template_id, position) do
    GenServer.call(__MODULE__, {:spawn_creature, template_id, position})
  end

  @doc "Get a creature by GUID."
  @spec get_creature(non_neg_integer()) :: creature_state() | nil
  def get_creature(guid) do
    GenServer.call(__MODULE__, {:get_creature, guid})
  end

  @doc "Get all creatures."
  @spec list_creatures() :: [creature_state()]
  def list_creatures do
    GenServer.call(__MODULE__, :list_creatures)
  end

  @doc "Get creatures within range of a position."
  @spec get_creatures_in_range({float(), float(), float()}, float()) :: [creature_state()]
  def get_creatures_in_range(position, range) do
    GenServer.call(__MODULE__, {:get_creatures_in_range, position, range})
  end

  @doc "Apply damage to a creature from a player."
  @spec damage_creature(non_neg_integer(), non_neg_integer(), non_neg_integer()) ::
          {:ok, :damaged | :killed, map()} | {:error, term()}
  def damage_creature(creature_guid, attacker_guid, damage) do
    GenServer.call(__MODULE__, {:damage_creature, creature_guid, attacker_guid, damage})
  end

  @doc "Set creature's target (for player targeting creature)."
  @spec creature_enter_combat(non_neg_integer(), non_neg_integer()) :: :ok
  def creature_enter_combat(creature_guid, target_guid) do
    GenServer.cast(__MODULE__, {:creature_enter_combat, creature_guid, target_guid})
  end

  @doc "Check if a creature is alive and targetable."
  @spec creature_targetable?(non_neg_integer()) :: boolean()
  def creature_targetable?(guid) do
    GenServer.call(__MODULE__, {:creature_targetable, guid})
  end

  @doc "Get creature count."
  @spec creature_count() :: non_neg_integer()
  def creature_count do
    GenServer.call(__MODULE__, :creature_count)
  end

  @doc """
  Load all creature spawns for a zone from static data.
  Returns the number of creatures spawned.
  """
  @spec load_zone_spawns(non_neg_integer()) :: {:ok, non_neg_integer()} | {:error, term()}
  def load_zone_spawns(world_id) do
    GenServer.call(__MODULE__, {:load_zone_spawns, world_id}, 30_000)
  end

  @doc """
  Load all creature spawns for a zone asynchronously.
  Use this when the caller doesn't need to wait for completion.
  Results are logged by CreatureManager.
  """
  @spec load_zone_spawns_async(non_neg_integer()) :: :ok
  def load_zone_spawns_async(world_id) do
    GenServer.cast(__MODULE__, {:load_zone_spawns_async, world_id})
  end

  @doc """
  Load spawns for a specific area within a zone.
  """
  @spec load_area_spawns(non_neg_integer(), non_neg_integer()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def load_area_spawns(world_id, area_id) do
    GenServer.call(__MODULE__, {:load_area_spawns, world_id, area_id}, 30_000)
  end

  @doc """
  Clear all spawned creatures. Used for zone reset/shutdown.
  """
  @spec clear_all_creatures() :: :ok
  def clear_all_creatures do
    GenServer.call(__MODULE__, :clear_all_creatures)
  end

  @doc """
  Get spawn definitions loaded for the current zone.
  """
  @spec get_spawn_definitions() :: [map()]
  def get_spawn_definitions do
    GenServer.call(__MODULE__, :get_spawn_definitions)
  end

  @doc """
  Check aggro for a specific creature against nearby players.
  If a player is within aggro range, the creature will enter combat.
  """
  @spec check_aggro_for_creature(non_neg_integer(), [map()]) :: :ok
  def check_aggro_for_creature(creature_guid, nearby_players) do
    GenServer.cast(__MODULE__, {:check_aggro, creature_guid, nearby_players})
  end

  @doc """
  Get the current state of a creature by GUID.
  Returns {:ok, creature_state} if found, :error if not found.
  Useful for testing and debugging.
  """
  @spec get_creature_state(non_neg_integer()) :: {:ok, creature_state()} | :error
  def get_creature_state(creature_guid) do
    GenServer.call(__MODULE__, {:get_creature_state, creature_guid})
  end

  ## Server Callbacks

  @impl true
  def init(_opts) do
    # Build spatial index for efficient spline lookups during spawn
    # This is done once at startup rather than per-creature for performance
    spline_index = Store.build_spline_spatial_index()
    Logger.info("Built spline spatial index for #{map_size(spline_index)} worlds")

    state = %{
      creatures: %{},
      spawn_definitions: [],
      spline_index: spline_index
    }

    # Register with TickScheduler to receive tick notifications
    # This ensures all systems (buffs, AI, etc.) tick in sync
    # In tests, TickScheduler may not be running, so we handle that gracefully
    try do
      TickScheduler.register_listener(self())
      Logger.info("CreatureManager started, registered with TickScheduler")
    catch
      :exit, _ ->
        Logger.info("CreatureManager started (TickScheduler not available)")
    end

    {:ok, state}
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
          creature_id: template_id,
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
        Logger.debug("Spawned creature #{template.name} (#{guid}) at #{inspect(position)}")

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
  def handle_call({:load_zone_spawns, world_id}, _from, state) do
    case Store.get_creature_spawns(world_id) do
      {:ok, zone_data} ->
        {spawned_count, new_state} = spawn_from_definitions(zone_data.creature_spawns, world_id, state)
        Logger.info("Loaded #{spawned_count} creature spawns for world #{world_id}")
        {:reply, {:ok, spawned_count}, new_state}

      :error ->
        Logger.warning("No spawn data found for world #{world_id}")
        {:reply, {:error, :no_spawn_data}, state}
    end
  end

  @impl true
  def handle_call({:load_area_spawns, world_id, area_id}, _from, state) do
    spawns = Store.get_spawns_in_area(world_id, area_id)

    if Enum.empty?(spawns) do
      {:reply, {:error, :no_spawn_data}, state}
    else
      {spawned_count, new_state} = spawn_from_definitions(spawns, world_id, state)
      Logger.info("Loaded #{spawned_count} creature spawns for world #{world_id} area #{area_id}")
      {:reply, {:ok, spawned_count}, new_state}
    end
  end

  @impl true
  def handle_call(:clear_all_creatures, _from, state) do
    # Cancel any pending respawn timers
    for {_guid, %{respawn_timer: timer}} <- state.creatures, timer != nil do
      Process.cancel_timer(timer)
    end

    Logger.info("Cleared #{map_size(state.creatures)} creatures")
    {:reply, :ok, %{state | creatures: %{}, spawn_definitions: []}}
  end

  @impl true
  def handle_call(:get_spawn_definitions, _from, state) do
    {:reply, state.spawn_definitions, state}
  end

  @impl true
  def handle_call({:get_creature_state, creature_guid}, _from, state) do
    case Map.get(state.creatures, creature_guid) do
      nil -> {:reply, :error, state}
      creature_state -> {:reply, {:ok, creature_state}, state}
    end
  end

  @impl true
  def handle_cast({:check_aggro, creature_guid, nearby_players}, state) do
    case Map.get(state.creatures, creature_guid) do
      nil ->
        {:noreply, state}

      creature_state ->
        case check_and_enter_combat(creature_state, nearby_players) do
          {:entered_combat, new_creature_state} ->
            creatures = Map.put(state.creatures, creature_guid, new_creature_state)
            {:noreply, %{state | creatures: creatures}}

          :no_aggro ->
            {:noreply, state}
        end
    end
  end

  @impl true
  def handle_cast({:load_zone_spawns_async, world_id}, state) do
    case Store.get_creature_spawns(world_id) do
      {:ok, zone_data} ->
        {spawned_count, new_state} = spawn_from_definitions(zone_data.creature_spawns, world_id, state)
        Logger.info("Loaded #{spawned_count} creature spawns for world #{world_id}")
        {:noreply, new_state}

      :error ->
        # Tutorial zones may not have spawn data - don't warn for known empty zones
        Logger.debug("No spawn data found for world #{world_id}")
        {:noreply, state}
    end
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
    # Process AI for all creatures on the shared tick
    # This keeps creature AI in sync with buffs and other periodic effects
    state = process_ai_tick(state)
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

          Logger.debug("Respawned creature #{new_entity.name} (#{guid})")
          %{state | creatures: Map.put(state.creatures, guid, new_creature_state)}
      end

    {:noreply, state}
  end

  ## Private Functions

  # Check aggro and enter combat if player detected
  defp check_and_enter_combat(creature_state, nearby_players) do
    template = creature_state.template
    aggro_range = template.aggro_range || 0.0

    # Only aggressive creatures auto-aggro
    if template.ai_type == :aggressive and aggro_range > 0 do
      case AI.check_aggro(creature_state.ai, nearby_players, aggro_range) do
        {:aggro, player_guid} ->
          new_ai = AI.enter_combat(creature_state.ai, player_guid)
          Logger.info("Creature #{creature_state.entity.name} aggro'd on player #{player_guid}")
          {:entered_combat, %{creature_state | ai: new_ai}}

        nil ->
          :no_aggro
      end
    else
      :no_aggro
    end
  end

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
    killer_level = get_killer_level(killer_guid, creature_state.template.level)

    # Delegate to shared death handling logic
    {result, new_creature_state} =
      CreatureDeath.handle_death(creature_state, entity, killer_guid, killer_level)

    {result, new_creature_state, state}
  end

  # Get the level of the killer for loot scaling
  # If the killer is a player, try to get their level from ZoneInstance
  # Falls back to default_level if not found
  defp get_killer_level(killer_guid, default_level) do
    # Check if killer is a player (type bits = 1 in bits 60-63)
    if CreatureDeath.is_player_guid?(killer_guid) do
      # Try to get player entity from zone instance
      case ZoneInstance.get_entity({1, 1}, killer_guid) do
        {:ok, player_entity} ->
          player_entity.level

        _ ->
          default_level
      end
    else
      default_level
    end
  end

  defp process_ai_tick(state) do
    now = System.monotonic_time(:millisecond)

    # Get zones with active players - only process creatures in these zones
    # This is a major optimization: we skip all AI for zones without players
    active_zones = InstanceSupervisor.list_zones_with_players()

    # Filter to only creatures in active zones (or in combat regardless of zone)
    # Then apply the existing needs_ai_processing? filter
    creatures_needing_update =
      state.creatures
      |> Enum.filter(fn {_guid, creature_state} ->
        in_active_zone_or_combat?(creature_state, active_zones)
      end)
      |> Enum.filter(fn {_guid, creature_state} ->
        needs_ai_processing?(creature_state, now)
      end)


    # Process the filtered creatures
    creatures =
      Enum.reduce(creatures_needing_update, state.creatures, fn {guid, creature_state}, creatures ->
        case process_creature_ai(creature_state, now) do
          {:no_change, _} ->
            creatures

          {:updated, new_creature_state} ->
            Map.put(creatures, guid, new_creature_state)
        end
      end)

    %{state | creatures: creatures}
  end

  # Check if creature is in an active zone (has players) or is in combat
  # Creatures in combat continue processing even if players leave the zone
  defp in_active_zone_or_combat?(creature_state, active_zones) do
    world_id = Map.get(creature_state, :world_id)
    ai = creature_state.ai

    # Always process creatures in combat or evading
    ai.state == :combat or ai.state == :evade or
      # Process creatures in zones with players
      MapSet.member?(active_zones, world_id)
  end

  # Determine if a creature needs AI processing this tick
  defp needs_ai_processing?(%{ai: ai, template: template}, now) do
    # Process if:
    # - In combat (needs to attack/check threat)
    # - Evading (needs to return to spawn)
    # - Has targets in threat table (should be in combat)
    # - Idle with patrol enabled (always needs processing to start patrol)
    # - Idle aggressive creature (needs aggro checking)
    # - Idle and can wander (for ambient movement)
    # - Currently wandering (need to check completion)
    # - Currently patrolling (need to check segment completion)
    ai.state == :combat or
      ai.state == :evade or
      ai.state == :wandering or
      ai.state == :patrol or
      map_size(ai.threat_table) > 0 or
      (ai.state == :idle and ai.patrol_enabled) or
      (ai.state == :idle and template.ai_type == :aggressive and (template.aggro_range || 0.0) > 0) or
      (ai.state == :idle and AI.can_wander?(ai, now))
  end

  defp process_creature_ai(%{ai: ai, template: template, entity: entity} = creature_state, now) do
    # For idle aggressive creatures, check for nearby players to aggro
    if ai.state == :idle and template.ai_type == :aggressive and (template.aggro_range || 0.0) > 0 do
      case check_aggro_nearby_players(creature_state) do
        {:aggro, player_guid} ->
          new_ai = AI.enter_combat(ai, player_guid)
          Logger.debug("Creature #{entity.name} auto-aggro'd player #{player_guid}")
          {:updated, %{creature_state | ai: new_ai}}

        nil ->
          # No aggro, continue with normal idle behavior
          process_creature_ai_tick(creature_state, ai, template, entity, now)
      end
    else
      process_creature_ai_tick(creature_state, ai, template, entity, now)
    end
  end

  # Helper to get nearby players and check aggro
  defp check_aggro_nearby_players(creature_state) do
    world_id = Map.get(creature_state, :world_id)
    creature_pos = creature_state.entity.position
    aggro_range = creature_state.template.aggro_range || 15.0

    # Get nearby players from zone instance
    nearby_players = get_nearby_players(world_id, creature_pos, aggro_range)

    # Use AI.check_aggro to find closest player in range
    AI.check_aggro(creature_state.ai, nearby_players, aggro_range)
  end

  # Get nearby player entities from zone instance
  defp get_nearby_players(world_id, position, range) do
    zone_key = {world_id, 1}  # Assuming instance 1

    case ZoneInstance.entities_in_range(zone_key, position, range) do
      {:ok, entities} ->
        entities
        |> Enum.filter(fn e -> e.type == :player end)
        |> Enum.map(fn e -> %{guid: e.guid, position: e.position} end)

      _ ->
        []
    end
  end

  defp process_creature_ai_tick(creature_state, ai, template, entity, now) do
    # Check for combat timeout - exit combat if no activity for too long
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
      attack_speed: template.attack_speed,
      position: entity.position
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

        # Apply damage to target (if player)
        apply_creature_attack(entity, template, target_guid)

        {:updated, %{creature_state | ai: new_ai}}

      {:move_to, _position} ->
        # Movement would be handled here
        {:no_change, creature_state}

      {:start_wander, new_ai} ->
        # Creature is starting to wander - broadcast movement to players in zone
        world_id = Map.get(creature_state, :world_id)
        broadcast_creature_movement(entity.guid, new_ai.movement_path, new_ai.wander_speed, world_id)

        # Update entity position to path end (client will animate the movement)
        end_position = List.last(new_ai.movement_path) || entity.position

        new_entity = %{entity | position: end_position}
        {:updated, %{creature_state | ai: new_ai, entity: new_entity}}

      {:wander_complete, new_ai} ->
        # Wandering finished, creature is now idle
        {:updated, %{creature_state | ai: new_ai}}

      {:start_patrol, new_ai} ->
        # Creature is starting a patrol segment - broadcast movement to players in zone
        world_id = Map.get(creature_state, :world_id)
        broadcast_creature_movement(entity.guid, new_ai.movement_path, new_ai.patrol_speed, world_id)

        # Update entity position to path end (client will animate the movement)
        end_position = List.last(new_ai.movement_path) || entity.position

        new_entity = %{entity | position: end_position}
        {:updated, %{creature_state | ai: new_ai, entity: new_entity}}

      {:patrol_segment_complete, new_ai} ->
        # Patrol segment finished, creature may be pausing or continuing
        {:updated, %{creature_state | ai: new_ai}}
    end
  end

  defp faction_to_int(:hostile), do: 0
  defp faction_to_int(:neutral), do: 1
  defp faction_to_int(:friendly), do: 2
  defp faction_to_int(_), do: 0

  # Spawn creatures from static data definitions
  defp spawn_from_definitions(spawn_defs, world_id, state) do
    # Store definitions for reference
    state = %{state | spawn_definitions: state.spawn_definitions ++ spawn_defs}

    # Extract spline index for efficient lookups
    spline_index = state.spline_index

    # Spawn each creature
    {spawned_count, creatures} =
      Enum.reduce(spawn_defs, {0, state.creatures}, fn spawn_def, {count, creatures} ->
        case spawn_creature_from_def(spawn_def, world_id, spline_index) do
          {:ok, guid, creature_state} ->
            {count + 1, Map.put(creatures, guid, creature_state)}

          {:error, reason} ->
            Logger.warning(
              "Failed to spawn creature #{spawn_def.creature_id} at #{inspect(spawn_def.position)}: #{inspect(reason)}"
            )

            {count, creatures}
        end
      end)

    {spawned_count, %{state | creatures: creatures}}
  end

  # Spawn a single creature from a spawn definition
  defp spawn_creature_from_def(spawn_def, world_id, spline_index) do
    creature_id = spawn_def.creature_id
    [x, y, z] = spawn_def.position
    position = {x, y, z}

    case get_creature_template(creature_id, spawn_def) do
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

        # Build AI options, including patrol path if specified
        # Pass world_id, position, and spline_index for efficient automatic spline matching
        ai_opts = build_ai_options(spawn_def, world_id, position, spline_index)
        ai = AI.new(position, ai_opts)

        # Don't start movement on spawn - wait for players to enter zone
        # Movement will be triggered by AI tick once zone has players
        # This keeps server/client timing in sync

        creature_state = %{
          entity: entity,
          template: template,
          ai: ai,
          spawn_position: position,
          respawn_timer: nil,
          spawn_def: spawn_def,
          world_id: world_id
        }

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
        case BezgelorData.Store.get_spline_as_patrol(spline_id) do
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
        case BezgelorData.Store.get_patrol_path(path_name) do
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
              "Auto-assigned spline #{spline_id} (#{length(patrol_data.waypoints)} waypoints) to creature at #{inspect(position)} (distance: #{Float.round(distance, 1)})"
            )

            [
              patrol_waypoints: patrol_data.waypoints,
              patrol_speed: patrol_data.speed,
              patrol_mode: patrol_data.mode
            ]

          :error ->
            Logger.warning("Spline #{spline_id} found but get_spline_as_patrol failed")
            []
        end

      :none ->
        []
    end
  end

  # Get creature template - first try hardcoded test templates, then BezgelorData
  # Returns {:ok, template, display_info, outfit_info} or {:error, reason}
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

        # Get outfit_info from spawn if provided (hardcoded templates don't have outfit_info)
        outfit_info = spawn_def[:outfit_info] || 0

        {:ok, template, display_info, outfit_info}
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

    # Use display_info from spawn if provided, otherwise from creature data
    display_info =
      if spawn_def[:display_info] && spawn_def.display_info > 0 do
        spawn_def.display_info
      else
        template.display_info
      end

    # Get outfit_info from spawn if provided, otherwise from creature data
    # outfit_group_id controls the creature's clothing/appearance
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
  defp apply_creature_attack(creature_entity, template, target_guid) do
    # Only attack players for now
    if CreatureDeath.is_player_guid?(target_guid) do
      # Roll base damage from template
      base_damage = CreatureTemplate.roll_damage(template)

      # Get target's defensive stats and apply mitigation
      final_damage = apply_damage_mitigation(target_guid, base_damage)

      # Try to apply damage to player in zone instance
      # For simplicity, assume zone 1 instance 1 (would need player tracking in real impl)
      # Use try/catch to handle zone instance not existing (e.g., during tests)
      try do
        case ZoneInstance.update_entity({1, 1}, target_guid, fn player_entity ->
               Entity.apply_damage(player_entity, final_damage)
             end) do
          :ok ->
            # Send damage effect to player
            send_creature_attack_effect(creature_entity.guid, target_guid, final_damage)

            # Check if player died
            case ZoneInstance.get_entity({1, 1}, target_guid) do
              {:ok, player_entity} when player_entity.health == 0 ->
                handle_player_death(player_entity, creature_entity.guid)

              _ ->
                :ok
            end

            Logger.debug(
              "Creature #{creature_entity.name} dealt #{final_damage} damage (base: #{base_damage}) to player #{target_guid}"
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

  # Apply damage mitigation based on player's defensive stats
  defp apply_damage_mitigation(player_guid, base_damage) do
    alias BezgelorCore.CharacterStats

    target_stats = get_target_defensive_stats(player_guid)
    armor = Map.get(target_stats, :armor, 0.0)

    # Armor reduces damage (capped at 75% mitigation)
    mitigation = min(armor, 0.75)
    final_damage = round(base_damage * (1 - mitigation))
    max(final_damage, 1)  # Always deal at least 1 damage
  end

  # Get defensive stats for a player target
  defp get_target_defensive_stats(player_guid) do
    alias BezgelorCore.CharacterStats

    # Try to get session data for the player
    case WorldManager.get_session_by_entity_guid(player_guid) do
      nil ->
        %{armor: 0.0}

      session ->
        character = session[:character]

        if character do
          CharacterStats.compute_combat_stats(%{
            level: character.level || 1,
            class: character.class || 1,
            race: character.race || 0
          })
        else
          %{armor: 0.0}
        end
    end
  end

  defp send_creature_attack_effect(creature_guid, player_guid, damage) do
    # Send damage effect packet to player
    effect = %{type: :damage, amount: damage, is_crit: false}

    # Use CombatBroadcaster to send spell effect
    # Creature attacks use spell_id 0 (auto-attack)
    CombatBroadcaster.send_spell_effect(creature_guid, player_guid, 0, effect, [player_guid])
  end

  defp handle_player_death(player_entity, killer_guid) do
    Logger.info(
      "Player #{player_entity.name} (#{player_entity.guid}) killed by creature #{killer_guid}"
    )

    # Broadcast death to the player
    CombatBroadcaster.broadcast_entity_death(player_entity.guid, killer_guid, [player_entity.guid])

    :ok
  end

  # Broadcast creature movement to players in the same zone
  defp broadcast_creature_movement(creature_guid, path, speed, world_id) when length(path) > 1 do
    alias BezgelorProtocol.Packets.World.ServerEntityCommand
    alias BezgelorProtocol.PacketWriter
    alias BezgelorWorld.Zone.Instance, as: ZoneInstance

    # Build movement commands using map format
    # Set move state (0x02 = Move flag per NexusForever StateFlags)
    state_command = %{type: :set_state, state: 0x02}

    # Reset move direction to defaults
    move_defaults = %{type: :set_move_defaults, blend: false}

    # SetRotationDefaults makes entity auto-face along path movement
    # (delegates to position command's GetRotation when path/spline/keys active)
    rotation_defaults = %{type: :set_rotation_defaults, blend: false}

    # Path following command
    path_command = %{
      type: :set_position_path,
      positions: path,
      speed: speed,
      spline_type: :linear,
      spline_mode: :one_shot,
      offset: 0,
      blend: true
    }

    packet = %ServerEntityCommand{
      guid: creature_guid,
      time: System.monotonic_time(:millisecond) |> rem(0xFFFFFFFF),
      time_reset: false,
      server_controlled: true,
      commands: [state_command, move_defaults, rotation_defaults, path_command]
    }

    # Serialize the packet
    writer = PacketWriter.new()
    {:ok, writer} = ServerEntityCommand.write(packet, writer)
    packet_data = PacketWriter.to_binary(writer)

    # Broadcast to players in the same zone (instance_id = 1 for now)
    # Zone.Instance.broadcast routes via WorldManager's zone_index
    ZoneInstance.broadcast({world_id, 1}, {:server_entity_command, packet_data})

    Logger.debug("Broadcast movement for creature #{creature_guid} in zone #{world_id}, path length: #{length(path)}")
  end

  defp broadcast_creature_movement(_creature_guid, _path, _speed, _world_id), do: :ok
end
