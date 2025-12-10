defmodule BezgelorDb.Schema.AccountCurrency do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "account_currencies" do
    belongs_to :account, BezgelorDb.Schema.Account

    field :premium_currency, :integer, default: 0
    field :bonus_currency, :integer, default: 0

    timestamps(type: :utc_datetime)
  end

  def changeset(currency, attrs) do
    currency
    |> cast(attrs, [:account_id, :premium_currency, :bonus_currency])
    |> validate_required([:account_id])
    |> validate_number(:premium_currency, greater_than_or_equal_to: 0)
    |> validate_number(:bonus_currency, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:account_id)
    |> unique_constraint(:account_id)
  end

  def add_premium_changeset(currency, amount) do
    new_amount = currency.premium_currency + amount
    change(currency, premium_currency: new_amount)
  end

  def deduct_premium_changeset(currency, amount) do
    new_amount = currency.premium_currency - amount
    if new_amount >= 0 do
      {:ok, change(currency, premium_currency: new_amount)}
    else
      {:error, :insufficient_funds}
    end
  end

  def add_bonus_changeset(currency, amount) do
    new_amount = currency.bonus_currency + amount
    change(currency, bonus_currency: new_amount)
  end

  def deduct_bonus_changeset(currency, amount) do
    new_amount = currency.bonus_currency - amount
    if new_amount >= 0 do
      {:ok, change(currency, bonus_currency: new_amount)}
    else
      {:error, :insufficient_funds}
    end
  end
end
