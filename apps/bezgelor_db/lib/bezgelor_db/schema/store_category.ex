defmodule BezgelorDb.Schema.StoreCategory do
  @moduledoc """
  Store category schema for organizing store items hierarchically.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "store_categories" do
    field(:name, :string)
    field(:slug, :string)
    field(:description, :string)
    field(:sort_order, :integer, default: 0)
    field(:icon, :string)
    field(:is_active, :boolean, default: true)

    belongs_to(:parent, __MODULE__)
    has_many(:children, __MODULE__, foreign_key: :parent_id)
    has_many(:store_items, BezgelorDb.Schema.StoreItem, foreign_key: :category_id)

    timestamps(type: :utc_datetime)
  end

  def changeset(category, attrs) do
    category
    |> cast(attrs, [:name, :slug, :description, :parent_id, :sort_order, :icon, :is_active])
    |> validate_required([:name, :slug])
    |> validate_length(:name, max: 100)
    |> validate_length(:slug, max: 100)
    |> validate_format(:slug, ~r/^[a-z0-9-]+$/,
      message: "must be lowercase alphanumeric with hyphens"
    )
    |> unique_constraint(:slug)
    |> foreign_key_constraint(:parent_id)
  end
end
