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
          participants: MapSet.t(non_neg_integer())
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
        case PublicEvents.start_event(event_id, state.zone_id, instance_id) do
          {:ok, _db_event} ->
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
        PublicEvents.add_participant(instance_id, character_id)

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

      event_state ->
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
        PublicEvents.update_contribution(instance_id, character_id, amount)

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

  ## Private Helpers

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
      participants: MapSet.new()
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
        # Cancel timer
        if event_state.time_limit_timer do
          Process.cancel_timer(event_state.time_limit_timer)
        end

        # Update DB
        if success do
          PublicEvents.complete_event(instance_id)
        else
          PublicEvents.fail_event(instance_id)
        end

        # TODO: Distribute rewards (Task 21)
        Logger.info("Event #{instance_id} completed: success=#{success}")

        events = Map.delete(state.events, instance_id)
        %{state | events: events}
    end
  end
end
