defmodule BezgelorDb.Schema.MythicRun do
  @moduledoc """
  Schema for completed mythic+ runs (leaderboard data).

  Tracks run data for leaderboards:
  - Instance, level, and affixes
  - Duration and timed status
  - Team composition
  - Season for historical tracking
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          instance_definition_id: integer(),
          level: integer(),
          affixes: [String.t()],
          duration_seconds: integer(),
          timed: boolean(),
          completed_at: DateTime.t(),
          member_ids: [integer()],
          member_names: [String.t()],
          member_classes: [String.t()],
          season: integer(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @max_group_size 5

  schema "mythic_runs" do
    field(:instance_definition_id, :integer)
    field(:level, :integer)
    field(:affixes, {:array, :string})
    field(:duration_seconds, :integer)
    field(:timed, :boolean)
    field(:completed_at, :utc_datetime)
    field(:member_ids, {:array, :integer})
    field(:member_names, {:array, :string})
    field(:member_classes, {:array, :string})
    field(:season, :integer, default: 1)

    timestamps()
  end

  @required_fields [
    :instance_definition_id,
    :level,
    :affixes,
    :duration_seconds,
    :timed,
    :completed_at,
    :member_ids,
    :member_names,
    :member_classes
  ]
  @optional_fields [:season]

  @doc """
  Creates a changeset for a mythic run.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(run, attrs) do
    run
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_number(:level, greater_than: 0)
    |> validate_number(:duration_seconds, greater_than: 0)
    |> validate_number(:season, greater_than: 0)
    |> validate_length(:member_ids, min: 1, max: @max_group_size)
    |> validate_length(:member_names, min: 1, max: @max_group_size)
    |> validate_length(:member_classes, min: 1, max: @max_group_size)
    |> validate_member_arrays_match()
  end

  # Validates that all member arrays have the same length.
  @spec validate_member_arrays_match(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_member_arrays_match(changeset) do
    member_ids = get_field(changeset, :member_ids) || []
    member_names = get_field(changeset, :member_names) || []
    member_classes = get_field(changeset, :member_classes) || []

    ids_len = length(member_ids)
    names_len = length(member_names)
    classes_len = length(member_classes)

    if ids_len == names_len and names_len == classes_len do
      changeset
    else
      add_error(changeset, :member_ids, "member arrays must have matching lengths")
    end
  end

  @doc """
  Checks if the run was timed (beat the timer).
  """
  @spec timed?(t()) :: boolean()
  def timed?(%__MODULE__{timed: timed}), do: timed == true

  @doc """
  Returns formatted duration as "MM:SS".
  """
  @spec formatted_duration(t()) :: String.t()
  def formatted_duration(%__MODULE__{duration_seconds: seconds}) do
    minutes = div(seconds, 60)
    secs = rem(seconds, 60)

    "#{String.pad_leading(to_string(minutes), 2, "0")}:#{String.pad_leading(to_string(secs), 2, "0")}"
  end

  @doc """
  Returns the score for this run (level * time factor).
  Used for leaderboard ranking.
  """
  @spec score(t(), integer()) :: float()
  def score(%__MODULE__{level: level, duration_seconds: duration, timed: timed}, time_limit) do
    base_score = level * 100

    time_bonus =
      if timed do
        remaining = time_limit - duration
        # Bonus points for faster completion
        remaining / time_limit * 50
      else
        0
      end

    base_score + time_bonus
  end

  @doc """
  Returns member data as a list of tuples.
  """
  @spec members(t()) :: [{integer(), String.t(), String.t()}]
  def members(%__MODULE__{member_ids: ids, member_names: names, member_classes: classes}) do
    Enum.zip([ids, names, classes])
  end
end
