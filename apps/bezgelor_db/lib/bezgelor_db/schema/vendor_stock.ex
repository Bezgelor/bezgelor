defmodule BezgelorDb.Schema.VendorStock do
  @moduledoc """
  Tracks limited stock items for vendors.

  Most vendor items have unlimited quantity (-1 in game data) and don't need
  database tracking. This schema only stores items with limited quantities
  that change when players purchase them.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer(),
          vendor_id: integer(),
          item_id: integer(),
          quantity_remaining: integer(),
          last_restock_at: DateTime.t() | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  schema "vendor_stock" do
    field :vendor_id, :integer
    field :item_id, :integer
    field :quantity_remaining, :integer
    field :last_restock_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc "Creates a changeset for vendor stock."
  def changeset(stock, attrs) do
    stock
    |> cast(attrs, [:vendor_id, :item_id, :quantity_remaining, :last_restock_at])
    |> validate_required([:vendor_id, :item_id, :quantity_remaining])
    |> validate_number(:quantity_remaining, greater_than_or_equal_to: 0)
    |> unique_constraint([:vendor_id, :item_id])
  end
end
