defmodule BezgelorDb.Schema.BattlegroundQueue do
  @moduledoc """
  Schema for battleground queue entries.

  Tracks players queued for battlegrounds including:
  - Queue type (random, specific)
  - Group information
  - Role preferences
  - MMR for rated BGs
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BezgelorDb.Schema.{Account, Character}

  @type t :: %__MODULE__{
          id: integer() | nil,
          character_id: integer(),
          account_id: integer(),
          queue_type: String.t(),
          battleground_id: integer() | nil,
          is_rated: boolean(),
          group_id: String.t() | nil,
          group_size: integer(),
          role: String.t(),
          mmr: integer(),
          queued_at: DateTime.t(),
          estimated_wait_seconds: integer() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @queue_types ~w(random specific rated)
  @roles ~w(tank healer dps any)

  schema "battleground_queue" do
    belongs_to(:character, Character)
    belongs_to(:account, Account)

    field(:queue_type, :string)
    field(:battleground_id, :integer)
    field(:is_rated, :boolean, default: false)
    field(:group_id, :string)
    field(:group_size, :integer, default: 1)
    field(:role, :string, default: "any")
    field(:mmr, :integer, default: 1500)
    field(:queued_at, :utc_datetime)
    field(:estimated_wait_seconds, :integer)

    timestamps()
  end

  @required_fields [:character_id, :account_id, :queue_type, :queued_at]
  @optional_fields [
    :battleground_id,
    :is_rated,
    :group_id,
    :group_size,
    :role,
    :mmr,
    :estimated_wait_seconds
  ]

  @doc """
  Creates a changeset for a queue entry.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:queue_type, @queue_types)
    |> validate_inclusion(:role, @roles)
    |> validate_number(:group_size, greater_than_or_equal_to: 1, less_than_or_equal_to: 40)
    |> validate_number(:mmr, greater_than_or_equal_to: 0)
    |> validate_specific_bg()
    |> unique_constraint(:character_id)
    |> foreign_key_constraint(:character_id)
    |> foreign_key_constraint(:account_id)
  end

  @doc """
  Updates estimated wait time.
  """
  @spec update_estimate(t(), integer()) :: Ecto.Changeset.t()
  def update_estimate(entry, seconds) do
    change(entry, estimated_wait_seconds: seconds)
  end

  @doc """
  Returns wait time in seconds.
  """
  @spec wait_time_seconds(t()) :: integer()
  def wait_time_seconds(%__MODULE__{queued_at: queued_at}) do
    DateTime.diff(DateTime.utc_now(), queued_at, :second)
  end

  @doc """
  Checks if this is a group queue.
  """
  @spec group_queue?(t()) :: boolean()
  def group_queue?(%__MODULE__{group_id: nil}), do: false
  def group_queue?(%__MODULE__{}), do: true

  @doc """
  Checks if this is a rated queue.
  """
  @spec rated?(t()) :: boolean()
  def rated?(%__MODULE__{is_rated: true}), do: true
  def rated?(%__MODULE__{}), do: false

  @doc """
  Checks if entry wants a specific battleground.
  """
  @spec wants_battleground?(t(), integer()) :: boolean()
  def wants_battleground?(%__MODULE__{queue_type: "random"}, _bg_id), do: true
  def wants_battleground?(%__MODULE__{battleground_id: bg_id}, bg_id), do: true
  def wants_battleground?(%__MODULE__{}, _bg_id), do: false

  @doc """
  Returns the list of valid queue types.
  """
  @spec queue_types() :: [String.t()]
  def queue_types, do: @queue_types

  @doc """
  Returns the list of valid roles.
  """
  @spec roles() :: [String.t()]
  def roles, do: @roles

  # Private validation

  defp validate_specific_bg(changeset) do
    queue_type = get_field(changeset, :queue_type)
    bg_id = get_field(changeset, :battleground_id)

    if queue_type == "specific" and is_nil(bg_id) do
      add_error(changeset, :battleground_id, "required for specific queue")
    else
      changeset
    end
  end
end
