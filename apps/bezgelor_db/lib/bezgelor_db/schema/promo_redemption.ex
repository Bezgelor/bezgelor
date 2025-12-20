defmodule BezgelorDb.Schema.PromoRedemption do
  @moduledoc """
  Promo code redemption schema for tracking per-account usage.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "promo_redemptions" do
    belongs_to(:promo_code, BezgelorDb.Schema.PromoCode)
    belongs_to(:account, BezgelorDb.Schema.Account)
    belongs_to(:purchase, BezgelorDb.Schema.StorePurchase)

    field(:redeemed_at, :utc_datetime)

    timestamps(type: :utc_datetime)
  end

  def changeset(redemption, attrs) do
    redemption
    |> cast(attrs, [:promo_code_id, :account_id, :purchase_id, :redeemed_at])
    |> validate_required([:promo_code_id, :account_id, :redeemed_at])
    |> foreign_key_constraint(:promo_code_id)
    |> foreign_key_constraint(:account_id)
    |> foreign_key_constraint(:purchase_id)
  end
end
