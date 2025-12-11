defmodule BezgelorDb.Schema.StoreItem do
  @moduledoc """
  Store item schema representing purchasable items in the storefront.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @item_types ~w(mount pet costume dye service bundle)

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

    # New fields from migration
    belongs_to :store_category, BezgelorDb.Schema.StoreCategory, foreign_key: :category_id
    field :sort_order, :integer, default: 0
    field :new_until, :utc_datetime
    field :sale_price, :integer
    field :sale_ends_at, :utc_datetime
    field :metadata, :map, default: %{}

    has_many :purchases, BezgelorDb.Schema.StorePurchase
    has_many :daily_deals, BezgelorDb.Schema.DailyDeal

    timestamps(type: :utc_datetime)
  end

  def changeset(item, attrs) do
    item
    |> cast(attrs, [
      :item_type, :item_id, :name, :description,
      :premium_price, :bonus_price, :gold_price,
      :category, :featured, :limited_time,
      :available_from, :available_until, :active,
      :category_id, :sort_order, :new_until,
      :sale_price, :sale_ends_at, :metadata
    ])
    |> validate_required([:item_type, :item_id, :name])
    |> validate_inclusion(:item_type, @item_types)
    |> validate_has_price()
    |> validate_sale_dates()
    |> unique_constraint([:item_type, :item_id])
    |> foreign_key_constraint(:category_id)
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

  defp validate_sale_dates(changeset) do
    sale_price = get_field(changeset, :sale_price)
    sale_ends_at = get_field(changeset, :sale_ends_at)

    cond do
      sale_price && is_nil(sale_ends_at) ->
        add_error(changeset, :sale_ends_at, "sale_ends_at required when sale_price is set")

      sale_ends_at && is_nil(sale_price) ->
        add_error(changeset, :sale_price, "sale_price required when sale_ends_at is set")

      true ->
        changeset
    end
  end

  def item_types, do: @item_types

  @doc "Check if item is currently on sale."
  def on_sale?(%__MODULE__{sale_price: nil}), do: false
  def on_sale?(%__MODULE__{sale_ends_at: ends_at}) do
    DateTime.compare(DateTime.utc_now(), ends_at) == :lt
  end

  @doc "Check if item is marked as new."
  def is_new?(%__MODULE__{new_until: nil}), do: false
  def is_new?(%__MODULE__{new_until: new_until}) do
    DateTime.compare(DateTime.utc_now(), new_until) == :lt
  end

  @doc "Get effective price (sale price if on sale, otherwise regular price)."
  def effective_price(%__MODULE__{} = item, currency_type) do
    if on_sale?(item) do
      item.sale_price
    else
      case currency_type do
        :premium -> item.premium_price
        :bonus -> item.bonus_price
        :gold -> item.gold_price
      end
    end
  end
end
