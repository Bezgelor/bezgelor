defmodule BezgelorDb.Instances do
  @moduledoc """
  Context for instance-related database operations.

  Handles instance saves, completions, mythic runs, and related queries.
  """

  import Ecto.Query
  alias BezgelorDb.Repo
  alias BezgelorDb.Schema.{InstanceSave, InstanceCompletion, MythicRun, MythicKeystone, LootHistory}

  # ============================================================================
  # Instance Saves
  # ============================================================================

  @doc """
  Get or create an instance save by GUID.
  """
  @spec get_or_create_save(binary(), integer(), String.t()) ::
          {:ok, InstanceSave.t()} | {:error, Ecto.Changeset.t()}
  def get_or_create_save(instance_guid, definition_id, difficulty) do
    case get_save(instance_guid) do
      nil -> create_save(instance_guid, definition_id, difficulty)
      save -> {:ok, save}
    end
  end

  @doc """
  Get an instance save by GUID.
  """
  @spec get_save(binary()) :: InstanceSave.t() | nil
  def get_save(instance_guid) do
    Repo.get_by(InstanceSave, instance_guid: instance_guid)
  end

  @doc """
  Create a new instance save.
  """
  @spec create_save(binary(), integer(), String.t()) ::
          {:ok, InstanceSave.t()} | {:error, Ecto.Changeset.t()}
  def create_save(instance_guid, definition_id, difficulty) do
    now = DateTime.utc_now()
    expires_at = calculate_next_weekly_reset(now)

    %InstanceSave{}
    |> InstanceSave.changeset(%{
      instance_guid: instance_guid,
      instance_definition_id: definition_id,
      difficulty: difficulty,
      created_at: now,
      expires_at: expires_at
    })
    |> Repo.insert()
  end

  @doc """
  Record a boss kill in an instance save.
  """
  @spec record_boss_kill(binary(), integer()) :: {:ok, InstanceSave.t()} | {:error, term()}
  def record_boss_kill(instance_guid, boss_id) do
    case get_save(instance_guid) do
      nil ->
        {:error, :save_not_found}

      save ->
        save
        |> InstanceSave.record_boss_kill(boss_id)
        |> Repo.update()
    end
  end

  @doc """
  Delete expired saves.
  """
  @spec cleanup_expired_saves() :: {integer(), nil}
  def cleanup_expired_saves do
    now = DateTime.utc_now()

    from(s in InstanceSave, where: s.expires_at < ^now)
    |> Repo.delete_all()
  end

  # ============================================================================
  # Instance Completions
  # ============================================================================

  @doc """
  Record an instance completion.
  """
  @spec record_completion(map()) :: {:ok, InstanceCompletion.t()} | {:error, Ecto.Changeset.t()}
  def record_completion(attrs) do
    %InstanceCompletion{}
    |> InstanceCompletion.changeset(Map.put(attrs, :completed_at, DateTime.utc_now()))
    |> Repo.insert()
  end

  @doc """
  Get completion count for a character/instance.
  """
  @spec get_completion_count(integer(), integer(), String.t()) :: integer()
  def get_completion_count(character_id, instance_id, difficulty) do
    from(c in InstanceCompletion,
      where:
        c.character_id == ^character_id and
          c.instance_definition_id == ^instance_id and
          c.difficulty == ^difficulty,
      select: count(c.id)
    )
    |> Repo.one()
  end

  @doc """
  Get completion rate for a character (for smart matching).
  """
  @spec get_completion_rate(integer()) :: float()
  def get_completion_rate(character_id) do
    total =
      from(c in InstanceCompletion, where: c.character_id == ^character_id, select: count(c.id))
      |> Repo.one()

    # Simplified - in production would track abandons separately
    if total == 0, do: 1.0, else: 1.0
  end

  @doc """
  Get recent completions for a character.
  """
  @spec get_recent_completions(integer(), integer()) :: [InstanceCompletion.t()]
  def get_recent_completions(character_id, limit \\ 10) do
    from(c in InstanceCompletion,
      where: c.character_id == ^character_id,
      order_by: [desc: c.completed_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc """
  Get completions for a specific instance.
  """
  @spec get_instance_completions(integer(), String.t(), integer()) :: [InstanceCompletion.t()]
  def get_instance_completions(instance_id, difficulty, limit \\ 100) do
    from(c in InstanceCompletion,
      where: c.instance_definition_id == ^instance_id and c.difficulty == ^difficulty,
      order_by: [desc: c.completed_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  # ============================================================================
  # Mythic+ Runs (Leaderboards)
  # ============================================================================

  @doc """
  Record a mythic+ run.
  """
  @spec record_mythic_run(map()) :: {:ok, MythicRun.t()} | {:error, Ecto.Changeset.t()}
  def record_mythic_run(attrs) do
    %MythicRun{}
    |> MythicRun.changeset(Map.put(attrs, :completed_at, DateTime.utc_now()))
    |> Repo.insert()
  end

  @doc """
  Get best mythic+ times for leaderboard.
  """
  @spec get_leaderboard(integer(), integer(), integer()) :: [MythicRun.t()]
  def get_leaderboard(instance_id, level, limit \\ 100) do
    from(r in MythicRun,
      where: r.instance_definition_id == ^instance_id and r.level == ^level and r.timed == true,
      order_by: [asc: r.duration_seconds],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc """
  Get leaderboard for current season.
  """
  @spec get_season_leaderboard(integer(), integer(), integer(), integer()) :: [MythicRun.t()]
  def get_season_leaderboard(instance_id, level, season, limit \\ 100) do
    from(r in MythicRun,
      where:
        r.instance_definition_id == ^instance_id and
          r.level == ^level and
          r.season == ^season and
          r.timed == true,
      order_by: [asc: r.duration_seconds],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc """
  Get a player's best runs for the season.
  """
  @spec get_player_best_runs(integer(), integer(), integer()) :: [MythicRun.t()]
  def get_player_best_runs(character_id, season, limit \\ 10) do
    from(r in MythicRun,
      where: ^character_id in r.member_ids and r.season == ^season and r.timed == true,
      order_by: [desc: r.level, asc: r.duration_seconds],
      limit: ^limit
    )
    |> Repo.all()
  end

  # ============================================================================
  # Mythic Keystones
  # ============================================================================

  @doc """
  Get a character's keystone.
  """
  @spec get_keystone(integer()) :: MythicKeystone.t() | nil
  def get_keystone(character_id) do
    from(k in MythicKeystone,
      where: k.character_id == ^character_id,
      order_by: [desc: k.obtained_at],
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Grant a new keystone to a character.
  """
  @spec grant_keystone(integer(), integer(), integer(), [String.t()]) ::
          {:ok, MythicKeystone.t()} | {:error, Ecto.Changeset.t()}
  def grant_keystone(character_id, instance_id, level, affixes \\ []) do
    %MythicKeystone{}
    |> MythicKeystone.changeset(%{
      character_id: character_id,
      instance_definition_id: instance_id,
      level: level,
      affixes: affixes,
      obtained_at: DateTime.utc_now()
    })
    |> Repo.insert()
  end

  @doc """
  Upgrade a character's keystone.
  """
  @spec upgrade_keystone(integer(), integer()) :: {:ok, MythicKeystone.t()} | {:error, term()}
  def upgrade_keystone(character_id, levels) do
    case get_keystone(character_id) do
      nil ->
        {:error, :no_keystone}

      keystone ->
        keystone
        |> MythicKeystone.upgrade(levels)
        |> Repo.update()
    end
  end

  @doc """
  Deplete a character's keystone (failed timer).
  """
  @spec deplete_keystone(integer()) :: {:ok, MythicKeystone.t()} | {:error, term()}
  def deplete_keystone(character_id) do
    case get_keystone(character_id) do
      nil ->
        {:error, :no_keystone}

      keystone ->
        keystone
        |> MythicKeystone.deplete()
        |> Repo.update()
    end
  end

  # ============================================================================
  # Loot History
  # ============================================================================

  @doc """
  Record a loot drop.
  """
  @spec record_loot(map()) :: {:ok, LootHistory.t()} | {:error, Ecto.Changeset.t()}
  def record_loot(attrs) do
    LootHistory.record_drop(attrs)
    |> Repo.insert()
  end

  @doc """
  Get loot history for an instance.
  """
  @spec get_instance_loot(binary()) :: [LootHistory.t()]
  def get_instance_loot(instance_guid) do
    from(l in LootHistory,
      where: l.instance_guid == ^instance_guid,
      order_by: [desc: l.awarded_at]
    )
    |> Repo.all()
  end

  @doc """
  Get loot history for a character.
  """
  @spec get_character_loot(integer(), integer()) :: [LootHistory.t()]
  def get_character_loot(character_id, limit \\ 100) do
    from(l in LootHistory,
      where: l.character_id == ^character_id,
      order_by: [desc: l.awarded_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  @doc """
  Calculate the next weekly reset (Tuesday 10:00 AM).
  """
  @spec calculate_next_weekly_reset(DateTime.t()) :: DateTime.t()
  def calculate_next_weekly_reset(now) do
    # Tuesday is day 2 in Elixir (Monday = 1)
    current_day = Date.day_of_week(now)
    days_until_tuesday = rem(9 - current_day, 7)

    # If it's Tuesday but after 10 AM, go to next Tuesday
    days_until_tuesday =
      if days_until_tuesday == 0 and now.hour >= 10, do: 7, else: days_until_tuesday

    # Handle edge case where it's exactly 0 days and before 10 AM
    days_until_tuesday = if days_until_tuesday == 0, do: 0, else: days_until_tuesday

    reset_date = Date.add(DateTime.to_date(now), days_until_tuesday)

    DateTime.new!(reset_date, ~T[10:00:00], "Etc/UTC")
  end

  @doc """
  Calculate daily reset time (typically 10:00 AM UTC).
  """
  @spec calculate_next_daily_reset(DateTime.t()) :: DateTime.t()
  def calculate_next_daily_reset(now) do
    reset_time = ~T[10:00:00]

    if Time.compare(DateTime.to_time(now), reset_time) == :lt do
      # Before reset today
      DateTime.new!(DateTime.to_date(now), reset_time, "Etc/UTC")
    else
      # After reset, go to tomorrow
      tomorrow = Date.add(DateTime.to_date(now), 1)
      DateTime.new!(tomorrow, reset_time, "Etc/UTC")
    end
  end
end
