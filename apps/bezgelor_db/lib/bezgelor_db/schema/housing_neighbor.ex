defmodule BezgelorDb.Schema.HousingNeighbor do
  @moduledoc """
  Schema for housing neighbor permissions.

  Tracks who can visit a plot, with optional roommate
  elevation for decor placement rights.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "housing_neighbors" do
    belongs_to :plot, BezgelorDb.Schema.HousingPlot
    belongs_to :character, BezgelorDb.Schema.Character

    field :is_roommate, :boolean, default: false
    field :added_at, :utc_datetime
  end

  def changeset(neighbor, attrs) do
    neighbor
    |> cast(attrs, [:plot_id, :character_id, :is_roommate])
    |> validate_required([:plot_id, :character_id])
    |> put_change(:added_at, DateTime.utc_now() |> DateTime.truncate(:second))
    |> foreign_key_constraint(:plot_id)
    |> foreign_key_constraint(:character_id)
    |> unique_constraint([:plot_id, :character_id])
  end

  def roommate_changeset(neighbor, attrs) do
    neighbor
    |> cast(attrs, [:is_roommate])
  end
end
