defmodule BezgelorDb.Schema.InstanceSave do
  @moduledoc """
  Schema for raid save states.

  Tracks the state of a raid instance including:
  - Boss kills
  - Trash cleared areas
  - Expiration time (weekly reset)
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          instance_guid: binary(),
          instance_definition_id: integer(),
          difficulty: String.t(),
          boss_kills: [integer()],
          trash_cleared: [String.t()],
          created_at: DateTime.t(),
          expires_at: DateTime.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @difficulties ~w(normal veteran)

  schema "instance_saves" do
    field :instance_guid, :binary
    field :instance_definition_id, :integer
    field :difficulty, :string
    field :boss_kills, {:array, :integer}, default: []
    field :trash_cleared, {:array, :string}, default: []
    field :created_at, :utc_datetime
    field :expires_at, :utc_datetime

    timestamps()
  end

  @required_fields [:instance_guid, :instance_definition_id, :difficulty, :created_at, :expires_at]
  @optional_fields [:boss_kills, :trash_cleared]

  @doc """
  Creates a changeset for an instance save.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(save, attrs) do
    save
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:difficulty, @difficulties)
    |> unique_constraint(:instance_guid)
  end

  @doc """
  Records a boss kill in the save.
  """
  @spec record_boss_kill(t(), integer()) :: Ecto.Changeset.t()
  def record_boss_kill(save, boss_id) do
    new_kills = Enum.uniq([boss_id | save.boss_kills])
    change(save, boss_kills: new_kills)
  end

  @doc """
  Records that a trash area has been cleared.
  """
  @spec record_trash_cleared(t(), String.t()) :: Ecto.Changeset.t()
  def record_trash_cleared(save, area_id) do
    new_cleared = Enum.uniq([area_id | save.trash_cleared])
    change(save, trash_cleared: new_cleared)
  end

  @doc """
  Checks if the save has expired.
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
  Checks if a trash area has been cleared.
  """
  @spec trash_area_cleared?(t(), String.t()) :: boolean()
  def trash_area_cleared?(%__MODULE__{trash_cleared: trash_cleared}, area_id) do
    area_id in trash_cleared
  end

  @doc """
  Returns the count of bosses killed.
  """
  @spec bosses_killed_count(t()) :: integer()
  def bosses_killed_count(%__MODULE__{boss_kills: boss_kills}) do
    length(boss_kills)
  end

  @doc """
  Returns progress as a fraction (killed / total).
  """
  @spec progress(t(), integer()) :: float()
  def progress(%__MODULE__{boss_kills: boss_kills}, total_bosses) when total_bosses > 0 do
    length(boss_kills) / total_bosses
  end

  def progress(_save, _total), do: 0.0
end
