defmodule BezgelorDb.BattlegroundQueue do
  @moduledoc """
  Context module for battleground queue management.

  Provides functions for:
  - Adding/removing players from queue
  - Group queue handling
  - Queue statistics
  """

  import Ecto.Query

  alias BezgelorDb.Repo
  alias BezgelorDb.Schema.BattlegroundQueue

  @doc """
  Adds a player to the battleground queue.
  """
  @spec join_queue(map()) :: {:ok, BattlegroundQueue.t()} | {:error, Ecto.Changeset.t()}
  def join_queue(attrs) do
    attrs = Map.put(attrs, :queued_at, DateTime.utc_now())

    %BattlegroundQueue{}
    |> BattlegroundQueue.changeset(attrs)
    |> Repo.insert(on_conflict: :replace_all, conflict_target: :character_id)
  end

  @doc """
  Removes a player from the queue.
  """
  @spec leave_queue(integer()) :: {:ok, BattlegroundQueue.t()} | {:error, :not_in_queue}
  def leave_queue(character_id) do
    case get_queue_entry(character_id) do
      nil -> {:error, :not_in_queue}
      entry -> Repo.delete(entry)
    end
  end

  @doc """
  Gets a player's queue entry.
  """
  @spec get_queue_entry(integer()) :: BattlegroundQueue.t() | nil
  def get_queue_entry(character_id) do
    Repo.get_by(BattlegroundQueue, character_id: character_id)
  end

  @doc """
  Checks if a player is in queue.
  """
  @spec in_queue?(integer()) :: boolean()
  def in_queue?(character_id) do
    BattlegroundQueue
    |> where([q], q.character_id == ^character_id)
    |> Repo.exists?()
  end

  @doc """
  Gets all players in queue for a specific type.
  """
  @spec get_queue(String.t()) :: [BattlegroundQueue.t()]
  def get_queue(queue_type) do
    BattlegroundQueue
    |> where([q], q.queue_type == ^queue_type)
    |> order_by([q], asc: q.queued_at)
    |> Repo.all()
  end

  @doc """
  Gets players in queue for a specific battleground.
  """
  @spec get_queue_for_battleground(integer()) :: [BattlegroundQueue.t()]
  def get_queue_for_battleground(battleground_id) do
    BattlegroundQueue
    |> where([q], q.battleground_id == ^battleground_id or q.queue_type == "random")
    |> order_by([q], asc: q.queued_at)
    |> Repo.all()
  end

  @doc """
  Gets all group members in queue.
  """
  @spec get_group_queue(String.t()) :: [BattlegroundQueue.t()]
  def get_group_queue(group_id) do
    BattlegroundQueue
    |> where([q], q.group_id == ^group_id)
    |> order_by([q], asc: q.queued_at)
    |> Repo.all()
  end

  @doc """
  Updates estimated wait time for a player.
  """
  @spec update_estimate(integer(), integer()) :: {:ok, BattlegroundQueue.t()} | {:error, term()}
  def update_estimate(character_id, seconds) do
    case get_queue_entry(character_id) do
      nil ->
        {:error, :not_in_queue}

      entry ->
        entry
        |> BattlegroundQueue.update_estimate(seconds)
        |> Repo.update()
    end
  end

  @doc """
  Removes multiple players from queue (for match formation).
  """
  @spec remove_players([integer()]) :: {integer(), nil}
  def remove_players(character_ids) do
    BattlegroundQueue
    |> where([q], q.character_id in ^character_ids)
    |> Repo.delete_all()
  end

  @doc """
  Removes a group from queue.
  """
  @spec remove_group(String.t()) :: {integer(), nil}
  def remove_group(group_id) do
    BattlegroundQueue
    |> where([q], q.group_id == ^group_id)
    |> Repo.delete_all()
  end

  @doc """
  Gets queue statistics.
  """
  @spec get_queue_stats() :: map()
  def get_queue_stats do
    random_count =
      BattlegroundQueue
      |> where([q], q.queue_type == "random")
      |> Repo.aggregate(:count)

    specific_count =
      BattlegroundQueue
      |> where([q], q.queue_type == "specific")
      |> Repo.aggregate(:count)

    rated_count =
      BattlegroundQueue
      |> where([q], q.queue_type == "rated")
      |> Repo.aggregate(:count)

    avg_wait =
      BattlegroundQueue
      |> select([q], fragment("AVG(EXTRACT(EPOCH FROM NOW() - ?))", q.queued_at))
      |> Repo.one() || 0

    %{
      random: random_count,
      specific: specific_count,
      rated: rated_count,
      total: random_count + specific_count + rated_count,
      avg_wait_seconds: round(avg_wait)
    }
  end

  @doc """
  Gets queue count by role.
  """
  @spec get_role_counts(String.t()) :: map()
  def get_role_counts(queue_type) do
    BattlegroundQueue
    |> where([q], q.queue_type == ^queue_type)
    |> group_by([q], q.role)
    |> select([q], {q.role, count(q.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Finds eligible players for a match.

  Returns players sorted by queue time, respecting group constraints.
  """
  @spec find_eligible_players(String.t(), integer() | nil, integer()) :: [BattlegroundQueue.t()]
  def find_eligible_players(queue_type, battleground_id, limit) do
    query =
      BattlegroundQueue
      |> where([q], q.queue_type == ^queue_type or q.queue_type == "random")
      |> order_by([q], asc: q.queued_at)
      |> limit(^limit)

    query =
      if battleground_id do
        where(query, [q], is_nil(q.battleground_id) or q.battleground_id == ^battleground_id)
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Clears stale queue entries (older than specified minutes).
  """
  @spec clear_stale_entries(integer()) :: {integer(), nil}
  def clear_stale_entries(max_age_minutes \\ 60) do
    cutoff = DateTime.add(DateTime.utc_now(), -max_age_minutes * 60, :second)

    BattlegroundQueue
    |> where([q], q.queued_at < ^cutoff)
    |> Repo.delete_all()
  end

  @doc """
  Gets the longest wait time in queue.
  """
  @spec longest_wait_seconds(String.t()) :: integer()
  def longest_wait_seconds(queue_type) do
    oldest =
      BattlegroundQueue
      |> where([q], q.queue_type == ^queue_type)
      |> order_by([q], asc: q.queued_at)
      |> limit(1)
      |> select([q], q.queued_at)
      |> Repo.one()

    case oldest do
      nil -> 0
      queued_at -> DateTime.diff(DateTime.utc_now(), queued_at, :second)
    end
  end
end
