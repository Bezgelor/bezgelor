defmodule BezgelorWorld.PvP.ArenaQueue do
  @moduledoc """
  Manages arena queue and rating-based matchmaking.

  Handles:
  - Player/team queue registration
  - Rating-based matchmaking (tries to find close ratings)
  - Match creation when teams are found
  - Queue time tracking with rating window expansion
  """

  use GenServer

  require Logger

  alias BezgelorData.Store
  alias BezgelorDb.ArenaTeams

  # Queue configuration
  @initial_rating_window 100
  @rating_window_expansion 50
  @rating_window_max 500
  @rating_expand_interval 30_000
  @queue_pop_check_interval 5_000
  @max_queue_time_ms 600_000

  defstruct [
    :team_id,
    :team_name,
    :members,
    :rating,
    :bracket,
    :queued_at,
    :rating_window
  ]

  @type queue_entry :: %__MODULE__{
          team_id: non_neg_integer(),
          team_name: String.t(),
          members: [non_neg_integer()],
          rating: non_neg_integer(),
          bracket: String.t(),
          queued_at: integer(),
          rating_window: non_neg_integer()
        }

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Join the arena queue with a team.
  Returns {:ok, estimated_wait} or {:error, reason}.
  """
  @spec join_queue(non_neg_integer(), String.t()) :: {:ok, non_neg_integer()} | {:error, atom()}
  def join_queue(team_id, bracket) do
    GenServer.call(__MODULE__, {:join_queue, team_id, bracket})
  end

  @doc """
  Join arena queue as solo player (creates ad-hoc team).
  """
  @spec join_queue_solo(non_neg_integer(), String.t(), String.t(), non_neg_integer()) ::
          {:ok, non_neg_integer()} | {:error, atom()}
  def join_queue_solo(player_guid, player_name, bracket, rating \\ 1500) do
    GenServer.call(__MODULE__, {:join_queue_solo, player_guid, player_name, bracket, rating})
  end

  @doc """
  Leave the arena queue.
  """
  @spec leave_queue(non_neg_integer()) :: :ok | {:error, :not_in_queue}
  def leave_queue(team_id) do
    GenServer.call(__MODULE__, {:leave_queue, team_id})
  end

  @doc """
  Check if a team is in queue.
  """
  @spec in_queue?(non_neg_integer()) :: boolean()
  def in_queue?(team_id) do
    GenServer.call(__MODULE__, {:in_queue?, team_id})
  end

  @doc """
  Get queue status for a team.
  """
  @spec get_queue_status(non_neg_integer()) :: {:ok, map()} | {:error, :not_in_queue}
  def get_queue_status(team_id) do
    GenServer.call(__MODULE__, {:get_queue_status, team_id})
  end

  @doc """
  Get all available arena brackets.
  """
  @spec list_brackets() :: [map()]
  def list_brackets do
    ["2v2", "3v3", "5v5"]
    |> Enum.map(fn bracket ->
      %{
        bracket: bracket,
        team_size: bracket_size(bracket),
        available: true
      }
    end)
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    Logger.info("ArenaQueue started")

    schedule_queue_check()
    schedule_rating_expansion()

    state = %{
      queues: %{
        "2v2" => [],
        "3v3" => [],
        "5v5" => []
      },
      team_queues: %{},
      active_matches: MapSet.new()
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:join_queue, team_id, bracket}, _from, state) do
    cond do
      Map.has_key?(state.team_queues, team_id) ->
        {:reply, {:error, :already_in_queue}, state}

      not valid_bracket?(bracket) ->
        {:reply, {:error, :invalid_bracket}, state}

      true ->
        case ArenaTeams.get_team(team_id) do
          {:ok, team} ->
            if team.bracket == bracket do
              entry = %__MODULE__{
                team_id: team_id,
                team_name: team.name,
                members: get_team_member_guids(team),
                rating: team.rating,
                bracket: bracket,
                queued_at: System.monotonic_time(:millisecond),
                rating_window: @initial_rating_window
              }

              state = add_to_queue(state, entry)
              estimated_wait = estimate_wait_time(state, bracket, team.rating)

              Logger.debug("Team #{team.name} joined #{bracket} arena queue (rating: #{team.rating})")
              {:reply, {:ok, estimated_wait}, state}
            else
              {:reply, {:error, :wrong_bracket}, state}
            end

          {:error, _} ->
            {:reply, {:error, :team_not_found}, state}
        end
    end
  end

  def handle_call({:join_queue_solo, player_guid, player_name, bracket, rating}, _from, state) do
    # Create ad-hoc team entry for solo queue
    team_id = -player_guid  # Negative to distinguish from real teams

    cond do
      Map.has_key?(state.team_queues, team_id) ->
        {:reply, {:error, :already_in_queue}, state}

      not valid_bracket?(bracket) ->
        {:reply, {:error, :invalid_bracket}, state}

      true ->
        entry = %__MODULE__{
          team_id: team_id,
          team_name: player_name,
          members: [player_guid],
          rating: rating,
          bracket: bracket,
          queued_at: System.monotonic_time(:millisecond),
          rating_window: @initial_rating_window
        }

        state = add_to_queue(state, entry)
        estimated_wait = estimate_wait_time(state, bracket, rating)

        Logger.debug("Player #{player_name} joined #{bracket} solo arena queue (rating: #{rating})")
        {:reply, {:ok, estimated_wait}, state}
    end
  end

  def handle_call({:leave_queue, team_id}, _from, state) do
    case Map.get(state.team_queues, team_id) do
      nil ->
        {:reply, {:error, :not_in_queue}, state}

      {bracket, timer_ref} ->
        Process.cancel_timer(timer_ref)
        state = remove_from_queue(state, team_id, bracket)
        {:reply, :ok, state}
    end
  end

  def handle_call({:in_queue?, team_id}, _from, state) do
    in_queue = Map.has_key?(state.team_queues, team_id)
    {:reply, in_queue, state}
  end

  def handle_call({:get_queue_status, team_id}, _from, state) do
    case Map.get(state.team_queues, team_id) do
      nil ->
        {:reply, {:error, :not_in_queue}, state}

      {bracket, _timer_ref} ->
        queue = Map.get(state.queues, bracket, [])
        entry = Enum.find(queue, fn e -> e.team_id == team_id end)

        if entry do
          now = System.monotonic_time(:millisecond)
          wait_time = div(now - entry.queued_at, 1000)

          status = %{
            bracket: bracket,
            rating: entry.rating,
            rating_window: entry.rating_window,
            wait_time_seconds: wait_time,
            estimated_wait: estimate_wait_time(state, bracket, entry.rating),
            queue_size: length(queue)
          }

          {:reply, {:ok, status}, state}
        else
          {:reply, {:error, :not_in_queue}, state}
        end
    end
  end

  @impl true
  def handle_info(:check_queues, state) do
    state = check_and_pop_queues(state)
    schedule_queue_check()
    {:noreply, state}
  end

  def handle_info(:expand_rating_windows, state) do
    state = expand_all_rating_windows(state)
    schedule_rating_expansion()
    {:noreply, state}
  end

  def handle_info({:queue_timeout, team_id}, state) do
    case Map.get(state.team_queues, team_id) do
      nil ->
        {:noreply, state}

      {bracket, _timer_ref} ->
        Logger.debug("Team #{team_id} arena queue timeout")
        state = remove_from_queue(state, team_id, bracket)
        {:noreply, state}
    end
  end

  # Private functions

  defp schedule_queue_check do
    Process.send_after(self(), :check_queues, @queue_pop_check_interval)
  end

  defp schedule_rating_expansion do
    Process.send_after(self(), :expand_rating_windows, @rating_expand_interval)
  end

  defp add_to_queue(state, entry) do
    queue = Map.get(state.queues, entry.bracket, [])
    queue = queue ++ [entry]
    queues = Map.put(state.queues, entry.bracket, queue)

    timer_ref = Process.send_after(self(), {:queue_timeout, entry.team_id}, @max_queue_time_ms)
    team_queues = Map.put(state.team_queues, entry.team_id, {entry.bracket, timer_ref})

    %{state | queues: queues, team_queues: team_queues}
  end

  defp remove_from_queue(state, team_id, bracket) do
    queue = Map.get(state.queues, bracket, [])
    queue = Enum.reject(queue, fn e -> e.team_id == team_id end)
    queues = Map.put(state.queues, bracket, queue)

    team_queues = Map.delete(state.team_queues, team_id)

    %{state | queues: queues, team_queues: team_queues}
  end

  defp check_and_pop_queues(state) do
    Enum.reduce(state.queues, state, fn {bracket, queue}, acc_state ->
      check_and_pop_bracket(acc_state, bracket, queue)
    end)
  end

  defp check_and_pop_bracket(state, bracket, queue) do
    case find_match(queue) do
      {:ok, team1, team2, remaining_queue} ->
        match_id = create_arena_match(bracket, team1, team2)
        Logger.info("Created arena match #{match_id} for #{bracket} (#{team1.team_name} vs #{team2.team_name})")

        # Update queues
        queues = Map.put(state.queues, bracket, remaining_queue)

        # Remove teams from tracking
        team_queues =
          state.team_queues
          |> cancel_and_remove(team1.team_id)
          |> cancel_and_remove(team2.team_id)

        # Track active match
        active_matches = MapSet.put(state.active_matches, match_id)

        %{state | queues: queues, team_queues: team_queues, active_matches: active_matches}

      :no_match ->
        state
    end
  end

  defp find_match([]), do: :no_match
  defp find_match([_single]), do: :no_match

  defp find_match(queue) do
    # Try to find a match based on rating windows
    Enum.reduce_while(queue, :no_match, fn team1, acc ->
      case find_opponent(team1, queue -- [team1]) do
        {:ok, team2} ->
          remaining = queue -- [team1, team2]
          {:halt, {:ok, team1, team2, remaining}}

        :no_match ->
          {:cont, acc}
      end
    end)
  end

  defp find_opponent(team1, candidates) do
    # Find a team within rating window
    case Enum.find(candidates, fn team2 ->
           rating_diff = abs(team1.rating - team2.rating)
           rating_diff <= team1.rating_window and rating_diff <= team2.rating_window
         end) do
      nil -> :no_match
      team2 -> {:ok, team2}
    end
  end

  defp cancel_and_remove(team_queues, team_id) do
    case Map.get(team_queues, team_id) do
      {_, timer_ref} ->
        Process.cancel_timer(timer_ref)
        Map.delete(team_queues, team_id)

      nil ->
        team_queues
    end
  end

  defp expand_all_rating_windows(state) do
    queues =
      Enum.reduce(state.queues, %{}, fn {bracket, queue}, acc ->
        expanded_queue =
          Enum.map(queue, fn entry ->
            new_window = min(entry.rating_window + @rating_window_expansion, @rating_window_max)
            %{entry | rating_window: new_window}
          end)

        Map.put(acc, bracket, expanded_queue)
      end)

    %{state | queues: queues}
  end

  defp create_arena_match(bracket, team1, team2) do
    match_id = generate_match_id()

    case BezgelorWorld.PvP.ArenaInstance.start_instance(
           match_id,
           bracket,
           team1,
           team2
         ) do
      {:ok, _pid} ->
        match_id

      {:error, reason} ->
        Logger.error("Failed to start arena instance: #{inspect(reason)}")
        match_id
    end
  end

  defp estimate_wait_time(state, bracket, rating) do
    queue = Map.get(state.queues, bracket, [])

    # Count potential opponents within expanded window
    potential_opponents =
      Enum.count(queue, fn entry ->
        abs(entry.rating - rating) <= @rating_window_max
      end)

    cond do
      potential_opponents >= 1 ->
        # Likely to find match soon
        15

      true ->
        # Estimate based on queue activity
        60 + (30 * div(@rating_window_max, @initial_rating_window))
    end
  end

  defp get_team_member_guids(team) do
    Enum.map(team.members, fn m -> m.character_id end)
  end

  defp valid_bracket?(bracket) do
    bracket in ["2v2", "3v3", "5v5"]
  end

  defp bracket_size("2v2"), do: 2
  defp bracket_size("3v3"), do: 3
  defp bracket_size("5v5"), do: 5
  defp bracket_size(_), do: 0

  defp generate_match_id do
    Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end
end
