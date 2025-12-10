defmodule BezgelorDb.Schema.StorePurchase do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @currency_types ~w(premium bonus gold)

  schema "store_purchases" do
    belongs_to :account, BezgelorDb.Schema.Account
    belongs_to :store_item, BezgelorDb.Schema.StoreItem

    field :currency_type, :string
    field :amount_paid, :integer
    field :character_id, :integer

    timestamps(type: :utc_datetime)
  end

  def changeset(purchase, attrs) do
    purchase
    |> cast(attrs, [:account_id, :store_item_id, :currency_type, :amount_paid, :character_id])
    |> validate_required([:account_id, :store_item_id, :currency_type, :amount_paid])
    |> validate_inclusion(:currency_type, @currency_types)
    |> validate_number(:amount_paid, greater_than: 0)
    |> foreign_key_constraint(:account_id)
    |> foreign_key_constraint(:store_item_id)
  end

  def currency_types, do: @currency_types
end
