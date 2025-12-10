defmodule BezgelorDb.Schema.Achievement do
  @moduledoc """
  Schema for character achievement progress and completion.

  ## Achievement Types

  - `:progress` - Incremental achievements (kill X creatures, collect Y items)
  - `:criteria` - Multi-criteria achievements (complete A, B, and C)
  - `:meta` - Meta achievements (complete X other achievements)

  ## Progress Tracking

  Progress is stored as integer for simple achievements, or JSON
  for multi-criteria achievements tracking individual criteria.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "achievements" do
    belongs_to :character, BezgelorDb.Schema.Character

    # Achievement template reference (from BezgelorData)
    field :achievement_id, :integer

    # Progress tracking
    field :progress, :integer, default: 0
    field :criteria_progress, :map, default: %{}

    # Completion
    field :completed, :boolean, default: false
    field :completed_at, :utc_datetime

    # Display
    field :points_awarded, :integer, default: 0

    timestamps(type: :utc_datetime)
  end

  def changeset(achievement, attrs) do
    achievement
    |> cast(attrs, [:character_id, :achievement_id, :progress, :criteria_progress, :completed, :completed_at, :points_awarded])
    |> validate_required([:character_id, :achievement_id])
    |> validate_number(:progress, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:character_id)
    |> unique_constraint([:character_id, :achievement_id], name: :achievements_character_id_achievement_id_index)
  end

  def progress_changeset(achievement, progress) do
    achievement
    |> cast(%{progress: progress}, [:progress])
    |> validate_number(:progress, greater_than_or_equal_to: 0)
  end

  def criteria_changeset(achievement, criteria_progress) do
    achievement
    |> cast(%{criteria_progress: criteria_progress}, [:criteria_progress])
  end

  def complete_changeset(achievement, points) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    achievement
    |> change(completed: true, completed_at: now, points_awarded: points)
  end
end
