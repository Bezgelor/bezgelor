defmodule BezgelorDb.Schema.GroupFinderQueue do
  @moduledoc """
  Schema for group finder queue entries.

  Tracks players actively queued for instances including:
  - Selected role and instances
  - Gear score for smart matching
  - Completion rate for reliability scoring
  - Preferences for advanced matching
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BezgelorDb.Schema.{Account, Character}

  @type t :: %__MODULE__{
          id: integer() | nil,
          character_id: integer(),
          account_id: integer(),
          instance_type: String.t(),
          instance_ids: [integer()],
          difficulty: String.t(),
          role: String.t(),
          gear_score: integer(),
          completion_rate: float(),
          preferences: map(),
          queued_at: DateTime.t(),
          estimated_wait_seconds: integer() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @instance_types ~w(dungeon adventure raid expedition)
  @difficulties ~w(normal veteran challenge mythic_plus)
  @roles ~w(tank healer dps)

  schema "group_finder_queue" do
    belongs_to :character, Character
    belongs_to :account, Account

    field :instance_type, :string
    field :instance_ids, {:array, :integer}
    field :difficulty, :string
    field :role, :string
    field :gear_score, :integer, default: 0
    field :completion_rate, :float, default: 1.0
    field :preferences, :map, default: %{}
    field :queued_at, :utc_datetime
    field :estimated_wait_seconds, :integer

    timestamps()
  end

  @required_fields [:character_id, :account_id, :instance_type, :instance_ids, :difficulty, :role, :queued_at]
  @optional_fields [:gear_score, :completion_rate, :preferences, :estimated_wait_seconds]

  @doc """
  Creates a changeset for a queue entry.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(queue_entry, attrs) do
    queue_entry
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:instance_type, @instance_types)
    |> validate_inclusion(:difficulty, @difficulties)
    |> validate_inclusion(:role, @roles)
    |> validate_number(:gear_score, greater_than_or_equal_to: 0)
    |> validate_number(:completion_rate, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_length(:instance_ids, min: 1)
    |> unique_constraint(:character_id)
    |> foreign_key_constraint(:character_id)
    |> foreign_key_constraint(:account_id)
  end

  @doc """
  Updates the estimated wait time.
  """
  @spec update_estimate(t(), integer()) :: Ecto.Changeset.t()
  def update_estimate(queue_entry, seconds) do
    change(queue_entry, estimated_wait_seconds: seconds)
  end

  @doc """
  Returns the time spent in queue in seconds.
  """
  @spec wait_time_seconds(t()) :: integer()
  def wait_time_seconds(%__MODULE__{queued_at: queued_at}) do
    DateTime.diff(DateTime.utc_now(), queued_at, :second)
  end

  @doc """
  Checks if the player wants a specific instance.
  """
  @spec wants_instance?(t(), integer()) :: boolean()
  def wants_instance?(%__MODULE__{instance_ids: instance_ids}, instance_id) do
    instance_id in instance_ids
  end

  @doc """
  Checks if this is a tank role.
  """
  @spec tank?(t()) :: boolean()
  def tank?(%__MODULE__{role: role}), do: role == "tank"

  @doc """
  Checks if this is a healer role.
  """
  @spec healer?(t()) :: boolean()
  def healer?(%__MODULE__{role: role}), do: role == "healer"

  @doc """
  Checks if this is a DPS role.
  """
  @spec dps?(t()) :: boolean()
  def dps?(%__MODULE__{role: role}), do: role == "dps"

  @doc """
  Returns the list of valid roles.
  """
  @spec roles() :: [String.t()]
  def roles, do: @roles

  @doc """
  Returns the list of valid instance types.
  """
  @spec instance_types() :: [String.t()]
  def instance_types, do: @instance_types

  @doc """
  Returns the list of valid difficulties.
  """
  @spec difficulties() :: [String.t()]
  def difficulties, do: @difficulties
end
