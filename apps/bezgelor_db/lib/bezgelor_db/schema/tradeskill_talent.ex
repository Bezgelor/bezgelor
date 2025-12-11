defmodule BezgelorDb.Schema.TradeskillTalent do
  @moduledoc """
  Schema for tradeskill tech tree talent allocation.

  Each record represents points spent in a specific talent node
  for a character's profession.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BezgelorDb.Schema.Character

  @type t :: %__MODULE__{}

  schema "tradeskill_talents" do
    belongs_to :character, Character

    field :profession_id, :integer
    field :talent_id, :integer
    field :points_spent, :integer, default: 1

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(character_id profession_id talent_id)a
  @optional_fields ~w(points_spent)a

  @doc """
  Build a changeset for creating a talent allocation.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(talent, attrs) do
    talent
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_number(:points_spent, greater_than: 0)
    |> foreign_key_constraint(:character_id)
    |> unique_constraint([:character_id, :profession_id, :talent_id])
  end

  @doc """
  Changeset for adding another point to this talent.
  """
  @spec add_point_changeset(t()) :: Ecto.Changeset.t()
  def add_point_changeset(talent) do
    change(talent, points_spent: talent.points_spent + 1)
  end
end
