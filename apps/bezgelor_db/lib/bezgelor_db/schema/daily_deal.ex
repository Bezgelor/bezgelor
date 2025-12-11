defmodule BezgelorDb.Schema.DailyDeal do
  @moduledoc """
  Daily deal schema for rotating featured items with discounts.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "daily_deals" do
    belongs_to :store_item, BezgelorDb.Schema.StoreItem

    field :discount_percent, :integer
    field :active_date, :date
    field :quantity_limit, :integer
    field :quantity_sold, :integer, default: 0

    timestamps(type: :utc_datetime)
  end

  def changeset(deal, attrs) do
    deal
    |> cast(attrs, [:store_item_id, :discount_percent, :active_date, :quantity_limit, :quantity_sold])
    |> validate_required([:store_item_id, :discount_percent, :active_date])
    |> validate_number(:discount_percent, greater_than: 0, less_than_or_equal_to: 100)
    |> validate_number(:quantity_limit, greater_than: 0)
    |> validate_number(:quantity_sold, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:store_item_id)
    |> unique_constraint([:active_date, :store_item_id])
  end

  @doc "Check if deal has available stock."
  def available?(%__MODULE__{quantity_limit: nil}), do: true
  def available?(%__MODULE__{quantity_limit: limit, quantity_sold: sold}), do: sold < limit

  @doc "Calculate discounted price for an item."
  def calculate_price(%__MODULE__{discount_percent: discount}, original_price) do
    trunc(original_price * (100 - discount) / 100)
  end
end
