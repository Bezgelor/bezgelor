defmodule BezgelorWorld.GroupFinder.GroupFinder do
  @moduledoc """
  GenServer managing the group finder queue and matchmaking.

  Handles:
  - Player queue management (join, leave, update)
  - Role-based matchmaking
  - Group formation and confirmation
  - Instance creation when groups accept

  ## Matching Tiers

  1. **Simple FIFO** (Normal dungeons) - First-come, first-served
  2. **Smart Matching** (Veteran dungeons) - Consider gear score, experience
  3. **Advanced Matching** (Raids) - Role composition, faction, language

  ## Queue Flow

  1. Player joins queue with role(s) and instance preferences
  2. System periodically attempts to form groups
  3. When match found, all players get confirmation prompt
  4. If all accept, instance is created and players teleported
  5. If anyone declines/times out, back to queue for remaining players
  """
  use GenServer

  alias BezgelorWorld.GroupFinder.Matcher
  alias BezgelorWorld.Instance.Supervisor, as: InstanceSupervisor

  require Logger

  @match_interval 5_000      # Check for matches every 5 seconds
  @confirm_timeout 30_000    # 30 seconds to accept/decline

  defstruct [
    queues: %{},           # instance_type => [queue_entry]
    pending_matches: %{},  # match_id => pending_match
    player_queue: %{},     # character_id => queue_info
    stats: %{
      total_queued: 0,
      matches_formed: 0,
      matches_completed: 0,
      average_wait_time: 0
    }
  ]

  @type role :: :tank | :healer | :dps
  @type instance_type :: :dungeon | :adventure | :raid | :expedition
  @type difficulty :: :normal | :veteran | :challenge | :mythic_plus

  @type queue_entry :: %{
          character_id: non_neg_integer(),
          name: String.t(),
          class_id: non_neg_integer(),
          level: non_neg_integer(),
          roles: [role()],
          instance_ids: [non_neg_integer()],
          instance_type: instance_type(),
          difficulty: difficulty(),
          gear_score: non_neg_integer(),
          language: String.t(),
          queued_at: integer(),
          estimated_wait: integer() | nil
        }

  @type pending_match :: %{
          match_id: non_neg_integer(),
          instance_id: non_neg_integer(),
          instance_type: instance_type(),
          difficulty: difficulty(),
          members: [%{character_id: non_neg_integer(), role: role(), accepted: boolean() | nil}],
          created_at: integer(),
          expires_at: integer()
        }

  # Client API

  @doc """
  Starts the group finder server.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Joins the queue with specified roles and preferences.
  """
  @spec join_queue(queue_entry()) :: :ok | {:error, term()}
  def join_queue(entry) do
    GenServer.call(__MODULE__, {:join_queue, entry})
  end

  @doc """
  Leaves the queue.
  """
  @spec leave_queue(non_neg_integer()) :: :ok
  def leave_queue(character_id) do
    GenServer.call(__MODULE__, {:leave_queue, character_id})
  end

  @doc """
  Updates queue preferences (roles, instances).
  """
  @spec update_queue(non_neg_integer(), map()) :: :ok | {:error, term()}
  def update_queue(character_id, updates) do
    GenServer.call(__MODULE__, {:update_queue, character_id, updates})
  end

  @doc """
  Gets queue status for a player.
  """
  @spec get_queue_status(non_neg_integer()) :: {:ok, map()} | {:error, :not_queued}
  def get_queue_status(character_id) do
    GenServer.call(__MODULE__, {:get_queue_status, character_id})
  end

  @doc """
  Responds to a match confirmation (accept/decline).
  """
  @spec respond_to_match(non_neg_integer(), non_neg_integer(), boolean()) :: :ok | {:error, term()}
  def respond_to_match(match_id, character_id, accepted) do
    GenServer.call(__MODULE__, {:respond_to_match, match_id, character_id, accepted})
  end

  @doc """
  Gets global queue statistics.
  """
  @spec get_stats() :: map()
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc """
  Gets queue counts by role for an instance type.
  """
  @spec get_role_counts(instance_type(), difficulty()) :: map()
  def get_role_counts(instance_type, difficulty) do
    GenServer.call(__MODULE__, {:get_role_counts, instance_type, difficulty})
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Initialize queues for each instance type
    queues =
      Map.new([:dungeon, :adventure, :raid, :expedition], fn type ->
        {type, []}
      end)

    schedule_match_check()

    {:ok, %__MODULE__{queues: queues}}
  end

  @impl true
  def handle_call({:join_queue, entry}, _from, state) do
    character_id = entry.character_id

    if Map.has_key?(state.player_queue, character_id) do
      {:reply, {:error, :already_queued}, state}
    else
      entry =
        entry
        |> Map.put(:queued_at, System.monotonic_time(:millisecond))
        |> Map.put(:estimated_wait, estimate_wait_time(state, entry))

      # Add to appropriate queue
      queue_key = entry.instance_type
      queues = Map.update!(state.queues, queue_key, &[entry | &1])

      # Track player
      player_queue = Map.put(state.player_queue, character_id, %{
        instance_type: queue_key,
        entry: entry
      })

      stats = Map.update!(state.stats, :total_queued, &(&1 + 1))

      Logger.info("Player #{character_id} joined #{queue_key} queue")

      # Notify player of queue status
      send_queue_status(character_id, entry)

      {:reply, :ok, %{state | queues: queues, player_queue: player_queue, stats: stats}}
    end
  end

  def handle_call({:leave_queue, character_id}, _from, state) do
    state = remove_from_queue(state, character_id)
    Logger.info("Player #{character_id} left queue")
    {:reply, :ok, state}
  end

  def handle_call({:update_queue, character_id, updates}, _from, state) do
    case Map.get(state.player_queue, character_id) do
      nil ->
        {:reply, {:error, :not_queued}, state}

      %{instance_type: queue_key, entry: entry} ->
        new_entry = Map.merge(entry, updates)
        queues =
          Map.update!(state.queues, queue_key, fn queue ->
            Enum.map(queue, fn e ->
              if e.character_id == character_id, do: new_entry, else: e
            end)
          end)

        player_queue =
          Map.put(state.player_queue, character_id, %{
            instance_type: queue_key,
            entry: new_entry
          })

        {:reply, :ok, %{state | queues: queues, player_queue: player_queue}}
    end
  end

  def handle_call({:get_queue_status, character_id}, _from, state) do
    case Map.get(state.player_queue, character_id) do
      nil ->
        # Check pending matches
        case find_pending_match(state, character_id) do
          nil -> {:reply, {:error, :not_queued}, state}
          match -> {:reply, {:ok, %{status: :match_found, match: match}}, state}
        end

      %{entry: entry} ->
        wait_time = System.monotonic_time(:millisecond) - entry.queued_at
        position = queue_position(state, entry)

        status = %{
          status: :queued,
          roles: entry.roles,
          instance_type: entry.instance_type,
          difficulty: entry.difficulty,
          wait_time_ms: wait_time,
          estimated_wait_ms: entry.estimated_wait,
          position: position
        }

        {:reply, {:ok, status}, state}
    end
  end

  def handle_call({:respond_to_match, match_id, character_id, accepted}, _from, state) do
    case Map.get(state.pending_matches, match_id) do
      nil ->
        {:reply, {:error, :match_not_found}, state}

      match ->
        # Verify player is part of this match
        if character_in_match?(match, character_id) do
          state = update_match_response(state, match_id, character_id, accepted)

          if accepted do
            Logger.info("Player #{character_id} accepted match #{match_id}")
          else
            Logger.info("Player #{character_id} declined match #{match_id}")
          end

          # Check if match is resolved
          state = check_match_completion(state, match_id)

          {:reply, :ok, state}
        else
          {:reply, {:error, :not_in_match}, state}
        end
    end
  end

  def handle_call(:get_stats, _from, state) do
    queue_counts =
      Map.new(state.queues, fn {type, queue} ->
        {type, length(queue)}
      end)

    stats = Map.put(state.stats, :queue_counts, queue_counts)
    {:reply, stats, state}
  end

  def handle_call({:get_role_counts, instance_type, difficulty}, _from, state) do
    queue = Map.get(state.queues, instance_type, [])

    filtered =
      Enum.filter(queue, fn entry ->
        entry.difficulty == difficulty
      end)

    counts = %{
      tank: count_role(filtered, :tank),
      healer: count_role(filtered, :healer),
      dps: count_role(filtered, :dps)
    }

    {:reply, counts, state}
  end

  @impl true
  def handle_info(:check_matches, state) do
    state = process_all_queues(state)
    state = cleanup_expired_matches(state)
    schedule_match_check()
    {:noreply, state}
  end

  def handle_info({:match_timeout, match_id}, state) do
    state = handle_match_timeout(state, match_id)
    {:noreply, state}
  end

  def handle_info({:queue_timeout, character_id}, state) do
    state = remove_from_queue(state, character_id)
    # Notify player their queue expired
    send_queue_expired(character_id)
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private Functions

  defp character_in_match?(match, character_id) do
    Enum.any?(match.members, fn m -> m.character_id == character_id end)
  end

  defp schedule_match_check do
    Process.send_after(self(), :check_matches, @match_interval)
  end

  defp process_all_queues(state) do
    Enum.reduce(state.queues, state, fn {instance_type, queue}, acc ->
      process_queue(acc, instance_type, queue)
    end)
  end

  defp process_queue(state, instance_type, queue) do
    # Group by difficulty
    by_difficulty = Enum.group_by(queue, & &1.difficulty)

    Enum.reduce(by_difficulty, state, fn {difficulty, entries}, acc ->
      try_form_groups(acc, instance_type, difficulty, entries)
    end)
  end

  defp try_form_groups(state, instance_type, difficulty, entries) do
    case Matcher.find_match(instance_type, difficulty, entries) do
      {:ok, match} ->
        state = create_pending_match(state, instance_type, difficulty, match)
        # Remove matched players from queue and try again
        remaining = Enum.reject(entries, fn e ->
          Enum.any?(match.members, &(&1.character_id == e.character_id))
        end)
        if length(remaining) >= required_group_size(instance_type) do
          try_form_groups(state, instance_type, difficulty, remaining)
        else
          state
        end

      :no_match ->
        state
    end
  end

  defp create_pending_match(state, instance_type, difficulty, match) do
    match_id = System.unique_integer([:positive])
    now = System.monotonic_time(:millisecond)

    pending = %{
      match_id: match_id,
      instance_id: match.instance_id,
      instance_type: instance_type,
      difficulty: difficulty,
      members: Enum.map(match.members, fn m ->
        Map.put(m, :accepted, nil)
      end),
      created_at: now,
      expires_at: now + @confirm_timeout
    }

    # Remove players from queue
    state =
      Enum.reduce(match.members, state, fn m, acc ->
        remove_from_queue(acc, m.character_id)
      end)

    # Schedule timeout
    Process.send_after(self(), {:match_timeout, match_id}, @confirm_timeout)

    # Notify all players
    Enum.each(match.members, fn m ->
      send_match_found(m.character_id, pending)
    end)

    stats = Map.update!(state.stats, :matches_formed, &(&1 + 1))

    Logger.info("Match #{match_id} formed for #{instance_type} (#{difficulty})")

    %{state |
      pending_matches: Map.put(state.pending_matches, match_id, pending),
      stats: stats
    }
  end

  defp update_match_response(state, match_id, character_id, accepted) do
    update_in(state, [:pending_matches, match_id, :members], fn members ->
      Enum.map(members, fn m ->
        if m.character_id == character_id do
          %{m | accepted: accepted}
        else
          m
        end
      end)
    end)
  end

  defp check_match_completion(state, match_id) do
    case Map.get(state.pending_matches, match_id) do
      nil ->
        state

      match ->
        cond do
          # All accepted
          Enum.all?(match.members, &(&1.accepted == true)) ->
            complete_match(state, match)

          # Someone declined
          Enum.any?(match.members, &(&1.accepted == false)) ->
            cancel_match(state, match, :declined)

          # Still waiting
          true ->
            state
        end
    end
  end

  defp complete_match(state, match) do
    Logger.info("Match #{match.match_id} completed - creating instance")

    # Create instance
    instance_guid = InstanceSupervisor.generate_instance_guid()

    group_id = System.unique_integer([:positive])
    leader_id = hd(match.members).character_id

    case InstanceSupervisor.start_instance(
      instance_guid,
      match.instance_id,
      match.difficulty,
      group_id: group_id,
      leader_id: leader_id
    ) do
      {:ok, _pid} ->
        # Notify players of success
        Enum.each(match.members, fn m ->
          send_match_result(m.character_id, :formed, instance_guid, match)
        end)

        stats = Map.update!(state.stats, :matches_completed, &(&1 + 1))

        %{state |
          pending_matches: Map.delete(state.pending_matches, match.match_id),
          stats: stats
        }

      {:error, reason} ->
        Logger.error("Failed to create instance for match #{match.match_id}: #{inspect(reason)}")
        cancel_match(state, match, :instance_failed)
    end
  end

  defp cancel_match(state, match, reason) do
    Logger.info("Match #{match.match_id} cancelled: #{reason}")

    # Re-queue players who accepted (or hadn't responded)
    players_to_requeue =
      match.members
      |> Enum.reject(&(&1.accepted == false))

    state =
      Enum.reduce(players_to_requeue, state, fn member, acc ->
        # Re-add to queue with original entry
        # In a real implementation, we'd store the original entry
        send_match_result(member.character_id, :disbanded, nil, match)
        acc
      end)

    # Notify player who declined
    match.members
    |> Enum.filter(&(&1.accepted == false))
    |> Enum.each(fn member ->
      send_match_result(member.character_id, :disbanded, nil, match)
    end)

    %{state | pending_matches: Map.delete(state.pending_matches, match.match_id)}
  end

  defp handle_match_timeout(state, match_id) do
    case Map.get(state.pending_matches, match_id) do
      nil ->
        state

      match ->
        # Treat non-responses as declines
        cancel_match(state, match, :timeout)
    end
  end

  defp cleanup_expired_matches(state) do
    now = System.monotonic_time(:millisecond)

    expired =
      state.pending_matches
      |> Enum.filter(fn {_id, match} -> match.expires_at < now end)
      |> Enum.map(fn {id, _} -> id end)

    Enum.reduce(expired, state, fn match_id, acc ->
      handle_match_timeout(acc, match_id)
    end)
  end

  defp remove_from_queue(state, character_id) do
    case Map.get(state.player_queue, character_id) do
      nil ->
        state

      %{instance_type: queue_key} ->
        queues =
          Map.update!(state.queues, queue_key, fn queue ->
            Enum.reject(queue, &(&1.character_id == character_id))
          end)

        player_queue = Map.delete(state.player_queue, character_id)

        %{state | queues: queues, player_queue: player_queue}
    end
  end

  defp find_pending_match(state, character_id) do
    state.pending_matches
    |> Enum.find_value(fn {_id, match} ->
      if Enum.any?(match.members, &(&1.character_id == character_id)) do
        match
      end
    end)
  end

  defp estimate_wait_time(state, entry) do
    queue = Map.get(state.queues, entry.instance_type, [])

    # Simple estimation based on queue depth and role scarcity
    base_wait = length(queue) * 30_000  # 30s per person ahead

    role_factor =
      cond do
        :tank in entry.roles -> 0.5   # Tanks queue faster
        :healer in entry.roles -> 0.7 # Healers queue faster
        true -> 1.5                    # DPS queue slower
      end

    round(base_wait * role_factor)
  end

  defp queue_position(state, entry) do
    queue = Map.get(state.queues, entry.instance_type, [])
    case Enum.find_index(queue, &(&1.character_id == entry.character_id)) do
      nil -> length(queue)
      idx -> idx + 1
    end
  end

  defp count_role(queue, role) do
    Enum.count(queue, fn entry -> role in entry.roles end)
  end

  defp required_group_size(:raid), do: 20
  defp required_group_size(_), do: 5

  # Notification stubs - in real implementation these would send packets
  defp send_queue_status(_character_id, _entry) do
    # Would send ServerGroupFinderStatus packet
    :ok
  end

  defp send_match_found(_character_id, _match) do
    # Would send ServerGroupFinderMatch packet
    :ok
  end

  defp send_match_result(_character_id, _result, _instance_guid, _match) do
    # Would send ServerGroupFinderResult packet
    :ok
  end

  defp send_queue_expired(_character_id) do
    # Would send notification that queue expired
    :ok
  end
end
