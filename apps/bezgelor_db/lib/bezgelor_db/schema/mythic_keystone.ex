defmodule BezgelorDb.Schema.MythicKeystone do
  @moduledoc """
  Schema for player mythic+ keystone inventory.

  Tracks keystones that players have obtained:
  - Instance and level
  - Active affixes
  - Depleted status (failed timer)
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BezgelorDb.Schema.Character

  @type t :: %__MODULE__{
          id: integer() | nil,
          character_id: integer(),
          instance_definition_id: integer(),
          level: integer(),
          affixes: [String.t()],
          obtained_at: DateTime.t(),
          depleted: boolean(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @max_level 30

  schema "mythic_keystones" do
    belongs_to :character, Character

    field :instance_definition_id, :integer
    field :level, :integer, default: 1
    field :affixes, {:array, :string}, default: []
    field :obtained_at, :utc_datetime
    field :depleted, :boolean, default: false

    timestamps()
  end

  @required_fields [:character_id, :instance_definition_id, :level, :obtained_at]
  @optional_fields [:affixes, :depleted]

  @doc """
  Creates a changeset for a keystone.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(keystone, attrs) do
    keystone
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_number(:level, greater_than: 0, less_than_or_equal_to: @max_level)
    |> foreign_key_constraint(:character_id)
  end

  @doc """
  Upgrades the keystone by the specified number of levels.
  """
  @spec upgrade(t(), integer()) :: Ecto.Changeset.t()
  def upgrade(keystone, levels \\ 1) do
    new_level = min(keystone.level + levels, @max_level)
    change(keystone, level: new_level, depleted: false)
  end

  @doc """
  Depletes the keystone (failed timer), reducing level by 1.
  """
  @spec deplete(t()) :: Ecto.Changeset.t()
  def deplete(keystone) do
    new_level = max(keystone.level - 1, 1)
    change(keystone, level: new_level, depleted: true)
  end

  @doc """
  Resets the depleted status without changing level.
  """
  @spec reset_depleted(t()) :: Ecto.Changeset.t()
  def reset_depleted(keystone) do
    change(keystone, depleted: false)
  end

  @doc """
  Sets new affixes for the keystone.
  """
  @spec set_affixes(t(), [String.t()]) :: Ecto.Changeset.t()
  def set_affixes(keystone, affixes) do
    change(keystone, affixes: affixes)
  end

  @doc """
  Checks if the keystone is depleted.
  """
  @spec depleted?(t()) :: boolean()
  def depleted?(%__MODULE__{depleted: depleted}), do: depleted

  @doc """
  Checks if the keystone is at max level.
  """
  @spec max_level?(t()) :: boolean()
  def max_level?(%__MODULE__{level: level}), do: level >= @max_level

  @doc """
  Returns the maximum keystone level.
  """
  @spec max_level() :: integer()
  def max_level, do: @max_level

  @doc """
  Calculates the number of upgrade levels based on time remaining.
  Returns 1-3 based on how quickly the dungeon was completed.
  """
  @spec calculate_upgrade_levels(integer(), integer()) :: integer()
  def calculate_upgrade_levels(duration_seconds, time_limit_seconds) do
    remaining = time_limit_seconds - duration_seconds

    cond do
      remaining <= 0 -> 0
      remaining >= time_limit_seconds * 0.4 -> 3  # 40%+ time remaining
      remaining >= time_limit_seconds * 0.2 -> 2  # 20%+ time remaining
      true -> 1
    end
  end
end
