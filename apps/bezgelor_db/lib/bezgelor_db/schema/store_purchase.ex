defmodule BezgelorDb.Schema.StorePurchase do
  @moduledoc """
  Store purchase schema representing completed transactions.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @currency_types ~w(premium bonus gold)

  schema "store_purchases" do
    belongs_to :account, BezgelorDb.Schema.Account
    belongs_to :store_item, BezgelorDb.Schema.StoreItem
    belongs_to :promo_code, BezgelorDb.Schema.PromoCode
    belongs_to :promotion, BezgelorDb.Schema.StorePromotion
    belongs_to :daily_deal, BezgelorDb.Schema.DailyDeal

    field :currency_type, :string
    field :amount_paid, :integer
    field :character_id, :integer

    # New fields from migration
    field :original_price, :integer
    field :discount_applied, :integer, default: 0
    field :metadata, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  def changeset(purchase, attrs) do
    purchase
    |> cast(attrs, [
      :account_id, :store_item_id, :currency_type, :amount_paid, :character_id,
      :promo_code_id, :promotion_id, :daily_deal_id,
      :original_price, :discount_applied, :metadata
    ])
    |> validate_required([:account_id, :store_item_id, :currency_type, :amount_paid])
    |> validate_inclusion(:currency_type, @currency_types)
    |> validate_number(:amount_paid, greater_than_or_equal_to: 0)
    |> validate_number(:original_price, greater_than: 0)
    |> validate_number(:discount_applied, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:account_id)
    |> foreign_key_constraint(:store_item_id)
    |> foreign_key_constraint(:promo_code_id)
    |> foreign_key_constraint(:promotion_id)
    |> foreign_key_constraint(:daily_deal_id)
  end

  def currency_types, do: @currency_types

  @doc "Check if purchase had any discount applied."
  def discounted?(%__MODULE__{discount_applied: discount}) when discount > 0, do: true
  def discounted?(_), do: false
end
