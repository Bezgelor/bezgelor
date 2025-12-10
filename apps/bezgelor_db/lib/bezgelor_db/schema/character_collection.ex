defmodule BezgelorDb.Schema.CharacterCollection do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "character_collections" do
    belongs_to :character, BezgelorDb.Schema.Character

    field :collectible_type, :string
    field :collectible_id, :integer
    field :unlock_source, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(collection, attrs) do
    collection
    |> cast(attrs, [:character_id, :collectible_type, :collectible_id, :unlock_source])
    |> validate_required([:character_id, :collectible_type, :collectible_id])
    |> validate_inclusion(:collectible_type, ["mount", "pet"])
    |> foreign_key_constraint(:character_id)
    |> unique_constraint([:character_id, :collectible_type, :collectible_id])
  end
end
