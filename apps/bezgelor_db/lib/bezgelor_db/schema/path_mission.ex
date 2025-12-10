defmodule BezgelorDb.Schema.PathMission do
  @moduledoc """
  Schema for path mission progress.

  Path missions are similar to quests but path-specific.
  They reward path XP instead of normal XP.

  ## Mission States

  - `:active` - Currently in progress
  - `:completed` - Finished and rewards claimed
  - `:failed` - Failed (some missions can fail)

  ## Progress Tracking

  Progress is stored as JSON map for flexibility:
  - Counter missions: `%{"count" => current, "target" => required}`
  - Multi-objective: `%{"obj1" => true, "obj2" => false, "obj3" => 5}`
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "path_missions" do
    belongs_to :character, BezgelorDb.Schema.Character

    # Mission template reference (from BezgelorData)
    field :mission_id, :integer

    # State
    field :state, Ecto.Enum, values: [:active, :completed, :failed], default: :active

    # Flexible progress tracking
    field :progress, :map, default: %{}

    # Completion time
    field :completed_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(mission, attrs) do
    mission
    |> cast(attrs, [:character_id, :mission_id, :state, :progress, :completed_at])
    |> validate_required([:character_id, :mission_id])
    |> foreign_key_constraint(:character_id)
    |> unique_constraint([:character_id, :mission_id], name: :path_missions_character_id_mission_id_index)
  end

  def progress_changeset(mission, progress) do
    mission
    |> cast(%{progress: progress}, [:progress])
  end

  def complete_changeset(mission) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    mission
    |> change(state: :completed, completed_at: now)
  end

  def fail_changeset(mission) do
    mission
    |> change(state: :failed)
  end
end
