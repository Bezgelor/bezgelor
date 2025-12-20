defmodule BezgelorDb.Schema.EventInstance do
  @moduledoc """
  Active public event instance.

  Tracks an in-progress event in a specific zone, including current phase,
  wave progress, objectives, and participant count.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @states [:pending, :active, :completed, :failed, :cancelled]

  schema "event_instances" do
    field(:event_id, :integer)
    field(:zone_id, :integer)
    field(:instance_id, :integer, default: 1)
    field(:state, Ecto.Enum, values: @states, default: :pending)
    field(:current_phase, :integer, default: 0)
    field(:current_wave, :integer, default: 0)
    field(:phase_progress, :map, default: %{})
    field(:participant_count, :integer, default: 0)
    field(:difficulty_multiplier, :float, default: 1.0)
    field(:started_at, :utc_datetime)
    field(:ends_at, :utc_datetime)
    field(:completed_at, :utc_datetime)

    has_many(:participations, BezgelorDb.Schema.EventParticipation)

    timestamps(type: :utc_datetime)
  end

  def changeset(instance, attrs) do
    instance
    |> cast(attrs, [
      :event_id,
      :zone_id,
      :instance_id,
      :state,
      :current_phase,
      :current_wave,
      :phase_progress,
      :participant_count,
      :difficulty_multiplier,
      :started_at,
      :ends_at
    ])
    |> validate_required([:event_id, :zone_id])
    |> validate_number(:current_phase, greater_than_or_equal_to: 0)
    |> validate_number(:current_wave, greater_than_or_equal_to: 0)
    |> validate_number(:participant_count, greater_than_or_equal_to: 0)
    |> validate_number(:difficulty_multiplier, greater_than: 0)
  end

  def start_changeset(instance, started_at, ends_at) do
    instance
    |> change(state: :active, started_at: started_at, ends_at: ends_at)
  end

  def progress_changeset(instance, progress) do
    instance
    |> change(phase_progress: progress)
  end

  def advance_phase_changeset(instance, new_phase, new_progress) do
    instance
    |> change(current_phase: new_phase, phase_progress: new_progress)
  end

  def advance_wave_changeset(instance, new_wave) do
    instance
    |> change(current_wave: new_wave)
  end

  def participant_changeset(instance, count) do
    instance
    |> change(participant_count: count)
  end

  def difficulty_changeset(instance, multiplier) do
    instance
    |> change(difficulty_multiplier: multiplier)
  end

  def complete_changeset(instance, completed_at) do
    instance
    |> change(state: :completed, completed_at: completed_at)
  end

  def fail_changeset(instance) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    instance
    |> change(state: :failed, completed_at: now)
  end

  def cancel_changeset(instance) do
    instance
    |> change(state: :cancelled)
  end

  def valid_states, do: @states
end
