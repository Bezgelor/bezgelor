defmodule BezgelorDb.Lockouts do
  @moduledoc """
  Context for instance lockout management.

  Handles checking, creating, and managing lockouts for all content types:
  - Instance lockouts: Full instance reentry restriction
  - Encounter lockouts: Per-boss kill tracking
  - Loot lockouts: Loot eligibility separate from entry
  - Soft lockouts: Diminishing returns for repeated runs
  """

  import Ecto.Query
  alias BezgelorDb.Repo
  alias BezgelorDb.Schema.InstanceLockout

  # ============================================================================
  # Lockout Checks
  # ============================================================================

  @doc """
  Check if character is locked out of an instance.
  """
  @spec locked_out?(integer(), integer(), String.t()) :: boolean()
  def locked_out?(character_id, instance_id, difficulty) do
    case get_lockout(character_id, instance_id, difficulty) do
      nil -> false
      lockout -> not InstanceLockout.expired?(lockout)
    end
  end

  @doc """
  Get lockout for character/instance/difficulty.
  """
  @spec get_lockout(integer(), integer(), String.t()) :: InstanceLockout.t() | nil
  def get_lockout(character_id, instance_id, difficulty) do
    from(l in InstanceLockout,
      where:
        l.character_id == ^character_id and
          l.instance_definition_id == ^instance_id and
          l.difficulty == ^difficulty and
          l.expires_at > ^DateTime.utc_now()
    )
    |> Repo.one()
  end

  @doc """
  Get all active lockouts for a character.
  """
  @spec get_character_lockouts(integer()) :: [InstanceLockout.t()]
  def get_character_lockouts(character_id) do
    from(l in InstanceLockout,
      where: l.character_id == ^character_id and l.expires_at > ^DateTime.utc_now(),
      order_by: [asc: l.expires_at]
    )
    |> Repo.all()
  end

  @doc """
  Get lockouts by instance type.
  """
  @spec get_lockouts_by_type(integer(), String.t()) :: [InstanceLockout.t()]
  def get_lockouts_by_type(character_id, instance_type) do
    from(l in InstanceLockout,
      where:
        l.character_id == ^character_id and
          l.instance_type == ^instance_type and
          l.expires_at > ^DateTime.utc_now(),
      order_by: [asc: l.expires_at]
    )
    |> Repo.all()
  end

  # ============================================================================
  # Lockout Creation/Update
  # ============================================================================

  @doc """
  Create or update a lockout.
  """
  @spec create_or_update_lockout(map()) ::
          {:ok, InstanceLockout.t()} | {:error, Ecto.Changeset.t()}
  def create_or_update_lockout(attrs) do
    case get_lockout(attrs.character_id, attrs.instance_definition_id, attrs.difficulty) do
      nil ->
        %InstanceLockout{}
        |> InstanceLockout.changeset(attrs)
        |> Repo.insert()

      existing ->
        existing
        |> InstanceLockout.changeset(attrs)
        |> Repo.update()
    end
  end

  @doc """
  Create a new lockout with calculated expiry.
  """
  @spec create_lockout(integer(), String.t(), integer(), String.t()) ::
          {:ok, InstanceLockout.t()} | {:error, Ecto.Changeset.t()}
  def create_lockout(character_id, instance_type, instance_id, difficulty) do
    expires_at = calculate_expiry(instance_type, difficulty)

    create_or_update_lockout(%{
      character_id: character_id,
      instance_type: instance_type,
      instance_definition_id: instance_id,
      difficulty: difficulty,
      expires_at: expires_at
    })
  end

  # ============================================================================
  # Boss Kill Tracking
  # ============================================================================

  @doc """
  Record a boss kill in a lockout.
  """
  @spec record_boss_kill(integer(), integer(), String.t(), integer()) ::
          {:ok, InstanceLockout.t()} | {:error, term()}
  def record_boss_kill(character_id, instance_id, difficulty, boss_id) do
    case get_lockout(character_id, instance_id, difficulty) do
      nil ->
        {:error, :no_lockout}

      lockout ->
        lockout
        |> InstanceLockout.record_boss_kill(boss_id)
        |> Repo.update()
    end
  end

  @doc """
  Check if a specific boss has been killed.
  """
  @spec boss_killed?(integer(), integer(), String.t(), integer()) :: boolean()
  def boss_killed?(character_id, instance_id, difficulty, boss_id) do
    case get_lockout(character_id, instance_id, difficulty) do
      nil -> false
      lockout -> InstanceLockout.boss_killed?(lockout, boss_id)
    end
  end

  @doc """
  Get list of killed bosses for a lockout.
  """
  @spec get_killed_bosses(integer(), integer(), String.t()) :: [integer()]
  def get_killed_bosses(character_id, instance_id, difficulty) do
    case get_lockout(character_id, instance_id, difficulty) do
      nil -> []
      lockout -> lockout.boss_kills
    end
  end

  # ============================================================================
  # Loot Eligibility
  # ============================================================================

  @doc """
  Mark loot as received (for loot lockouts).
  """
  @spec mark_loot_received(integer(), integer(), String.t()) ::
          {:ok, InstanceLockout.t()} | {:error, term()}
  def mark_loot_received(character_id, instance_id, difficulty) do
    case get_lockout(character_id, instance_id, difficulty) do
      nil ->
        {:error, :no_lockout}

      lockout ->
        lockout
        |> InstanceLockout.record_loot_received()
        |> Repo.update()
    end
  end

  @doc """
  Check if character is eligible for loot.
  """
  @spec loot_eligible?(integer(), integer(), String.t()) :: boolean()
  def loot_eligible?(character_id, instance_id, difficulty) do
    case get_lockout(character_id, instance_id, difficulty) do
      nil -> true
      lockout -> lockout.loot_eligible
    end
  end

  # ============================================================================
  # Soft Lockouts (Diminishing Returns)
  # ============================================================================

  @doc """
  Increment completion count (for soft lockouts).
  """
  @spec increment_completion(integer(), integer(), String.t()) ::
          {:ok, InstanceLockout.t()} | {:error, term()}
  def increment_completion(character_id, instance_id, difficulty) do
    case get_lockout(character_id, instance_id, difficulty) do
      nil ->
        {:error, :no_lockout}

      lockout ->
        config = get_lockout_config(lockout.instance_type)
        new_count = lockout.completion_count + 1

        new_factor =
          if new_count > Map.get(config, :diminishing_start, 5) do
            max(lockout.diminishing_factor * Map.get(config, :diminishing_factor, 0.8), 0.1)
          else
            lockout.diminishing_factor
          end

        lockout
        |> Ecto.Changeset.change(completion_count: new_count, diminishing_factor: new_factor)
        |> Repo.update()
    end
  end

  @doc """
  Get diminishing returns factor for rewards.
  """
  @spec get_reward_factor(integer(), integer(), String.t()) :: float()
  def get_reward_factor(character_id, instance_id, difficulty) do
    case get_lockout(character_id, instance_id, difficulty) do
      nil -> 1.0
      lockout -> lockout.diminishing_factor
    end
  end

  # ============================================================================
  # Lockout Extension
  # ============================================================================

  @doc """
  Extend a lockout (player choice to keep save).
  """
  @spec extend_lockout(integer(), integer(), String.t()) ::
          {:ok, InstanceLockout.t()} | {:error, term()}
  def extend_lockout(character_id, instance_id, difficulty) do
    case get_lockout(character_id, instance_id, difficulty) do
      nil ->
        {:error, :no_lockout}

      lockout ->
        # Add another week
        new_expires = DateTime.add(lockout.expires_at, 7 * 24 * 60 * 60, :second)

        lockout
        |> Ecto.Changeset.change(expires_at: new_expires, extended: true)
        |> Repo.update()
    end
  end

  @doc """
  Check if a lockout has been extended.
  """
  @spec extended?(integer(), integer(), String.t()) :: boolean()
  def extended?(character_id, instance_id, difficulty) do
    case get_lockout(character_id, instance_id, difficulty) do
      nil -> false
      lockout -> lockout.extended
    end
  end

  # ============================================================================
  # Raid Save Linking
  # ============================================================================

  @doc """
  Link a lockout to a raid instance GUID.
  """
  @spec link_to_instance(integer(), integer(), String.t(), binary()) ::
          {:ok, InstanceLockout.t()} | {:error, term()}
  def link_to_instance(character_id, instance_id, difficulty, instance_guid) do
    case get_lockout(character_id, instance_id, difficulty) do
      nil ->
        {:error, :no_lockout}

      lockout ->
        lockout
        |> Ecto.Changeset.change(instance_guid: instance_guid)
        |> Repo.update()
    end
  end

  @doc """
  Get all characters linked to a raid instance.
  """
  @spec get_characters_for_instance(binary()) :: [integer()]
  def get_characters_for_instance(instance_guid) do
    from(l in InstanceLockout,
      where: l.instance_guid == ^instance_guid and l.expires_at > ^DateTime.utc_now(),
      select: l.character_id
    )
    |> Repo.all()
  end

  # ============================================================================
  # Cleanup
  # ============================================================================

  @doc """
  Cleanup expired lockouts.
  """
  @spec cleanup_expired() :: {integer(), nil}
  def cleanup_expired do
    from(l in InstanceLockout, where: l.expires_at < ^DateTime.utc_now())
    |> Repo.delete_all()
  end

  @doc """
  Reset all lockouts for a character (admin function).
  """
  @spec reset_character_lockouts(integer()) :: {integer(), nil}
  def reset_character_lockouts(character_id) do
    from(l in InstanceLockout, where: l.character_id == ^character_id)
    |> Repo.delete_all()
  end

  @doc """
  Reset a specific lockout by ID (admin function).
  """
  @spec reset_lockout(integer()) :: {:ok, InstanceLockout.t()} | {:error, :not_found}
  def reset_lockout(lockout_id) do
    case Repo.get(InstanceLockout, lockout_id) do
      nil -> {:error, :not_found}
      lockout -> Repo.delete(lockout)
    end
  end

  @doc """
  Get a lockout by ID.
  """
  @spec get_lockout_by_id(integer()) :: InstanceLockout.t() | nil
  def get_lockout_by_id(lockout_id) do
    Repo.get(InstanceLockout, lockout_id)
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp get_lockout_config(instance_type) do
    Application.get_env(:bezgelor_world, :lockouts, %{})
    |> Map.get(:rules, %{})
    |> Map.get(String.to_atom(instance_type), %{})
  end

  defp calculate_expiry(instance_type, difficulty) do
    now = DateTime.utc_now()
    config = get_lockout_config(instance_type)

    case {instance_type, difficulty} do
      {"raid", _} ->
        # Raids reset weekly
        BezgelorDb.Instances.calculate_next_weekly_reset(now)

      {"dungeon", "mythic_plus"} ->
        # Mythic+ soft lockouts reset daily
        BezgelorDb.Instances.calculate_next_daily_reset(now)

      {"dungeon", _} ->
        # Normal/Veteran dungeons - configurable or instant reset
        duration = Map.get(config, :duration_seconds, 0)

        if duration > 0 do
          DateTime.add(now, duration, :second)
        else
          # No lockout
          now
        end

      {"expedition", _} ->
        # Expeditions - usually daily
        BezgelorDb.Instances.calculate_next_daily_reset(now)

      {"adventure", _} ->
        # Adventures - usually daily
        BezgelorDb.Instances.calculate_next_daily_reset(now)

      _ ->
        # Default to daily
        BezgelorDb.Instances.calculate_next_daily_reset(now)
    end
  end
end
