defmodule BezgelorDb.Schema.StoreItem do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @item_types ~w(mount pet costume dye service)

  schema "store_items" do
    field :item_type, :string
    field :item_id, :integer
    field :name, :string
    field :description, :string
    field :premium_price, :integer
    field :bonus_price, :integer
    field :gold_price, :integer
    field :category, :string
    field :featured, :boolean, default: false
    field :limited_time, :boolean, default: false
    field :available_from, :utc_datetime
    field :available_until, :utc_datetime
    field :active, :boolean, default: true

    timestamps(type: :utc_datetime)
  end

  def changeset(item, attrs) do
    item
    |> cast(attrs, [
      :item_type, :item_id, :name, :description,
      :premium_price, :bonus_price, :gold_price,
      :category, :featured, :limited_time,
      :available_from, :available_until, :active
    ])
    |> validate_required([:item_type, :item_id, :name])
    |> validate_inclusion(:item_type, @item_types)
    |> validate_has_price()
    |> unique_constraint([:item_type, :item_id])
  end

  defp validate_has_price(changeset) do
    premium = get_field(changeset, :premium_price)
    bonus = get_field(changeset, :bonus_price)
    gold = get_field(changeset, :gold_price)

    if premium || bonus || gold do
      changeset
    else
      add_error(changeset, :premium_price, "at least one price must be set")
    end
  end

  def item_types, do: @item_types
end
