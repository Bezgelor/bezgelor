defmodule BezgelorWorld.EventManager do
  @moduledoc """
  Manages public events and world bosses for a zone instance.

  ## Overview

  The EventManager tracks:
  - Active event instances with objectives
  - Player participation and contributions
  - Event phases and timers
  - World boss spawns and phases
  - Territory control states

  ## State Structure

      %{
        zone_id: integer,
        instance_id: integer,
        events: %{instance_id => EventState.t()},
        world_bosses: %{boss_id => WorldBossState.t()},
        participants: %{character_id => ParticipantState.t()},
        next_instance_id: integer
      }

  ## Event Lifecycle

  1. start_event/2 - Create event instance
  2. Players join via proximity or explicit join
  3. track_contribution/4 - Record kills, collections, etc.
  4. advance_phase/2 - When objectives complete
  5. complete_event/2 - Award rewards
  """

  use GenServer

  alias BezgelorDb.PublicEvents

  require Logger

  @type event_state :: %{
          event_id: non_neg_integer(),
          event_def: map(),
          phase: non_neg_integer(),
          objectives: [objective_state()],
          started_at: DateTime.t(),
          time_limit_timer: reference() | nil,
          participants: MapSet.t(non_neg_integer()),
          wave_state: wave_state() | nil,
          territory_state: territory_state() | nil
        }

  @type wave_state :: %{
          current_wave: non_neg_integer(),
          total_waves: non_neg_integer(),
          enemies_spawned: non_neg_integer(),
          enemies_killed: non_neg_integer(),
          wave_timer: reference() | nil
        }

  @type territory_state :: %{
          territories: [territory_point()],
          capture_tick_timer: reference() | nil
        }

  @type territory_point :: %{
          index: non_neg_integer(),
          name: String.t(),
          capture_progress: integer(),
          players_in_zone: MapSet.t(non_neg_integer()),
          captured: boolean()
        }

  @type objective_state :: %{
          index: non_neg_integer(),
          type: atom(),
          target: non_neg_integer(),
          current: non_neg_integer()
        }

  @type world_boss_state :: %{
          boss_id: non_neg_integer(),
          boss_def: map(),
          creature_id: non_neg_integer() | nil,
          phase: non_neg_integer(),
          health_current: non_neg_integer(),
          health_max: non_neg_integer(),
          engaged_at: DateTime.t() | nil,
          participants: MapSet.t(non_neg_integer()),
          contributions: %{non_neg_integer() => non_neg_integer()}
        }

  @type participant_state :: %{
          character_id: non_neg_integer(),
          contribution: non_neg_integer(),
          damage_dealt: non_neg_integer(),
          joined_at: DateTime.t()
        }

  @type state :: %{
          zone_id: non_neg_integer(),
          instance_id: non_neg_integer(),
          events: %{non_neg_integer() => event_state()},
          world_bosses: %{non_neg_integer() => world_boss_state()},
          participants: %{non_neg_integer() => participant_state()},
          next_instance_id: non_neg_integer()
        }

  ## Client API

  @doc "Start the EventManager for a zone instance."
  def start_link(opts) do
    zone_id = Keyword.fetch!(opts, :zone_id)
    instance_id = Keyword.fetch!(opts, :instance_id)
    name = via_tuple(zone_id, instance_id)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Get the registered name for an EventManager."
  def via_tuple(zone_id, instance_id) do
    {:via, Registry, {BezgelorWorld.EventRegistry, {zone_id, instance_id}}}
  end

  @doc "Start a new event instance."
  @spec start_event(pid() | tuple(), non_neg_integer()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def start_event(manager, event_id) do
    GenServer.call(manager, {:start_event, event_id})
  end

  @doc "Stop an event instance."
  @spec stop_event(pid() | tuple(), non_neg_integer()) :: :ok | {:error, term()}
  def stop_event(manager, instance_id) do
    GenServer.call(manager, {:stop_event, instance_id})
  end

  @doc "Get active events in this zone."
  @spec list_events(pid() | tuple()) :: [map()]
  def list_events(manager) do
    GenServer.call(manager, :list_events)
  end

  @doc "Get specific event state."
  @spec get_event(pid() | tuple(), non_neg_integer()) :: {:ok, event_state()} | {:error, :not_found}
  def get_event(manager, instance_id) do
    GenServer.call(manager, {:get_event, instance_id})
  end

  @doc "Player joins an event."
  @spec join_event(pid() | tuple(), non_neg_integer(), non_neg_integer()) :: :ok | {:error, term()}
  def join_event(manager, instance_id, character_id) do
    GenServer.call(manager, {:join_event, instance_id, character_id})
  end

  @doc "Player leaves an event."
  @spec leave_event(pid() | tuple(), non_neg_integer(), non_neg_integer()) :: :ok
  def leave_event(manager, instance_id, character_id) do
    GenServer.call(manager, {:leave_event, instance_id, character_id})
  end

  @doc "Track contribution to an event objective."
  @spec track_contribution(pid() | tuple(), non_neg_integer(), non_neg_integer(), non_neg_integer()) ::
          {:ok, map()} | {:error, term()}
  def track_contribution(manager, instance_id, character_id, amount) do
    GenServer.call(manager, {:track_contribution, instance_id, character_id, amount})
  end

  @doc "Update objective progress."
  @spec update_objective(pid() | tuple(), non_neg_integer(), non_neg_integer(), non_neg_integer()) ::
          {:ok, map()} | {:error, term()}
  def update_objective(manager, instance_id, objective_index, amount) do
    GenServer.call(manager, {:update_objective, instance_id, objective_index, amount})
  end

  @doc "Record a kill for kill-type objectives."
  @spec record_kill(pid() | tuple(), non_neg_integer(), non_neg_integer(), non_neg_integer()) ::
          {:ok, map()} | {:error, term()}
  def record_kill(manager, instance_id, character_id, creature_id) do
    GenServer.call(manager, {:record_kill, instance_id, character_id, creature_id})
  end

  @doc "Record a collection for collect-type objectives."
  @spec record_collection(pid() | tuple(), non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()) ::
          {:ok, map()} | {:error, term()}
  def record_collection(manager, instance_id, character_id, item_id, amount) do
    GenServer.call(manager, {:record_collection, instance_id, character_id, item_id, amount})
  end

  @doc "Record an interaction for interact-type objectives."
  @spec record_interaction(pid() | tuple(), non_neg_integer(), non_neg_integer(), non_neg_integer()) ::
          {:ok, map()} | {:error, term()}
  def record_interaction(manager, instance_id, character_id, object_id) do
    GenServer.call(manager, {:record_interaction, instance_id, character_id, object_id})
  end

  @doc "Record damage dealt for damage-type objectives."
  @spec record_damage(pid() | tuple(), non_neg_integer(), non_neg_integer(), non_neg_integer()) ::
          {:ok, map()} | {:error, term()}
  def record_damage(manager, instance_id, character_id, damage) do
    GenServer.call(manager, {:record_damage, instance_id, character_id, damage})
  end

  @doc "Get objectives for an event."
  @spec get_objectives(pid() | tuple(), non_neg_integer()) :: {:ok, [map()]} | {:error, term()}
  def get_objectives(manager, instance_id) do
    GenServer.call(manager, {:get_objectives, instance_id})
  end

  # World Boss Functions

  @doc "Spawn a world boss."
  @spec spawn_world_boss(pid() | tuple(), non_neg_integer(), map()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def spawn_world_boss(manager, boss_id, position) do
    GenServer.call(manager, {:spawn_world_boss, boss_id, position})
  end

  @doc "Record damage to world boss."
  @spec damage_world_boss(pid() | tuple(), non_neg_integer(), non_neg_integer(), non_neg_integer()) ::
          {:ok, map()} | {:error, term()}
  def damage_world_boss(manager, boss_id, character_id, damage) do
    GenServer.call(manager, {:damage_world_boss, boss_id, character_id, damage})
  end

  @doc "Get world boss state."
  @spec get_world_boss(pid() | tuple(), non_neg_integer()) ::
          {:ok, world_boss_state()} | {:error, :not_found}
  def get_world_boss(manager, boss_id) do
    GenServer.call(manager, {:get_world_boss, boss_id})
  end

  @doc "List active world bosses in zone."
  @spec list_world_bosses(pid() | tuple()) :: [map()]
  def list_world_bosses(manager) do
    GenServer.call(manager, :list_world_bosses)
  end

  # Wave System Functions

  @doc "Start a wave for an invasion event."
  @spec start_wave(pid() | tuple(), non_neg_integer(), non_neg_integer()) ::
          {:ok, map()} | {:error, term()}
  def start_wave(manager, instance_id, wave_number) do
    GenServer.call(manager, {:start_wave, instance_id, wave_number})
  end

  @doc "Report wave enemies killed."
  @spec wave_enemy_killed(pid() | tuple(), non_neg_integer(), non_neg_integer(), non_neg_integer()) ::
          {:ok, map()} | {:error, term()}
  def wave_enemy_killed(manager, instance_id, character_id, creature_id) do
    GenServer.call(manager, {:wave_enemy_killed, instance_id, character_id, creature_id})
  end

  @doc "Get current wave state for an event."
  @spec get_wave_state(pid() | tuple(), non_neg_integer()) ::
          {:ok, map()} | {:error, term()}
  def get_wave_state(manager, instance_id) do
    GenServer.call(manager, {:get_wave_state, instance_id})
  end

  # Territory Control Functions

  @doc "Enter a territory capture point."
  @spec enter_territory(pid() | tuple(), non_neg_integer(), non_neg_integer(), non_neg_integer()) ::
          {:ok, map()} | {:error, term()}
  def enter_territory(manager, instance_id, territory_index, character_id) do
    GenServer.call(manager, {:enter_territory, instance_id, territory_index, character_id})
  end

  @doc "Leave a territory capture point."
  @spec leave_territory(pid() | tuple(), non_neg_integer(), non_neg_integer(), non_neg_integer()) ::
          :ok | {:error, term()}
  def leave_territory(manager, instance_id, territory_index, character_id) do
    GenServer.call(manager, {:leave_territory, instance_id, territory_index, character_id})
  end

  @doc "Get territory state for an event."
  @spec get_territory_state(pid() | tuple(), non_neg_integer()) ::
          {:ok, map()} | {:error, term()}
  def get_territory_state(manager, instance_id) do
    GenServer.call(manager, {:get_territory_state, instance_id})
  end

  ## Server Callbacks

  @impl true
  def init(opts) do
    zone_id = Keyword.fetch!(opts, :zone_id)
    instance_id = Keyword.fetch!(opts, :instance_id)

    state = %{
      zone_id: zone_id,
      instance_id: instance_id,
      events: %{},
      world_bosses: %{},
      participants: %{},
      next_instance_id: 1
    }

    Logger.info("EventManager started for zone #{zone_id}:#{instance_id}")
    {:ok, state}
  end

  @impl true
  def handle_call({:start_event, event_id}, _from, state) do
    case BezgelorData.get_public_event(event_id) do
      {:ok, event_def} ->
        instance_id = state.next_instance_id

        # Create DB record
        case PublicEvents.create_event_instance(event_id, state.zone_id, instance_id) do
          {:ok, db_instance} ->
            # Start the event with a default duration
            duration_ms = event_def["time_limit_ms"] || 3_600_000
            PublicEvents.start_event(db_instance.id, duration_ms)
            event_state = create_event_state(event_id, event_def)

            # Start time limit timer if applicable
            event_state = maybe_start_time_limit(event_state, instance_id)

            events = Map.put(state.events, instance_id, event_state)
            state = %{state | events: events, next_instance_id: instance_id + 1}

            Logger.info("Started event #{event_id} as instance #{instance_id} in zone #{state.zone_id}")
            {:reply, {:ok, instance_id}, state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      :error ->
        {:reply, {:error, :event_not_found}, state}
    end
  end

  @impl true
  def handle_call({:stop_event, instance_id}, _from, state) do
    case Map.get(state.events, instance_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      event_state ->
        # Cancel any timers
        if event_state.time_limit_timer do
          Process.cancel_timer(event_state.time_limit_timer)
        end

        # Update DB
        PublicEvents.fail_event(instance_id)

        events = Map.delete(state.events, instance_id)
        Logger.info("Stopped event instance #{instance_id}")
        {:reply, :ok, %{state | events: events}}
    end
  end

  @impl true
  def handle_call(:list_events, _from, state) do
    events =
      Enum.map(state.events, fn {instance_id, event_state} ->
        %{
          instance_id: instance_id,
          event_id: event_state.event_id,
          event_type: event_state.event_def["type"],
          phase: event_state.phase,
          time_remaining_ms: calculate_time_remaining(event_state),
          participant_count: MapSet.size(event_state.participants)
        }
      end)

    {:reply, events, state}
  end

  @impl true
  def handle_call({:get_event, instance_id}, _from, state) do
    case Map.get(state.events, instance_id) do
      nil -> {:reply, {:error, :not_found}, state}
      event_state -> {:reply, {:ok, event_state}, state}
    end
  end

  @impl true
  def handle_call({:join_event, instance_id, character_id}, _from, state) do
    case Map.get(state.events, instance_id) do
      nil ->
        {:reply, {:error, :event_not_found}, state}

      event_state ->
        # Add to event participants
        participants = MapSet.put(event_state.participants, character_id)
        event_state = %{event_state | participants: participants}
        events = Map.put(state.events, instance_id, event_state)

        # Track in participant state
        participant =
          Map.get(state.participants, character_id, %{
            character_id: character_id,
            contribution: 0,
            damage_dealt: 0,
            joined_at: DateTime.utc_now()
          })

        participants_map = Map.put(state.participants, character_id, participant)

        # Record in DB
        PublicEvents.join_event(instance_id, character_id)

        Logger.debug("Character #{character_id} joined event #{instance_id}")
        {:reply, :ok, %{state | events: events, participants: participants_map}}
    end
  end

  @impl true
  def handle_call({:leave_event, instance_id, character_id}, _from, state) do
    case Map.get(state.events, instance_id) do
      nil ->
        {:reply, :ok, state}

      event_state ->
        participants = MapSet.delete(event_state.participants, character_id)
        event_state = %{event_state | participants: participants}
        events = Map.put(state.events, instance_id, event_state)

        Logger.debug("Character #{character_id} left event #{instance_id}")
        {:reply, :ok, %{state | events: events}}
    end
  end

  @impl true
  def handle_call({:track_contribution, instance_id, character_id, amount}, _from, state) do
    case Map.get(state.events, instance_id) do
      nil ->
        {:reply, {:error, :event_not_found}, state}

      _event_state ->
        # Update participant contribution
        participant =
          Map.get(state.participants, character_id, %{
            character_id: character_id,
            contribution: 0,
            damage_dealt: 0,
            joined_at: DateTime.utc_now()
          })

        participant = %{participant | contribution: participant.contribution + amount}
        participants_map = Map.put(state.participants, character_id, participant)

        # Update DB
        PublicEvents.add_contribution(instance_id, character_id, amount)

        {:reply, {:ok, participant}, %{state | participants: participants_map}}
    end
  end

  @impl true
  def handle_call({:update_objective, instance_id, objective_index, amount}, _from, state) do
    case Map.get(state.events, instance_id) do
      nil ->
        {:reply, {:error, :event_not_found}, state}

      event_state ->
        objectives =
          Enum.map(event_state.objectives, fn obj ->
            if obj.index == objective_index do
              new_current = min(obj.current + amount, obj.target)
              %{obj | current: new_current}
            else
              obj
            end
          end)

        event_state = %{event_state | objectives: objectives}
        events = Map.put(state.events, instance_id, event_state)
        state = %{state | events: events}

        # Check if phase objectives are complete
        state = maybe_advance_phase(state, instance_id)

        objective = Enum.find(objectives, &(&1.index == objective_index))
        {:reply, {:ok, objective}, state}
    end
  end

  @impl true
  def handle_call({:record_kill, instance_id, character_id, creature_id}, _from, state) do
    case Map.get(state.events, instance_id) do
      nil ->
        {:reply, {:error, :event_not_found}, state}

      event_state ->
        # Find kill objectives that match this creature
        {objectives, updated} =
          update_matching_objectives(event_state.objectives, :kill, creature_id)

        if updated do
          event_state = %{event_state | objectives: objectives}
          events = Map.put(state.events, instance_id, event_state)

          # Track contribution (kills give 10 points)
          state = track_participant_contribution(state, character_id, 10)

          state = %{state | events: events}
          state = maybe_advance_phase(state, instance_id)

          {:reply, {:ok, %{updated: true, objectives: objectives}}, state}
        else
          {:reply, {:ok, %{updated: false}}, state}
        end
    end
  end

  @impl true
  def handle_call({:record_collection, instance_id, character_id, item_id, amount}, _from, state) do
    case Map.get(state.events, instance_id) do
      nil ->
        {:reply, {:error, :event_not_found}, state}

      event_state ->
        # Find collect objectives that match this item
        {objectives, updated} =
          update_matching_objectives(event_state.objectives, :collect, item_id, amount)

        if updated do
          event_state = %{event_state | objectives: objectives}
          events = Map.put(state.events, instance_id, event_state)

          # Track contribution (collections give 5 points per item)
          state = track_participant_contribution(state, character_id, 5 * amount)

          state = %{state | events: events}
          state = maybe_advance_phase(state, instance_id)

          {:reply, {:ok, %{updated: true, objectives: objectives}}, state}
        else
          {:reply, {:ok, %{updated: false}}, state}
        end
    end
  end

  @impl true
  def handle_call({:record_interaction, instance_id, character_id, object_id}, _from, state) do
    case Map.get(state.events, instance_id) do
      nil ->
        {:reply, {:error, :event_not_found}, state}

      event_state ->
        # Find interact objectives that match this object
        {objectives, updated} =
          update_matching_objectives(event_state.objectives, :interact, object_id)

        if updated do
          event_state = %{event_state | objectives: objectives}
          events = Map.put(state.events, instance_id, event_state)

          # Track contribution (interactions give 15 points)
          state = track_participant_contribution(state, character_id, 15)

          state = %{state | events: events}
          state = maybe_advance_phase(state, instance_id)

          {:reply, {:ok, %{updated: true, objectives: objectives}}, state}
        else
          {:reply, {:ok, %{updated: false}}, state}
        end
    end
  end

  @impl true
  def handle_call({:record_damage, instance_id, character_id, damage}, _from, state) do
    case Map.get(state.events, instance_id) do
      nil ->
        {:reply, {:error, :event_not_found}, state}

      event_state ->
        # Update damage objectives
        objectives =
          Enum.map(event_state.objectives, fn obj ->
            if obj.type == :damage do
              new_current = min(obj.current + damage, obj.target)
              %{obj | current: new_current}
            else
              obj
            end
          end)

        event_state = %{event_state | objectives: objectives}
        events = Map.put(state.events, instance_id, event_state)

        # Track contribution (1 point per 100 damage)
        contribution = div(damage, 100)
        state = track_participant_contribution(state, character_id, contribution)

        # Track damage dealt
        participant = Map.get(state.participants, character_id)

        state =
          if participant do
            participant = %{participant | damage_dealt: participant.damage_dealt + damage}
            %{state | participants: Map.put(state.participants, character_id, participant)}
          else
            state
          end

        state = %{state | events: events}
        state = maybe_advance_phase(state, instance_id)

        {:reply, {:ok, %{damage_recorded: damage}}, state}
    end
  end

  @impl true
  def handle_call({:get_objectives, instance_id}, _from, state) do
    case Map.get(state.events, instance_id) do
      nil ->
        {:reply, {:error, :event_not_found}, state}

      event_state ->
        {:reply, {:ok, event_state.objectives}, state}
    end
  end

  # World Boss Handlers

  @impl true
  def handle_call({:spawn_world_boss, boss_id, position}, _from, state) do
    case BezgelorData.get_world_boss(boss_id) do
      {:ok, boss_def} ->
        creature_id = System.unique_integer([:positive])

        boss_state = %{
          boss_id: boss_id,
          boss_def: boss_def,
          creature_id: creature_id,
          phase: 1,
          health_max: boss_def["health"] || 1_000_000,
          health_current: boss_def["health"] || 1_000_000,
          engaged_at: nil,
          position: position,
          participants: MapSet.new(),
          contributions: %{}
        }

        world_bosses = Map.put(state.world_bosses, boss_id, boss_state)

        # Update DB
        PublicEvents.spawn_boss(boss_id)

        Logger.info("Spawned world boss #{boss_id} (creature #{creature_id}) in zone #{state.zone_id}")
        {:reply, {:ok, creature_id}, %{state | world_bosses: world_bosses}}

      :error ->
        {:reply, {:error, :boss_not_found}, state}
    end
  end

  @impl true
  def handle_call({:damage_world_boss, boss_id, character_id, damage}, _from, state) do
    case Map.get(state.world_bosses, boss_id) do
      nil ->
        {:reply, {:error, :boss_not_found}, state}

      boss_state ->
        # Mark as engaged if first damage
        boss_state =
          if is_nil(boss_state.engaged_at) do
            PublicEvents.engage_boss(boss_id)
            %{boss_state | engaged_at: DateTime.utc_now()}
          else
            boss_state
          end

        # Add to participants
        boss_state = %{boss_state | participants: MapSet.put(boss_state.participants, character_id)}

        # Track contribution
        current_contrib = Map.get(boss_state.contributions, character_id, 0)
        contributions = Map.put(boss_state.contributions, character_id, current_contrib + damage)
        boss_state = %{boss_state | contributions: contributions}

        # Apply damage
        new_health = max(0, boss_state.health_current - damage)
        boss_state = %{boss_state | health_current: new_health}

        # Check for phase transitions
        boss_state = check_boss_phase_transition(boss_state)

        # Check for death
        if new_health <= 0 do
          state = kill_world_boss(state, boss_id, boss_state)
          {:reply, {:ok, %{health: 0, killed: true}}, state}
        else
          world_bosses = Map.put(state.world_bosses, boss_id, boss_state)
          {:reply, {:ok, %{health: new_health, killed: false, phase: boss_state.phase}}, %{state | world_bosses: world_bosses}}
        end
    end
  end

  @impl true
  def handle_call({:get_world_boss, boss_id}, _from, state) do
    case Map.get(state.world_bosses, boss_id) do
      nil -> {:reply, {:error, :not_found}, state}
      boss_state -> {:reply, {:ok, boss_state}, state}
    end
  end

  @impl true
  def handle_call(:list_world_bosses, _from, state) do
    bosses =
      Enum.map(state.world_bosses, fn {boss_id, boss_state} ->
        %{
          boss_id: boss_id,
          creature_id: boss_state.creature_id,
          health_percent: div(boss_state.health_current * 100, boss_state.health_max),
          phase: boss_state.phase,
          participant_count: MapSet.size(boss_state.participants)
        }
      end)

    {:reply, bosses, state}
  end

  # Wave System Handlers

  @impl true
  def handle_call({:start_wave, instance_id, wave_number}, _from, state) do
    case Map.get(state.events, instance_id) do
      nil ->
        {:reply, {:error, :event_not_found}, state}

      event_state ->
        waves = event_state.event_def["waves"] || []

        if wave_number <= length(waves) do
          wave_def = Enum.at(waves, wave_number - 1)
          enemy_count = wave_def["enemy_count"] || 10

          wave_state = %{
            current_wave: wave_number,
            total_waves: length(waves),
            enemies_spawned: enemy_count,
            enemies_killed: 0,
            wave_timer: nil
          }

          # Start wave timer if defined
          wave_state =
            if wave_time = wave_def["time_limit_ms"] do
              timer_ref = Process.send_after(self(), {:wave_timeout, instance_id}, wave_time)
              %{wave_state | wave_timer: timer_ref}
            else
              wave_state
            end

          event_state = %{event_state | wave_state: wave_state}
          events = Map.put(state.events, instance_id, event_state)

          Logger.info("Started wave #{wave_number}/#{length(waves)} for event #{instance_id}")
          {:reply, {:ok, wave_state}, %{state | events: events}}
        else
          {:reply, {:error, :invalid_wave}, state}
        end
    end
  end

  @impl true
  def handle_call({:wave_enemy_killed, instance_id, character_id, _creature_id}, _from, state) do
    case Map.get(state.events, instance_id) do
      nil ->
        {:reply, {:error, :event_not_found}, state}

      %{wave_state: nil} ->
        {:reply, {:error, :no_wave_active}, state}

      event_state ->
        wave_state = event_state.wave_state
        wave_state = %{wave_state | enemies_killed: wave_state.enemies_killed + 1}

        # Track contribution
        state = track_participant_contribution(state, character_id, 10)

        # Check if wave complete
        if wave_state.enemies_killed >= wave_state.enemies_spawned do
          # Cancel wave timer
          if wave_state.wave_timer do
            Process.cancel_timer(wave_state.wave_timer)
          end

          Logger.info("Wave #{wave_state.current_wave} completed for event #{instance_id}")

          # Check if more waves
          state =
            if wave_state.current_wave < wave_state.total_waves do
              # Auto-start next wave after delay
              Process.send_after(self(), {:start_next_wave, instance_id}, 5_000)
              state
            else
              # All waves complete - advance phase or complete event
              maybe_advance_phase(state, instance_id)
            end

          event_state = Map.get(state.events, instance_id) || event_state
          event_state = %{event_state | wave_state: nil}
          events = Map.put(state.events, instance_id, event_state)
          {:reply, {:ok, %{wave_complete: true}}, %{state | events: events}}
        else
          event_state = %{event_state | wave_state: wave_state}
          events = Map.put(state.events, instance_id, event_state)
          {:reply, {:ok, %{wave_complete: false, remaining: wave_state.enemies_spawned - wave_state.enemies_killed}}, %{state | events: events}}
        end
    end
  end

  @impl true
  def handle_call({:get_wave_state, instance_id}, _from, state) do
    case Map.get(state.events, instance_id) do
      nil ->
        {:reply, {:error, :event_not_found}, state}

      event_state ->
        {:reply, {:ok, event_state.wave_state}, state}
    end
  end

  # Territory Control Handlers

  @impl true
  def handle_call({:enter_territory, instance_id, territory_index, character_id}, _from, state) do
    case Map.get(state.events, instance_id) do
      nil ->
        {:reply, {:error, :event_not_found}, state}

      event_state ->
        # Initialize territory state if needed
        event_state = maybe_init_territory_state(event_state)

        case get_territory_point(event_state.territory_state, territory_index) do
          nil ->
            {:reply, {:error, :territory_not_found}, state}

          territory ->
            # Add player to territory zone
            players = MapSet.put(territory.players_in_zone, character_id)
            territory = %{territory | players_in_zone: players}

            territory_state = update_territory_point(event_state.territory_state, territory_index, territory)

            # Start capture tick timer if not running and players present
            territory_state = maybe_start_capture_tick(territory_state, instance_id)

            event_state = %{event_state | territory_state: territory_state}
            events = Map.put(state.events, instance_id, event_state)

            Logger.debug("Character #{character_id} entered territory #{territory_index} in event #{instance_id}")
            {:reply, {:ok, territory}, %{state | events: events}}
        end
    end
  end

  @impl true
  def handle_call({:leave_territory, instance_id, territory_index, character_id}, _from, state) do
    case Map.get(state.events, instance_id) do
      nil ->
        {:reply, {:error, :event_not_found}, state}

      %{territory_state: nil} ->
        {:reply, :ok, state}

      event_state ->
        case get_territory_point(event_state.territory_state, territory_index) do
          nil ->
            {:reply, :ok, state}

          territory ->
            # Remove player from territory zone
            players = MapSet.delete(territory.players_in_zone, character_id)
            territory = %{territory | players_in_zone: players}

            territory_state = update_territory_point(event_state.territory_state, territory_index, territory)
            event_state = %{event_state | territory_state: territory_state}
            events = Map.put(state.events, instance_id, event_state)

            Logger.debug("Character #{character_id} left territory #{territory_index} in event #{instance_id}")
            {:reply, :ok, %{state | events: events}}
        end
    end
  end

  @impl true
  def handle_call({:get_territory_state, instance_id}, _from, state) do
    case Map.get(state.events, instance_id) do
      nil ->
        {:reply, {:error, :event_not_found}, state}

      event_state ->
        {:reply, {:ok, event_state.territory_state}, state}
    end
  end

  @impl true
  def handle_info({:wave_timeout, instance_id}, state) do
    case Map.get(state.events, instance_id) do
      nil ->
        {:noreply, state}

      %{wave_state: nil} ->
        {:noreply, state}

      event_state ->
        Logger.info("Wave timeout for event #{instance_id}")
        # Wave failed - could fail event or just advance
        event_state = %{event_state | wave_state: nil}
        events = Map.put(state.events, instance_id, event_state)
        {:noreply, %{state | events: events}}
    end
  end

  @impl true
  def handle_info({:start_next_wave, instance_id}, state) do
    case Map.get(state.events, instance_id) do
      nil ->
        {:noreply, state}

      event_state ->
        next_wave = (event_state.wave_state && event_state.wave_state.current_wave + 1) || 1

        case do_start_wave(state, instance_id, next_wave) do
          {:ok, new_state} -> {:noreply, new_state}
          {:error, _} -> {:noreply, state}
        end
    end
  end

  @impl true
  def handle_info({:event_time_limit, instance_id}, state) do
    case Map.get(state.events, instance_id) do
      nil ->
        {:noreply, state}

      event_state ->
        Logger.info("Event #{instance_id} time limit reached")
        # Check if objectives are met for partial success
        state = complete_event(state, instance_id, check_objectives_met(event_state))
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:territory_capture_tick, instance_id}, state) do
    case Map.get(state.events, instance_id) do
      nil ->
        {:noreply, state}

      %{territory_state: nil} ->
        {:noreply, state}

      event_state ->
        territory_state = process_territory_tick(event_state.territory_state)

        # Check if all territories captured (for territory objectives)
        all_captured = all_territories_captured?(territory_state)

        event_state = %{event_state | territory_state: territory_state}
        events = Map.put(state.events, instance_id, event_state)
        state = %{state | events: events}

        # If all territories captured, advance phase
        state =
          if all_captured do
            # Update territory objectives
            state = update_territory_objectives(state, instance_id)
            maybe_advance_phase(state, instance_id)
          else
            state
          end

        # Schedule next tick if there are still players in any territory
        state =
          if any_players_in_territories?(territory_state) do
            event_state = Map.get(state.events, instance_id)

            if event_state do
              territory_state = schedule_capture_tick(event_state.territory_state, instance_id)
              event_state = %{event_state | territory_state: territory_state}
              events = Map.put(state.events, instance_id, event_state)
              %{state | events: events}
            else
              state
            end
          else
            # Cancel the timer reference
            event_state = Map.get(state.events, instance_id)

            if event_state && event_state.territory_state do
              territory_state = %{event_state.territory_state | capture_tick_timer: nil}
              event_state = %{event_state | territory_state: territory_state}
              events = Map.put(state.events, instance_id, event_state)
              %{state | events: events}
            else
              state
            end
          end

        {:noreply, state}
    end
  end

  ## Private Helpers

  defp do_start_wave(state, instance_id, wave_number) do
    event_state = Map.get(state.events, instance_id)
    waves = event_state.event_def["waves"] || []

    if wave_number <= length(waves) do
      wave_def = Enum.at(waves, wave_number - 1)
      enemy_count = wave_def["enemy_count"] || 10

      wave_state = %{
        current_wave: wave_number,
        total_waves: length(waves),
        enemies_spawned: enemy_count,
        enemies_killed: 0,
        wave_timer: nil
      }

      wave_state =
        if wave_time = wave_def["time_limit_ms"] do
          timer_ref = Process.send_after(self(), {:wave_timeout, instance_id}, wave_time)
          %{wave_state | wave_timer: timer_ref}
        else
          wave_state
        end

      event_state = %{event_state | wave_state: wave_state}
      events = Map.put(state.events, instance_id, event_state)

      Logger.info("Auto-started wave #{wave_number} for event #{instance_id}")
      {:ok, %{state | events: events}}
    else
      {:error, :no_more_waves}
    end
  end

  defp create_event_state(event_id, event_def) do
    phases = event_def["phases"] || []
    first_phase = List.first(phases) || %{}
    objectives = parse_objectives(first_phase["objectives"] || [])

    %{
      event_id: event_id,
      event_def: event_def,
      phase: 1,
      objectives: objectives,
      started_at: DateTime.utc_now(),
      time_limit_timer: nil,
      participants: MapSet.new(),
      wave_state: nil,
      territory_state: nil
    }
  end

  defp parse_objectives(objectives) do
    objectives
    |> Enum.with_index()
    |> Enum.map(fn {obj, index} ->
      %{
        index: index,
        type: String.to_atom(obj["type"] || "kill"),
        target: obj["target"] || 0,
        target_id: obj["target_id"],
        current: 0
      }
    end)
  end

  defp maybe_start_time_limit(event_state, instance_id) do
    time_limit = event_state.event_def["time_limit_ms"]

    if time_limit && time_limit > 0 do
      timer_ref = Process.send_after(self(), {:event_time_limit, instance_id}, time_limit)
      %{event_state | time_limit_timer: timer_ref}
    else
      event_state
    end
  end

  defp calculate_time_remaining(event_state) do
    time_limit = event_state.event_def["time_limit_ms"]

    if time_limit && time_limit > 0 do
      elapsed = DateTime.diff(DateTime.utc_now(), event_state.started_at, :millisecond)
      max(0, time_limit - elapsed)
    else
      0
    end
  end

  defp check_objectives_met(event_state) do
    Enum.all?(event_state.objectives, fn obj ->
      obj.current >= obj.target
    end)
  end

  defp maybe_advance_phase(state, instance_id) do
    event_state = Map.get(state.events, instance_id)

    if check_objectives_met(event_state) do
      phases = event_state.event_def["phases"] || []
      next_phase = event_state.phase + 1

      if next_phase <= length(phases) do
        # Advance to next phase
        phase_def = Enum.at(phases, next_phase - 1)
        objectives = parse_objectives(phase_def["objectives"] || [])

        event_state = %{event_state | phase: next_phase, objectives: objectives}
        events = Map.put(state.events, instance_id, event_state)

        Logger.info("Event #{instance_id} advanced to phase #{next_phase}")
        %{state | events: events}
      else
        # All phases complete - success!
        complete_event(state, instance_id, true)
      end
    else
      state
    end
  end

  defp complete_event(state, instance_id, success) do
    case Map.get(state.events, instance_id) do
      nil ->
        state

      event_state ->
        # Cancel timers
        if event_state.time_limit_timer do
          Process.cancel_timer(event_state.time_limit_timer)
        end

        if event_state.wave_state && event_state.wave_state.wave_timer do
          Process.cancel_timer(event_state.wave_state.wave_timer)
        end

        if event_state.territory_state && event_state.territory_state.capture_tick_timer do
          Process.cancel_timer(event_state.territory_state.capture_tick_timer)
        end

        # Update DB
        if success do
          PublicEvents.complete_event(instance_id)
        else
          PublicEvents.fail_event(instance_id)
        end

        # Distribute rewards
        if success do
          distribute_event_rewards(event_state, state.participants)
        end

        Logger.info("Event #{instance_id} completed: success=#{success}, participants=#{MapSet.size(event_state.participants)}")

        events = Map.delete(state.events, instance_id)
        %{state | events: events}
    end
  end

  defp update_matching_objectives(objectives, type, target_id, amount \\ 1) do
    {updated_objectives, any_updated} =
      Enum.map_reduce(objectives, false, fn obj, updated ->
        if obj.type == type and (obj.target_id == nil or obj.target_id == target_id) and obj.current < obj.target do
          new_current = min(obj.current + amount, obj.target)
          {%{obj | current: new_current}, true}
        else
          {obj, updated}
        end
      end)

    {updated_objectives, any_updated}
  end

  defp track_participant_contribution(state, character_id, amount) do
    participant =
      Map.get(state.participants, character_id, %{
        character_id: character_id,
        contribution: 0,
        damage_dealt: 0,
        joined_at: DateTime.utc_now()
      })

    participant = %{participant | contribution: participant.contribution + amount}
    %{state | participants: Map.put(state.participants, character_id, participant)}
  end

  # World Boss Helpers

  defp check_boss_phase_transition(boss_state) do
    phases = boss_state.boss_def["phases"] || []
    health_percent = div(boss_state.health_current * 100, boss_state.health_max)

    # Find the appropriate phase based on health
    new_phase =
      phases
      |> Enum.with_index(1)
      |> Enum.find_value(boss_state.phase, fn {phase_def, phase_num} ->
        threshold = phase_def["health_threshold"] || 0

        if health_percent <= threshold and phase_num > boss_state.phase do
          phase_num
        else
          nil
        end
      end)

    if new_phase != boss_state.phase do
      Logger.info("World boss #{boss_state.boss_id} transitioned to phase #{new_phase}")
      %{boss_state | phase: new_phase}
    else
      boss_state
    end
  end

  defp kill_world_boss(state, boss_id, boss_state) do
    # Calculate kill time
    kill_time_ms =
      if boss_state.engaged_at do
        DateTime.diff(DateTime.utc_now(), boss_state.engaged_at, :millisecond)
      else
        0
      end

    # Update DB
    PublicEvents.kill_boss(boss_id, 24)

    Logger.info(
      "World boss #{boss_id} killed in #{kill_time_ms}ms by #{MapSet.size(boss_state.participants)} participants"
    )

    # Distribute rewards to all contributors
    distribute_boss_rewards(boss_state)

    world_bosses = Map.delete(state.world_bosses, boss_id)
    %{state | world_bosses: world_bosses}
  end

  # Territory Control Helpers

  @capture_tick_interval_ms 1_000
  @capture_progress_per_tick 5
  @capture_progress_max 100

  defp maybe_init_territory_state(%{territory_state: nil} = event_state) do
    territories = event_state.event_def["territories"] || []

    if length(territories) > 0 do
      territory_points =
        territories
        |> Enum.with_index()
        |> Enum.map(fn {territory_def, index} ->
          %{
            index: index,
            name: territory_def["name"] || "Territory #{index + 1}",
            capture_progress: 0,
            players_in_zone: MapSet.new(),
            captured: false
          }
        end)

      territory_state = %{
        territories: territory_points,
        capture_tick_timer: nil
      }

      %{event_state | territory_state: territory_state}
    else
      event_state
    end
  end

  defp maybe_init_territory_state(event_state), do: event_state

  defp get_territory_point(nil, _index), do: nil

  defp get_territory_point(territory_state, index) do
    Enum.find(territory_state.territories, &(&1.index == index))
  end

  defp update_territory_point(territory_state, index, updated_territory) do
    territories =
      Enum.map(territory_state.territories, fn territory ->
        if territory.index == index do
          updated_territory
        else
          territory
        end
      end)

    %{territory_state | territories: territories}
  end

  defp maybe_start_capture_tick(%{capture_tick_timer: nil} = territory_state, instance_id) do
    if any_players_in_territories?(territory_state) do
      schedule_capture_tick(territory_state, instance_id)
    else
      territory_state
    end
  end

  defp maybe_start_capture_tick(territory_state, _instance_id), do: territory_state

  defp schedule_capture_tick(territory_state, instance_id) do
    timer_ref = Process.send_after(self(), {:territory_capture_tick, instance_id}, @capture_tick_interval_ms)
    %{territory_state | capture_tick_timer: timer_ref}
  end

  defp process_territory_tick(territory_state) do
    territories =
      Enum.map(territory_state.territories, fn territory ->
        player_count = MapSet.size(territory.players_in_zone)

        if player_count > 0 and not territory.captured do
          # Progress increases based on player count (diminishing returns)
          progress_increase = @capture_progress_per_tick * min(player_count, 5)
          new_progress = min(territory.capture_progress + progress_increase, @capture_progress_max)

          captured = new_progress >= @capture_progress_max

          if captured do
            Logger.info("Territory #{territory.index} (#{territory.name}) captured!")
          end

          %{territory | capture_progress: new_progress, captured: captured}
        else
          territory
        end
      end)

    %{territory_state | territories: territories}
  end

  defp any_players_in_territories?(territory_state) do
    Enum.any?(territory_state.territories, fn territory ->
      MapSet.size(territory.players_in_zone) > 0
    end)
  end

  defp all_territories_captured?(territory_state) do
    Enum.all?(territory_state.territories, & &1.captured)
  end

  defp update_territory_objectives(state, instance_id) do
    event_state = Map.get(state.events, instance_id)

    if event_state do
      captured_count =
        event_state.territory_state.territories
        |> Enum.count(& &1.captured)

      # Update territory-type objectives
      objectives =
        Enum.map(event_state.objectives, fn obj ->
          if obj.type == :territory do
            %{obj | current: captured_count}
          else
            obj
          end
        end)

      event_state = %{event_state | objectives: objectives}
      events = Map.put(state.events, instance_id, event_state)
      %{state | events: events}
    else
      state
    end
  end

  # Reward Distribution Helpers

  @gold_tier_threshold 80
  @silver_tier_threshold 50
  @bronze_tier_threshold 20

  @gold_multiplier 1.0
  @silver_multiplier 0.75
  @bronze_multiplier 0.5
  @participation_multiplier 0.25

  defp distribute_event_rewards(event_state, participants) do
    rewards_def = event_state.event_def["rewards"] || %{}
    participant_ids = MapSet.to_list(event_state.participants)

    # Calculate duration
    duration_ms = DateTime.diff(DateTime.utc_now(), event_state.started_at, :millisecond)

    # Calculate total contribution for tier assignment
    contributions =
      Enum.map(participant_ids, fn char_id ->
        participant = Map.get(participants, char_id)
        {char_id, participant && participant.contribution || 0}
      end)

    total_contribution = Enum.reduce(contributions, 0, fn {_, c}, acc -> acc + c end)
    max_contribution = Enum.max_by(contributions, fn {_, c} -> c end, fn -> {0, 0} end) |> elem(1)

    # Assign reward tiers and distribute
    Enum.each(contributions, fn {character_id, contribution} ->
      tier = calculate_reward_tier(contribution, total_contribution, max_contribution)
      multiplier = tier_multiplier(tier)

      reward_data = calculate_participant_rewards(rewards_def, multiplier)

      # Log the reward (actual distribution would call game systems)
      Logger.debug("Event reward for #{character_id}: tier=#{tier}, rewards=#{inspect(reward_data)}")

      # Record completion in DB (character_id, event_id, tier, contribution, duration_ms)
      PublicEvents.record_completion(
        character_id,
        event_state.event_id,
        tier_to_string(tier),
        contribution,
        duration_ms
      )

      # TODO: Actually grant rewards via Inventory/Currency/XP systems
      # BezgelorWorld.Rewards.grant_event_rewards(character_id, reward_data)
    end)
  end

  defp calculate_reward_tier(contribution, total_contribution, max_contribution) do
    cond do
      total_contribution == 0 ->
        :participation

      contribution == max_contribution and contribution > 0 ->
        :gold

      true ->
        percent = if total_contribution > 0, do: div(contribution * 100, total_contribution), else: 0

        cond do
          percent >= @gold_tier_threshold -> :gold
          percent >= @silver_tier_threshold -> :silver
          percent >= @bronze_tier_threshold -> :bronze
          true -> :participation
        end
    end
  end

  defp tier_multiplier(:gold), do: @gold_multiplier
  defp tier_multiplier(:silver), do: @silver_multiplier
  defp tier_multiplier(:bronze), do: @bronze_multiplier
  defp tier_multiplier(:participation), do: @participation_multiplier

  defp tier_to_string(:gold), do: "gold"
  defp tier_to_string(:silver), do: "silver"
  defp tier_to_string(:bronze), do: "bronze"
  defp tier_to_string(:participation), do: "participation"

  defp calculate_participant_rewards(rewards_def, multiplier) do
    %{
      xp: round((rewards_def["xp"] || 0) * multiplier),
      gold: round((rewards_def["gold"] || 0) * multiplier),
      currency: scale_currency_rewards(rewards_def["currency"], multiplier),
      reputation: scale_reputation_reward(rewards_def["reputation"], multiplier),
      loot_table_id: rewards_def["loot_table_id"],
      achievement_id: rewards_def["achievement_id"]
    }
  end

  defp scale_currency_rewards(nil, _multiplier), do: %{}

  defp scale_currency_rewards(currency_map, multiplier) when is_map(currency_map) do
    Map.new(currency_map, fn {currency, amount} ->
      {currency, round(amount * multiplier)}
    end)
  end

  defp scale_reputation_reward(nil, _multiplier), do: nil

  defp scale_reputation_reward(%{"faction_id" => faction_id, "amount" => amount}, multiplier) do
    %{faction_id: faction_id, amount: round(amount * multiplier)}
  end

  defp scale_reputation_reward(_other, _multiplier), do: nil

  # World Boss Reward Distribution

  defp distribute_boss_rewards(boss_state) do
    boss_def = boss_state.boss_def
    rewards_def = boss_def["rewards"] || %{}
    total_damage = boss_state.health_max

    # Sort contributors by damage
    sorted_contributors =
      boss_state.contributions
      |> Enum.sort_by(fn {_id, damage} -> damage end, :desc)

    # Top contributor gets gold tier, rest scaled by damage percentage
    Enum.each(sorted_contributors, fn {character_id, damage} ->
      damage_percent = if total_damage > 0, do: div(damage * 100, total_damage), else: 0

      tier =
        cond do
          damage_percent >= 10 -> :gold
          damage_percent >= 5 -> :silver
          damage_percent >= 1 -> :bronze
          true -> :participation
        end

      multiplier = tier_multiplier(tier)
      reward_data = calculate_participant_rewards(rewards_def, multiplier)

      Logger.debug(
        "Boss reward for #{character_id}: tier=#{tier}, damage=#{damage} (#{damage_percent}%), rewards=#{inspect(reward_data)}"
      )

      # TODO: Record in DB when boss kill tracking is added
      # TODO: Actually grant rewards via BezgelorWorld.Rewards
      _ = {boss_state.boss_id, reward_data}
    end)
  end
end
