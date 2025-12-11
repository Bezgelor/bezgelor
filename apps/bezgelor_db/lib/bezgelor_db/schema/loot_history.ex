defmodule BezgelorDb.Schema.LootHistory do
  @moduledoc """
  Schema for loot distribution audit trail.

  Tracks all loot awarded in instances for:
  - Audit and dispute resolution
  - Statistics and analysis
  - Loot tracking for bad luck protection
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BezgelorDb.Schema.Character

  @type t :: %__MODULE__{
          id: integer() | nil,
          instance_guid: binary() | nil,
          character_id: integer() | nil,
          item_id: integer(),
          item_quality: String.t() | nil,
          source_type: String.t() | nil,
          source_id: integer() | nil,
          distribution_method: String.t() | nil,
          roll_value: integer() | nil,
          awarded_at: DateTime.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @source_types ~w(boss trash chest)
  @distribution_methods ~w(personal need greed master round_robin)

  schema "loot_history" do
    belongs_to :character, Character

    field :instance_guid, :binary
    field :item_id, :integer
    field :item_quality, :string
    field :source_type, :string
    field :source_id, :integer
    field :distribution_method, :string
    field :roll_value, :integer
    field :awarded_at, :utc_datetime

    timestamps()
  end

  @required_fields [:item_id, :awarded_at]
  @optional_fields [
    :instance_guid,
    :character_id,
    :item_quality,
    :source_type,
    :source_id,
    :distribution_method,
    :roll_value
  ]

  @doc """
  Creates a changeset for a loot history entry.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(history, attrs) do
    history
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:source_type, @source_types)
    |> validate_inclusion(:distribution_method, @distribution_methods)
    |> validate_number(:roll_value, greater_than_or_equal_to: 1, less_than_or_equal_to: 100)
    |> foreign_key_constraint(:character_id)
  end

  @doc """
  Creates a loot history entry for the current time.
  """
  @spec record_drop(map()) :: Ecto.Changeset.t()
  def record_drop(attrs) do
    attrs = Map.put(attrs, :awarded_at, DateTime.utc_now())
    changeset(%__MODULE__{}, attrs)
  end

  @doc """
  Checks if this was boss loot.
  """
  @spec from_boss?(t()) :: boolean()
  def from_boss?(%__MODULE__{source_type: source_type}), do: source_type == "boss"

  @doc """
  Checks if this was trash loot.
  """
  @spec from_trash?(t()) :: boolean()
  def from_trash?(%__MODULE__{source_type: source_type}), do: source_type == "trash"

  @doc """
  Checks if this was chest loot.
  """
  @spec from_chest?(t()) :: boolean()
  def from_chest?(%__MODULE__{source_type: source_type}), do: source_type == "chest"

  @doc """
  Checks if this was personal loot.
  """
  @spec personal_loot?(t()) :: boolean()
  def personal_loot?(%__MODULE__{distribution_method: method}), do: method == "personal"

  @doc """
  Checks if this was won via need roll.
  """
  @spec need_roll?(t()) :: boolean()
  def need_roll?(%__MODULE__{distribution_method: method}), do: method == "need"

  @doc """
  Checks if this was won via greed roll.
  """
  @spec greed_roll?(t()) :: boolean()
  def greed_roll?(%__MODULE__{distribution_method: method}), do: method == "greed"

  @doc """
  Checks if this was master loot.
  """
  @spec master_loot?(t()) :: boolean()
  def master_loot?(%__MODULE__{distribution_method: method}), do: method == "master"

  @doc """
  Checks if this was unclaimed (character_id is nil).
  """
  @spec unclaimed?(t()) :: boolean()
  def unclaimed?(%__MODULE__{character_id: character_id}), do: is_nil(character_id)

  @doc """
  Returns the list of valid source types.
  """
  @spec source_types() :: [String.t()]
  def source_types, do: @source_types

  @doc """
  Returns the list of valid distribution methods.
  """
  @spec distribution_methods() :: [String.t()]
  def distribution_methods, do: @distribution_methods
end
