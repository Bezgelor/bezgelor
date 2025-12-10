defmodule BezgelorDb.Schema.QuestHistory do
  @moduledoc """
  Schema for completed quest history.

  Stores normalized records of completed quests for efficient querying
  of completion status, repeatable quest tracking, and statistics.

  ## Purpose

  - Track which quests a character has completed
  - Support repeatable quests with completion counts
  - Enable quest prerequisite checking
  - Provide completion statistics
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "quest_history" do
    belongs_to :character, BezgelorDb.Schema.Character

    # Quest template reference
    field :quest_id, :integer

    # Completion tracking
    field :completed_at, :utc_datetime
    field :completion_count, :integer, default: 1

    # For daily/weekly reset tracking
    field :last_completion, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(history, attrs) do
    history
    |> cast(attrs, [:character_id, :quest_id, :completed_at, :completion_count, :last_completion])
    |> validate_required([:character_id, :quest_id, :completed_at])
    |> validate_number(:completion_count, greater_than: 0)
    |> foreign_key_constraint(:character_id)
    |> unique_constraint([:character_id, :quest_id], name: :quest_history_character_id_quest_id_index)
  end

  def increment_changeset(history) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    history
    |> change(
      completion_count: history.completion_count + 1,
      last_completion: now
    )
  end
end
