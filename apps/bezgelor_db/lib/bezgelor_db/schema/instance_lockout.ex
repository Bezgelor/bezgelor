defmodule BezgelorDb.Schema.InstanceLockout do
  @moduledoc """
  Schema for tracking character instance lockouts.

  Supports multiple lockout types:
  - Instance lockouts: Full instance reentry restriction
  - Encounter lockouts: Per-boss kill tracking
  - Loot lockouts: Loot eligibility separate from entry
  - Soft lockouts: Diminishing returns for repeated runs
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BezgelorDb.Schema.Character

  @type t :: %__MODULE__{
          id: integer() | nil,
          character_id: integer(),
          instance_type: String.t(),
          instance_definition_id: integer(),
          difficulty: String.t(),
          instance_guid: binary() | nil,
          boss_kills: [integer()],
          loot_received_at: DateTime.t() | nil,
          loot_eligible: boolean(),
          completion_count: integer(),
          diminishing_factor: float(),
          extended: boolean(),
          expires_at: DateTime.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @instance_types ~w(dungeon adventure raid expedition)
  @difficulties ~w(normal veteran challenge mythic_plus)

  schema "instance_lockouts" do
    belongs_to :character, Character

    field :instance_type, :string
    field :instance_definition_id, :integer
    field :difficulty, :string
    field :instance_guid, :binary
    field :boss_kills, {:array, :integer}, default: []
    field :loot_received_at, :utc_datetime
    field :loot_eligible, :boolean, default: true
    field :completion_count, :integer, default: 0
    field :diminishing_factor, :float, default: 1.0
    field :extended, :boolean, default: false
    field :expires_at, :utc_datetime

    timestamps()
  end

  @required_fields [:character_id, :instance_type, :instance_definition_id, :difficulty, :expires_at]
  @optional_fields [
    :instance_guid,
    :boss_kills,
    :loot_received_at,
    :loot_eligible,
    :completion_count,
    :diminishing_factor,
    :extended
  ]

  @doc """
  Creates a changeset for an instance lockout.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(lockout, attrs) do
    lockout
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:instance_type, @instance_types)
    |> validate_inclusion(:difficulty, @difficulties)
    |> validate_number(:completion_count, greater_than_or_equal_to: 0)
    |> validate_number(:diminishing_factor, greater_than: 0.0, less_than_or_equal_to: 1.0)
    |> foreign_key_constraint(:character_id)
  end

  @doc """
  Records a boss kill in the lockout.
  """
  @spec record_boss_kill(t(), integer()) :: Ecto.Changeset.t()
  def record_boss_kill(lockout, boss_id) do
    new_kills = Enum.uniq([boss_id | lockout.boss_kills])
    change(lockout, boss_kills: new_kills)
  end

  @doc """
  Records that loot was received, making the character ineligible for more loot.
  """
  @spec record_loot_received(t()) :: Ecto.Changeset.t()
  def record_loot_received(lockout) do
    change(lockout, loot_received_at: DateTime.utc_now(), loot_eligible: false)
  end

  @doc """
  Extends the lockout by marking it as extended (player choice to keep save).
  """
  @spec extend(t()) :: Ecto.Changeset.t()
  def extend(lockout) do
    change(lockout, extended: true)
  end

  @doc """
  Checks if the lockout has expired.
  """
  @spec expired?(t()) :: boolean()
  def expired?(%__MODULE__{expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :gt
  end

  @doc """
  Checks if a specific boss has been killed.
  """
  @spec boss_killed?(t(), integer()) :: boolean()
  def boss_killed?(%__MODULE__{boss_kills: boss_kills}, boss_id) do
    boss_id in boss_kills
  end

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
