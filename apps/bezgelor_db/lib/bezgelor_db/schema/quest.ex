defmodule BezgelorDb.Schema.Quest do
  @moduledoc """
  Schema for active character quests.

  ## Hybrid Storage

  Uses JSON for flexible objective progress while keeping
  core quest state in normalized columns for efficient queries.

  ## Progress Format

  The `progress` field stores objective completion as JSON:

      %{
        "objectives" => [
          %{"index" => 0, "current" => 5, "target" => 10, "type" => "kill"},
          %{"index" => 1, "current" => 1, "target" => 1, "type" => "item"}
        ],
        "flags" => %{"talked_to_npc" => true}
      }

  ## Quest States

  - `:accepted` - Quest is active
  - `:complete` - All objectives done, ready to turn in
  - `:failed` - Quest failed (timed out, etc.)
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @states [:accepted, :complete, :failed]

  schema "quests" do
    belongs_to :character, BezgelorDb.Schema.Character

    # Quest template reference (from BezgelorData)
    field :quest_id, :integer

    # Quest state
    field :state, Ecto.Enum, values: @states, default: :accepted

    # Flexible progress storage (JSON)
    field :progress, :map, default: %{}

    # Tracking
    field :accepted_at, :utc_datetime
    field :completed_at, :utc_datetime
    field :expires_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(quest, attrs) do
    quest
    |> cast(attrs, [:character_id, :quest_id, :state, :progress, :accepted_at, :completed_at, :expires_at])
    |> validate_required([:character_id, :quest_id])
    |> validate_inclusion(:state, @states)
    |> foreign_key_constraint(:character_id)
    |> unique_constraint([:character_id, :quest_id], name: :quests_character_id_quest_id_index)
  end

  def progress_changeset(quest, progress) do
    quest
    |> cast(%{progress: progress}, [:progress])
  end

  def complete_changeset(quest) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    quest
    |> change(state: :complete, completed_at: now)
  end

  def fail_changeset(quest) do
    quest
    |> change(state: :failed)
  end

  @doc "Get valid quest states."
  def states, do: @states
end
