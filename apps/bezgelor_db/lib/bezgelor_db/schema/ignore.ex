defmodule BezgelorDb.Schema.Ignore do
  @moduledoc """
  Ignore/block relationship between characters.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias BezgelorDb.Schema.Character

  schema "ignores" do
    belongs_to(:character, Character)
    belongs_to(:ignored_character, Character)
    timestamps()
  end

  def changeset(ignore, attrs) do
    ignore
    |> cast(attrs, [:character_id, :ignored_character_id])
    |> validate_required([:character_id, :ignored_character_id])
    |> unique_constraint([:character_id, :ignored_character_id])
  end
end
