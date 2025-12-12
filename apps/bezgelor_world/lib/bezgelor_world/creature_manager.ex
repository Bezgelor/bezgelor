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

  alias BezgelorCore.{AI, CreatureTemplate, Entity, Loot}
  alias BezgelorData.Store
  alias BezgelorWorld.{CombatBroadcaster, WorldManager}
  alias BezgelorWorld.Zone.Instance, as: ZoneInstance

  import Bitwise

  @type creature_state :: %{
          entity: Entity.t(),
          template: CreatureTemplate.t(),
          ai: AI.t(),
          spawn_position: {float(), float(), float()},
          respawn_timer: reference() | nil
        }

  @type state :: %{
          creatures: %{non_neg_integer() => creature_state()},
          spawn_definitions: [map()],
          ai_tick_interval: non_neg_integer()
        }

  # AI tick interval in milliseconds
  @default_ai_tick_interval 1000

  # Maximum creatures to process per tick (for batching)
  @max_creatures_per_tick 100

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

  ## Server Callbacks

  @impl true
  def init(opts) do
    ai_tick_interval = Keyword.get(opts, :ai_tick_interval, @default_ai_tick_interval)

    state = %{
      creatures: %{},
      spawn_definitions: [],
      ai_tick_interval: ai_tick_interval
    }

    # Start AI tick timer
    if ai_tick_interval > 0 do
      Process.send_after(self(), :ai_tick, ai_tick_interval)
    end

    Logger.info("CreatureManager started")
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
        {spawned_count, new_state} = spawn_from_definitions(zone_data.creature_spawns, state)
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
      {spawned_count, new_state} = spawn_from_definitions(spawns, state)
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
  def handle_info(:ai_tick, state) do
    # Process AI for all creatures
    state = process_ai_tick(state)

    # Schedule next tick
    Process.send_after(self(), :ai_tick, state.ai_tick_interval)

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
    template = creature_state.template

    # Set AI to dead
    ai = AI.set_dead(creature_state.ai)

    # Generate loot
    loot_drops =
      if template.loot_table_id do
        Loot.roll(template.loot_table_id)
      else
        []
      end

    # Calculate XP reward
    xp_reward = template.xp_reward

    # Start respawn timer
    respawn_timer =
      if template.respawn_time > 0 do
        Process.send_after(self(), {:respawn_creature, entity.guid}, template.respawn_time)
      else
        nil
      end

    new_creature_state = %{
      creature_state
      | entity: entity,
        ai: ai,
        respawn_timer: respawn_timer
    }

    result_info = %{
      creature_guid: entity.guid,
      xp_reward: xp_reward,
      loot_drops: loot_drops,
      gold: Loot.gold_from_drops(loot_drops),
      items: Loot.items_from_drops(loot_drops),
      killer_guid: killer_guid,
      reputation_rewards: template.reputation_rewards || []
    }

    Logger.debug("Creature #{entity.name} (#{entity.guid}) killed by #{killer_guid}")

    {{:ok, :killed, result_info}, new_creature_state, state}
  end

  defp process_ai_tick(state) do
    now = System.monotonic_time(:millisecond)

    # Filter to only creatures that need AI processing (in combat, evading, or have threat)
    # This optimization skips idle creatures with no targets
    creatures_needing_update =
      state.creatures
      |> Enum.filter(fn {_guid, creature_state} ->
        needs_ai_processing?(creature_state, now)
      end)
      |> Enum.take(@max_creatures_per_tick)

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

  # Determine if a creature needs AI processing this tick
  defp needs_ai_processing?(%{ai: ai}, _now) do
    # Process if:
    # - In combat (needs to attack/check threat)
    # - Evading (needs to return to spawn)
    # - Has targets in threat table (should be in combat)
    ai.state == :combat or
      ai.state == :evade or
      map_size(ai.threat_table) > 0
  end

  defp process_creature_ai(%{ai: ai, template: template, entity: entity} = creature_state, now) do
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

        # Apply damage to target (if player)
        apply_creature_attack(entity, template, target_guid)

        {:updated, %{creature_state | ai: new_ai}}

      {:move_to, _position} ->
        # Movement would be handled here
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
        case spawn_creature_from_def(spawn_def) do
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
  defp spawn_creature_from_def(spawn_def) do
    creature_id = spawn_def.creature_id
    [x, y, z] = spawn_def.position
    position = {x, y, z}

    case CreatureTemplate.get(creature_id) do
      nil ->
        {:error, :template_not_found}

      template ->
        guid = WorldManager.generate_guid(:creature)

        # Use display_info from spawn if provided, otherwise from template
        display_info =
          if spawn_def[:display_info] && spawn_def.display_info > 0 do
            spawn_def.display_info
          else
            template.display_info
          end

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

        ai = AI.new(position)

        creature_state = %{
          entity: entity,
          template: template,
          ai: ai,
          spawn_position: position,
          respawn_timer: nil,
          spawn_def: spawn_def
        }

        Logger.debug(
          "Spawned creature #{template.name} (#{guid}) at #{inspect(position)} from spawn def #{spawn_def.id}"
        )

        {:ok, guid, creature_state}
    end
  end

  # Apply creature attack damage to a target
  defp apply_creature_attack(creature_entity, template, target_guid) do
    # Only attack players for now
    if is_player_guid?(target_guid) do
      # Roll damage from template
      damage = CreatureTemplate.roll_damage(template)

      # Try to apply damage to player in zone instance
      # For simplicity, assume zone 1 instance 1 (would need player tracking in real impl)
      # Use try/catch to handle zone instance not existing (e.g., during tests)
      try do
        case ZoneInstance.update_entity({1, 1}, target_guid, fn player_entity ->
               Entity.apply_damage(player_entity, damage)
             end) do
          :ok ->
            # Send damage effect to player
            send_creature_attack_effect(creature_entity.guid, target_guid, damage)

            # Check if player died
            case ZoneInstance.get_entity({1, 1}, target_guid) do
              {:ok, player_entity} when player_entity.health == 0 ->
                handle_player_death(player_entity, creature_entity.guid)

              _ ->
                :ok
            end

            Logger.debug(
              "Creature #{creature_entity.name} dealt #{damage} damage to player #{target_guid}"
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

  # Check if GUID is a player (type bits = 1 in bits 60-63)
  defp is_player_guid?(guid) when is_integer(guid) and guid > 0 do
    type_bits = bsr(guid, 60) &&& 0xF
    type_bits == 1
  end

  defp is_player_guid?(_), do: false
end
