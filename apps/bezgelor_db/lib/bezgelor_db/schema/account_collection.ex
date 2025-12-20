defmodule BezgelorDb.Schema.AccountCollection do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "account_collections" do
    belongs_to(:account, BezgelorDb.Schema.Account)

    # "mount" or "pet"
    field(:collectible_type, :string)
    field(:collectible_id, :integer)
    field(:unlock_source, :string)

    timestamps(type: :utc_datetime)
  end

  def changeset(collection, attrs) do
    collection
    |> cast(attrs, [:account_id, :collectible_type, :collectible_id, :unlock_source])
    |> validate_required([:account_id, :collectible_type, :collectible_id])
    |> validate_inclusion(:collectible_type, ["mount", "pet"])
    |> foreign_key_constraint(:account_id)
    |> unique_constraint([:account_id, :collectible_type, :collectible_id])
  end
end
