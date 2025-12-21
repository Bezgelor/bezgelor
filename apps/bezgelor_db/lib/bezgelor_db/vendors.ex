defmodule BezgelorDb.Vendors do
  @moduledoc """
  Context for vendor operations.

  Handles limited stock management for vendors. Static vendor data (items,
  prices, types) is loaded from game data via BezgelorData.Store.
  This module manages dynamic state like limited stock quantities.
  """

  import Ecto.Query
  alias BezgelorDb.Repo
  alias BezgelorDb.Schema.VendorStock

  @doc """
  Get remaining quantity for a limited stock item.
  Returns nil if item is unlimited (not tracked in DB).
  """
  @spec get_stock(integer(), integer()) :: integer() | nil
  def get_stock(vendor_id, item_id) do
    query =
      from(s in VendorStock,
        where: s.vendor_id == ^vendor_id and s.item_id == ^item_id,
        select: s.quantity_remaining
      )

    Repo.one(query)
  end

  @doc """
  Initialize stock for a limited quantity item.
  Called when vendor is first loaded or after restock.
  """
  @spec init_stock(integer(), integer(), integer()) :: {:ok, VendorStock.t()} | {:error, term()}
  def init_stock(vendor_id, item_id, quantity) do
    %VendorStock{}
    |> VendorStock.changeset(%{
      vendor_id: vendor_id,
      item_id: item_id,
      quantity_remaining: quantity,
      last_restock_at: DateTime.utc_now()
    })
    |> Repo.insert(
      on_conflict: {:replace, [:quantity_remaining, :last_restock_at, :updated_at]},
      conflict_target: [:vendor_id, :item_id]
    )
  end

  @doc """
  Decrement stock when player purchases item.
  Returns {:ok, remaining} or {:error, :out_of_stock}.
  """
  @spec purchase_item(integer(), integer(), integer()) :: {:ok, integer()} | {:error, atom()}
  def purchase_item(vendor_id, item_id, quantity \\ 1) do
    query =
      from(s in VendorStock,
        where:
          s.vendor_id == ^vendor_id and s.item_id == ^item_id and
            s.quantity_remaining >= ^quantity
      )

    case Repo.update_all(query, inc: [quantity_remaining: -quantity]) do
      {1, _} ->
        remaining = get_stock(vendor_id, item_id)
        {:ok, remaining}

      {0, _} ->
        {:error, :out_of_stock}
    end
  end

  @doc """
  Restock a vendor's limited items to full quantity.
  """
  @spec restock_vendor(integer(), [{integer(), integer()}]) :: :ok
  def restock_vendor(vendor_id, items) do
    now = DateTime.utc_now()

    Enum.each(items, fn {item_id, quantity} ->
      init_stock(vendor_id, item_id, quantity)
    end)

    # Update restock timestamp for all vendor items
    from(s in VendorStock, where: s.vendor_id == ^vendor_id)
    |> Repo.update_all(set: [last_restock_at: now])

    :ok
  end

  @doc """
  Get all limited stock items for a vendor with their current quantities.
  """
  @spec get_vendor_stock(integer()) :: [VendorStock.t()]
  def get_vendor_stock(vendor_id) do
    from(s in VendorStock, where: s.vendor_id == ^vendor_id)
    |> Repo.all()
  end

  @doc """
  Check if item is in stock.
  Returns true for unlimited items (not in DB) or items with quantity > 0.
  """
  @spec in_stock?(integer(), integer()) :: boolean()
  def in_stock?(vendor_id, item_id) do
    case get_stock(vendor_id, item_id) do
      # Not tracked = unlimited
      nil -> true
      qty -> qty > 0
    end
  end
end
