defmodule BezgelorDb.Schema.CharacterTradeskill do
  @moduledoc """
  Schema for character tradeskill profession progress.

  Tracks a character's level and XP in each profession they've learned.
  The is_active flag indicates whether this is a currently active profession
  (characters can swap professions, potentially preserving progress).
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BezgelorDb.Schema.Character

  @type t :: %__MODULE__{}

  schema "character_tradeskills" do
    belongs_to(:character, Character)

    field(:profession_id, :integer)
    field(:profession_type, Ecto.Enum, values: [:crafting, :gathering])
    field(:skill_level, :integer, default: 0)
    field(:skill_xp, :integer, default: 0)
    field(:is_active, :boolean, default: true)

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(character_id profession_id profession_type)a
  @optional_fields ~w(skill_level skill_xp is_active)a

  @doc """
  Build a changeset for creating or updating a tradeskill record.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(tradeskill, attrs) do
    tradeskill
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_number(:skill_level, greater_than_or_equal_to: 0)
    |> validate_number(:skill_xp, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:character_id)
    |> unique_constraint([:character_id, :profession_id])
  end

  @doc """
  Changeset for updating skill progress (level and XP).
  """
  @spec progress_changeset(t(), map()) :: Ecto.Changeset.t()
  def progress_changeset(tradeskill, attrs) do
    tradeskill
    |> cast(attrs, [:skill_level, :skill_xp])
    |> validate_number(:skill_level, greater_than_or_equal_to: 0)
    |> validate_number(:skill_xp, greater_than_or_equal_to: 0)
  end

  @doc """
  Changeset for deactivating a profession (when swapping).
  """
  @spec deactivate_changeset(t()) :: Ecto.Changeset.t()
  def deactivate_changeset(tradeskill) do
    change(tradeskill, is_active: false)
  end

  @doc """
  Changeset for reactivating a previously learned profession.
  """
  @spec activate_changeset(t()) :: Ecto.Changeset.t()
  def activate_changeset(tradeskill) do
    change(tradeskill, is_active: true)
  end
end
