defmodule BezgelorDb.Schema.Reputation do
  @moduledoc """
  Character reputation with a faction.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias BezgelorDb.Schema.Character

  schema "reputations" do
    belongs_to(:character, Character)
    field(:faction_id, :integer)
    # Raw reputation points
    field(:standing, :integer, default: 0)
    timestamps()
  end

  def changeset(rep, attrs) do
    rep
    |> cast(attrs, [:character_id, :faction_id, :standing])
    |> validate_required([:character_id, :faction_id])
    |> unique_constraint([:character_id, :faction_id])
  end
end
