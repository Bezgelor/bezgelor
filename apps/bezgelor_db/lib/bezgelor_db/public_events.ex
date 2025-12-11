defmodule BezgelorDb.PublicEvents do
  @moduledoc """
  Public events management context.

  Handles event instances, participation tracking, contributions,
  scheduling, and completion history.
  """

  import Ecto.Query
  alias BezgelorDb.Repo
  alias BezgelorDb.Schema.{EventInstance, EventParticipation, EventCompletion, EventSchedule, WorldBossSpawn}

  # ============================================================================
  # Event Instance Management
  # ============================================================================

  @doc "Get an event instance by ID."
  def get_event_instance(instance_id) do
    Repo.get(EventInstance, instance_id)
  end

  @doc "Get an event instance with participations preloaded."
  def get_event_instance_with_participations(instance_id) do
    EventInstance
    |> where([e], e.id == ^instance_id)
    |> preload(:participations)
    |> Repo.one()
  end

  @doc "Get all active events in a zone."
  def get_active_events(zone_id, instance_id \\ 1) do
    EventInstance
    |> where([e], e.zone_id == ^zone_id and e.instance_id == ^instance_id)
    |> where([e], e.state == :active)
    |> order_by([e], asc: e.started_at)
    |> Repo.all()
  end

  @doc "Get all events in a zone (any state)."
  def get_zone_events(zone_id, instance_id \\ 1) do
    EventInstance
    |> where([e], e.zone_id == ^zone_id and e.instance_id == ^instance_id)
    |> where([e], e.state in [:pending, :active])
    |> order_by([e], asc: e.inserted_at)
    |> Repo.all()
  end

  @doc "Create a new event instance."
  def create_event_instance(event_id, zone_id, instance_id \\ 1) do
    %EventInstance{}
    |> EventInstance.changeset(%{
      event_id: event_id,
      zone_id: zone_id,
      instance_id: instance_id
    })
    |> Repo.insert()
  end

  @doc "Start a pending event."
  def start_event(instance_id, duration_ms) do
    case get_event_instance(instance_id) do
      nil ->
        {:error, :not_found}

      %{state: :pending} = instance ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)
        ends_at = DateTime.add(now, duration_ms, :millisecond) |> DateTime.truncate(:second)

        instance
        |> EventInstance.start_changeset(now, ends_at)
        |> Repo.update()

      _other ->
        {:error, :invalid_state}
    end
  end

  @doc "Complete an event successfully."
  def complete_event(instance_id) do
    case get_event_instance(instance_id) do
      nil ->
        {:error, :not_found}

      %{state: :active} = instance ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        instance
        |> EventInstance.complete_changeset(now)
        |> Repo.update()

      _other ->
        {:error, :invalid_state}
    end
  end

  @doc "Fail an event."
  def fail_event(instance_id) do
    case get_event_instance(instance_id) do
      nil ->
        {:error, :not_found}

      %{state: :active} = instance ->
        instance
        |> EventInstance.fail_changeset()
        |> Repo.update()

      _other ->
        {:error, :invalid_state}
    end
  end

  @doc "Cancel an event."
  def cancel_event(instance_id) do
    case get_event_instance(instance_id) do
      nil ->
        {:error, :not_found}

      %{state: state} = instance when state in [:pending, :active] ->
        instance
        |> EventInstance.cancel_changeset()
        |> Repo.update()

      _other ->
        {:error, :invalid_state}
    end
  end

  @doc "Advance to next phase."
  def advance_phase(instance_id, new_phase, initial_progress) do
    case get_event_instance(instance_id) do
      nil ->
        {:error, :not_found}

      instance ->
        instance
        |> EventInstance.advance_phase_changeset(new_phase, initial_progress)
        |> Repo.update()
    end
  end

  @doc "Advance to next wave."
  def advance_wave(instance_id, new_wave) do
    case get_event_instance(instance_id) do
      nil ->
        {:error, :not_found}

      instance ->
        instance
        |> EventInstance.advance_wave_changeset(new_wave)
        |> Repo.update()
    end
  end

  @doc "Update phase progress."
  def update_progress(instance_id, progress) do
    case get_event_instance(instance_id) do
      nil ->
        {:error, :not_found}

      instance ->
        instance
        |> EventInstance.progress_changeset(progress)
        |> Repo.update()
    end
  end

  @doc "Update participant count."
  def update_participant_count(instance_id) do
    count =
      EventParticipation
      |> where([p], p.event_instance_id == ^instance_id)
      |> Repo.aggregate(:count)

    case get_event_instance(instance_id) do
      nil ->
        {:error, :not_found}

      instance ->
        instance
        |> EventInstance.participant_changeset(count)
        |> Repo.update()
    end
  end

  @doc "Update difficulty multiplier based on participant count."
  def update_difficulty(instance_id, participant_count) do
    multiplier = calculate_difficulty_multiplier(participant_count)

    case get_event_instance(instance_id) do
      nil ->
        {:error, :not_found}

      instance ->
        instance
        |> EventInstance.difficulty_changeset(multiplier)
        |> Repo.update()
    end
  end

  defp calculate_difficulty_multiplier(count) when count <= 10, do: 1.0
  defp calculate_difficulty_multiplier(count) when count <= 25, do: 1.5
  defp calculate_difficulty_multiplier(count) when count <= 50, do: 2.0
  defp calculate_difficulty_multiplier(_count), do: 2.5

  # ============================================================================
  # Participation Management
  # ============================================================================

  @doc "Get participation record."
  def get_participation(instance_id, character_id) do
    Repo.get_by(EventParticipation, event_instance_id: instance_id, character_id: character_id)
  end

  @doc "Get all participations for an event, ordered by contribution."
  def get_participations(instance_id) do
    EventParticipation
    |> where([p], p.event_instance_id == ^instance_id)
    |> order_by([p], desc: p.contribution_score)
    |> Repo.all()
  end

  @doc "Get top N contributors."
  def get_top_contributors(instance_id, limit \\ 10) do
    EventParticipation
    |> where([p], p.event_instance_id == ^instance_id)
    |> order_by([p], desc: p.contribution_score)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc "Join an event."
  def join_event(instance_id, character_id) do
    if get_participation(instance_id, character_id) do
      {:error, :already_joined}
    else
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      result =
        %EventParticipation{}
        |> EventParticipation.changeset(%{
          event_instance_id: instance_id,
          character_id: character_id,
          joined_at: now,
          last_activity_at: now
        })
        |> Repo.insert()

      case result do
        {:ok, participation} ->
          update_participant_count(instance_id)
          {:ok, participation}

        error ->
          error
      end
    end
  end

  @doc "Add contribution points. Auto-joins if not participating."
  def add_contribution(instance_id, character_id, points) do
    case get_or_create_participation(instance_id, character_id) do
      {:ok, participation} ->
        participation
        |> EventParticipation.contribute_changeset(points)
        |> Repo.update()

      error ->
        error
    end
  end

  @doc "Record a kill."
  def record_kill(instance_id, character_id, contribution_points) do
    case get_or_create_participation(instance_id, character_id) do
      {:ok, participation} ->
        participation
        |> EventParticipation.kill_changeset(contribution_points)
        |> Repo.update()

      error ->
        error
    end
  end

  @doc "Record damage dealt."
  def record_damage(instance_id, character_id, damage, contribution_points) do
    case get_or_create_participation(instance_id, character_id) do
      {:ok, participation} ->
        participation
        |> EventParticipation.damage_changeset(damage, contribution_points)
        |> Repo.update()

      error ->
        error
    end
  end

  @doc "Record healing done."
  def record_healing(instance_id, character_id, healing, contribution_points) do
    case get_or_create_participation(instance_id, character_id) do
      {:ok, participation} ->
        participation
        |> EventParticipation.healing_changeset(healing, contribution_points)
        |> Repo.update()

      error ->
        error
    end
  end

  @doc "Complete an objective for a participant."
  def complete_objective(instance_id, character_id, objective_index, contribution_points) do
    case get_participation(instance_id, character_id) do
      nil ->
        {:error, :not_participating}

      participation ->
        participation
        |> EventParticipation.complete_objective_changeset(objective_index, contribution_points)
        |> Repo.update()
    end
  end

  @doc "Calculate and assign reward tiers for all participants."
  def calculate_reward_tiers(instance_id) do
    participations = get_participations(instance_id)
    total = length(participations)

    if total == 0 do
      {:ok, []}
    else
      # Calculate tier thresholds
      gold_threshold = max(1, ceil(total * 0.1))
      silver_threshold = max(1, ceil(total * 0.25))
      bronze_threshold = max(1, ceil(total * 0.5))

      updated =
        participations
        |> Enum.with_index(1)
        |> Enum.map(fn {p, rank} ->
          tier = determine_tier(rank, p.contribution_score, gold_threshold, silver_threshold, bronze_threshold)

          {:ok, updated} =
            p
            |> EventParticipation.set_tier_changeset(tier)
            |> Repo.update()

          updated
        end)

      {:ok, updated}
    end
  end

  defp determine_tier(rank, score, gold_t, silver_t, bronze_t) do
    cond do
      rank <= gold_t or score >= 500 -> :gold
      rank <= silver_t or score >= 300 -> :silver
      rank <= bronze_t or score >= 100 -> :bronze
      true -> :participation
    end
  end

  @doc "Claim rewards for a participant."
  def claim_rewards(instance_id, character_id) do
    case get_participation(instance_id, character_id) do
      nil ->
        {:error, :not_participating}

      %{rewards_claimed: true} ->
        {:error, :already_claimed}

      participation ->
        participation
        |> EventParticipation.claim_rewards_changeset()
        |> Repo.update()
    end
  end

  defp get_or_create_participation(instance_id, character_id) do
    case get_participation(instance_id, character_id) do
      nil ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        result =
          %EventParticipation{}
          |> EventParticipation.changeset(%{
            event_instance_id: instance_id,
            character_id: character_id,
            joined_at: now,
            last_activity_at: now
          })
          |> Repo.insert()

        case result do
          {:ok, participation} ->
            update_participant_count(instance_id)
            {:ok, participation}

          error ->
            error
        end

      participation ->
        {:ok, participation}
    end
  end
end
