defmodule BezgelorDb.GroupFinder do
  @moduledoc """
  Context for group finder queue and group operations.
  """

  import Ecto.Query
  alias BezgelorDb.Repo
  alias BezgelorDb.Schema.{GroupFinderQueue, GroupFinderGroup}

  # ============================================================================
  # Queue Operations
  # ============================================================================

  @doc """
  Add a player to the queue.
  """
  @spec enqueue(map()) :: {:ok, GroupFinderQueue.t()} | {:error, Ecto.Changeset.t()}
  def enqueue(attrs) do
    attrs = Map.put(attrs, :queued_at, DateTime.utc_now())

    %GroupFinderQueue{}
    |> GroupFinderQueue.changeset(attrs)
    |> Repo.insert(on_conflict: :replace_all, conflict_target: :character_id)
  end

  @doc """
  Remove a player from the queue.
  """
  @spec dequeue(integer()) :: {:ok, GroupFinderQueue.t()} | {:error, :not_found}
  def dequeue(character_id) do
    case Repo.get_by(GroupFinderQueue, character_id: character_id) do
      nil ->
        {:error, :not_found}

      entry ->
        Repo.delete(entry)
        {:ok, entry}
    end
  end

  @doc """
  Get queue entry for a character.
  """
  @spec get_queue_entry(integer()) :: GroupFinderQueue.t() | nil
  def get_queue_entry(character_id) do
    Repo.get_by(GroupFinderQueue, character_id: character_id)
  end

  @doc """
  Check if character is in queue.
  """
  @spec in_queue?(integer()) :: boolean()
  def in_queue?(character_id) do
    get_queue_entry(character_id) != nil
  end

  @doc """
  Get queued players for an instance type, difficulty, and role.
  """
  @spec get_queued_for_role(String.t(), String.t(), String.t(), integer()) :: [GroupFinderQueue.t()]
  def get_queued_for_role(instance_type, difficulty, role, limit \\ 100) do
    from(q in GroupFinderQueue,
      where:
        q.instance_type == ^instance_type and
          q.difficulty == ^difficulty and
          q.role == ^role,
      order_by: [asc: q.queued_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc """
  Get all queued players for a specific instance.
  """
  @spec get_queued_for_instance(integer(), String.t()) :: [GroupFinderQueue.t()]
  def get_queued_for_instance(instance_id, difficulty) do
    from(q in GroupFinderQueue,
      where: ^instance_id in q.instance_ids and q.difficulty == ^difficulty,
      order_by: [asc: q.queued_at]
    )
    |> Repo.all()
  end

  @doc """
  Get queue statistics for an instance type and difficulty.
  """
  @spec get_queue_stats(String.t(), String.t()) :: map()
  def get_queue_stats(instance_type, difficulty) do
    tanks =
      from(q in GroupFinderQueue,
        where: q.instance_type == ^instance_type and q.difficulty == ^difficulty and q.role == "tank",
        select: count(q.id)
      )
      |> Repo.one()

    healers =
      from(q in GroupFinderQueue,
        where: q.instance_type == ^instance_type and q.difficulty == ^difficulty and q.role == "healer",
        select: count(q.id)
      )
      |> Repo.one()

    dps =
      from(q in GroupFinderQueue,
        where: q.instance_type == ^instance_type and q.difficulty == ^difficulty and q.role == "dps",
        select: count(q.id)
      )
      |> Repo.one()

    %{
      tanks: tanks,
      healers: healers,
      dps: dps,
      total: tanks + healers + dps
    }
  end

  @doc """
  Update queue wait time estimate.
  """
  @spec update_wait_estimate(integer(), integer()) :: {:ok, GroupFinderQueue.t()} | {:error, term()}
  def update_wait_estimate(character_id, seconds) do
    case get_queue_entry(character_id) do
      nil ->
        {:error, :not_found}

      entry ->
        entry
        |> GroupFinderQueue.update_estimate(seconds)
        |> Repo.update()
    end
  end

  @doc """
  Remove multiple characters from queue (batch operation for group formation).
  """
  @spec dequeue_multiple([integer()]) :: {integer(), nil}
  def dequeue_multiple(character_ids) do
    from(q in GroupFinderQueue, where: q.character_id in ^character_ids)
    |> Repo.delete_all()
  end

  # ============================================================================
  # Group Operations
  # ============================================================================

  @doc """
  Create a formed group.
  """
  @spec create_group(map()) :: {:ok, GroupFinderGroup.t()} | {:error, Ecto.Changeset.t()}
  def create_group(attrs) do
    attrs = Map.put_new(attrs, :group_guid, generate_guid())

    %GroupFinderGroup{}
    |> GroupFinderGroup.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Get a group by GUID.
  """
  @spec get_group(binary()) :: GroupFinderGroup.t() | nil
  def get_group(group_guid) do
    Repo.get_by(GroupFinderGroup, group_guid: group_guid)
  end

  @doc """
  Get group for a character.
  """
  @spec get_group_for_character(integer()) :: GroupFinderGroup.t() | nil
  def get_group_for_character(character_id) do
    from(g in GroupFinderGroup,
      where: ^character_id in g.member_ids and g.status != "disbanded"
    )
    |> Repo.one()
  end

  @doc """
  Set player ready status.
  """
  @spec set_ready(binary(), integer(), boolean()) :: {:ok, GroupFinderGroup.t()} | {:error, term()}
  def set_ready(group_guid, character_id, ready) do
    case get_group(group_guid) do
      nil ->
        {:error, :group_not_found}

      group ->
        group
        |> GroupFinderGroup.set_ready(character_id, ready)
        |> Repo.update()
    end
  end

  @doc """
  Update group status.
  """
  @spec set_group_status(binary(), String.t()) :: {:ok, GroupFinderGroup.t()} | {:error, term()}
  def set_group_status(group_guid, status) do
    case get_group(group_guid) do
      nil ->
        {:error, :group_not_found}

      group ->
        group
        |> GroupFinderGroup.set_status(status)
        |> Repo.update()
    end
  end

  @doc """
  Disband a group and optionally return members to queue.
  """
  @spec disband_group(binary(), boolean()) :: :ok | {:error, term()}
  def disband_group(group_guid, _requeue_members \\ false) do
    case get_group(group_guid) do
      nil ->
        {:error, :group_not_found}

      group ->
        # Note: Requeueing would need to store original queue settings
        # For now, just disband
        group
        |> GroupFinderGroup.set_status("disbanded")
        |> Repo.update()

        :ok
    end
  end

  @doc """
  Get all active groups (not disbanded).
  """
  @spec get_active_groups() :: [GroupFinderGroup.t()]
  def get_active_groups do
    from(g in GroupFinderGroup, where: g.status != "disbanded")
    |> Repo.all()
  end

  @doc """
  Get groups waiting for ready check.
  """
  @spec get_groups_awaiting_ready() :: [GroupFinderGroup.t()]
  def get_groups_awaiting_ready do
    from(g in GroupFinderGroup, where: g.status == "forming")
    |> Repo.all()
  end

  @doc """
  Cleanup old disbanded/expired groups.
  """
  @spec cleanup_groups() :: {integer(), nil}
  def cleanup_groups do
    cutoff = DateTime.add(DateTime.utc_now(), -3600, :second)

    from(g in GroupFinderGroup,
      where:
        g.status == "disbanded" or
          (not is_nil(g.expires_at) and g.expires_at < ^DateTime.utc_now()) or
          g.inserted_at < ^cutoff
    )
    |> Repo.delete_all()
  end

  # ============================================================================
  # Matching Helpers
  # ============================================================================

  @doc """
  Get candidates for forming a group.
  Returns queued players grouped by role.
  """
  @spec get_matching_candidates(String.t(), String.t(), [integer()]) :: map()
  def get_matching_candidates(instance_type, difficulty, instance_ids) do
    base_query =
      from(q in GroupFinderQueue,
        where:
          q.instance_type == ^instance_type and
            q.difficulty == ^difficulty,
        order_by: [asc: q.queued_at]
      )

    # Filter to players who want at least one of these instances
    filtered =
      Enum.reduce(instance_ids, base_query, fn instance_id, query ->
        from(q in query, or_where: ^instance_id in q.instance_ids)
      end)

    players = Repo.all(filtered)

    %{
      tanks: Enum.filter(players, &GroupFinderQueue.tank?/1),
      healers: Enum.filter(players, &GroupFinderQueue.healer?/1),
      dps: Enum.filter(players, &GroupFinderQueue.dps?/1)
    }
  end

  @doc """
  Find a common instance that all candidates want.
  """
  @spec find_common_instance([GroupFinderQueue.t()]) :: integer() | nil
  def find_common_instance([]), do: nil

  def find_common_instance([first | rest]) do
    first.instance_ids
    |> Enum.find(fn instance_id ->
      Enum.all?(rest, fn entry -> GroupFinderQueue.wants_instance?(entry, instance_id) end)
    end)
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp generate_guid do
    :crypto.strong_rand_bytes(16)
  end
end
