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
end
