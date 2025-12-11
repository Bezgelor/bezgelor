defmodule BezgelorDb.Schema.InstanceCompletion do
  @moduledoc """
  Schema for historical instance completion records.

  Tracks statistics for completed instances including:
  - Duration and timing
  - Death count
  - Damage and healing done
  - Mythic+ specific data (level, timed status)
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BezgelorDb.Schema.Character

  @type t :: %__MODULE__{
          id: integer() | nil,
          character_id: integer(),
          instance_definition_id: integer(),
          instance_type: String.t(),
          difficulty: String.t(),
          completed_at: DateTime.t(),
          duration_seconds: integer() | nil,
          deaths: integer(),
          damage_done: integer(),
          healing_done: integer(),
          mythic_level: integer() | nil,
          timed: boolean() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @instance_types ~w(dungeon adventure raid expedition)
  @difficulties ~w(normal veteran challenge mythic_plus)

  schema "instance_completions" do
    belongs_to :character, Character

    field :instance_definition_id, :integer
    field :instance_type, :string
    field :difficulty, :string
    field :completed_at, :utc_datetime
    field :duration_seconds, :integer
    field :deaths, :integer, default: 0
    field :damage_done, :integer, default: 0
    field :healing_done, :integer, default: 0
    field :mythic_level, :integer
    field :timed, :boolean

    timestamps()
  end

  @required_fields [:character_id, :instance_definition_id, :instance_type, :difficulty, :completed_at]
  @optional_fields [:duration_seconds, :deaths, :damage_done, :healing_done, :mythic_level, :timed]

  @doc """
  Creates a changeset for an instance completion record.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(completion, attrs) do
    completion
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:instance_type, @instance_types)
    |> validate_inclusion(:difficulty, @difficulties)
    |> validate_number(:deaths, greater_than_or_equal_to: 0)
    |> validate_number(:damage_done, greater_than_or_equal_to: 0)
    |> validate_number(:healing_done, greater_than_or_equal_to: 0)
    |> validate_number(:duration_seconds, greater_than: 0)
    |> validate_number(:mythic_level, greater_than: 0, less_than_or_equal_to: 30)
    |> foreign_key_constraint(:character_id)
  end

  @doc """
  Creates a completion record for the current time.
  """
  @spec new_completion(integer(), integer(), String.t(), String.t(), map()) :: Ecto.Changeset.t()
  def new_completion(character_id, instance_id, instance_type, difficulty, stats \\ %{}) do
    attrs =
      Map.merge(stats, %{
        character_id: character_id,
        instance_definition_id: instance_id,
        instance_type: instance_type,
        difficulty: difficulty,
        completed_at: DateTime.utc_now()
      })

    changeset(%__MODULE__{}, attrs)
  end

  @doc """
  Checks if this was a mythic+ run.
  """
  @spec mythic_plus?(t()) :: boolean()
  def mythic_plus?(%__MODULE__{difficulty: difficulty}), do: difficulty == "mythic_plus"

  @doc """
  Checks if the run was timed (for mythic+).
  """
  @spec timed_run?(t()) :: boolean()
  def timed_run?(%__MODULE__{timed: timed}), do: timed == true
end
