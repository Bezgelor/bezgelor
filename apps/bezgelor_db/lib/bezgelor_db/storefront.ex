defmodule BezgelorDb.Storefront do
  @moduledoc """
  Storefront context for managing store items and purchases.
  """

  import Ecto.Query
  alias BezgelorDb.Repo
  alias BezgelorDb.Schema.{StoreItem, StorePurchase, AccountCurrency}
  alias BezgelorDb.Collections
  alias Ecto.Multi

  # Store Item Queries

  @spec list_available_items() :: [StoreItem.t()]
  def list_available_items do
    now = DateTime.utc_now()

    StoreItem
    |> where([i], i.active == true)
    |> where([i], is_nil(i.available_from) or i.available_from <= ^now)
    |> where([i], is_nil(i.available_until) or i.available_until >= ^now)
    |> order_by([i], [desc: i.featured, asc: i.name])
    |> Repo.all()
  end

  @spec get_store_item(integer()) :: {:ok, StoreItem.t()} | {:error, :not_found}
  def get_store_item(id) do
    case Repo.get(StoreItem, id) do
      nil -> {:error, :not_found}
      item -> {:ok, item}
    end
  end

  @spec list_by_category(String.t()) :: [StoreItem.t()]
  def list_by_category(category) do
    now = DateTime.utc_now()

    StoreItem
    |> where([i], i.active == true and i.category == ^category)
    |> where([i], is_nil(i.available_from) or i.available_from <= ^now)
    |> where([i], is_nil(i.available_until) or i.available_until >= ^now)
    |> order_by([i], [desc: i.featured, asc: i.name])
    |> Repo.all()
  end

  # Purchases

  @spec purchase_item(integer(), integer(), :premium | :bonus | :gold) ::
          {:ok, StorePurchase.t()} | {:error, :not_found | :insufficient_funds | :no_price | term()}
  def purchase_item(account_id, store_item_id, currency_type) do
    with {:ok, item} <- get_store_item(store_item_id),
         {:ok, price} <- get_price(item, currency_type),
         {:ok, result} <- execute_purchase(account_id, item, currency_type, price) do
      {:ok, result.purchase}
    else
      {:error, :currency, :insufficient_funds, _} -> {:error, :insufficient_funds}
      {:error, _} = error -> error
    end
  end

  defp get_price(item, :premium), do: price_or_error(item.premium_price)
  defp get_price(item, :bonus), do: price_or_error(item.bonus_price)
  defp get_price(item, :gold), do: price_or_error(item.gold_price)

  defp price_or_error(nil), do: {:error, :no_price}
  defp price_or_error(price), do: {:ok, price}

  defp execute_purchase(account_id, item, currency_type, price) do
    Multi.new()
    |> Multi.run(:currency, fn _repo, _changes ->
      deduct_currency(account_id, currency_type, price)
    end)
    |> Multi.run(:unlock, fn _repo, _changes ->
      unlock_collectible(account_id, item)
    end)
    |> Multi.insert(:purchase, fn _changes ->
      %StorePurchase{}
      |> StorePurchase.changeset(%{
        account_id: account_id,
        store_item_id: item.id,
        currency_type: Atom.to_string(currency_type),
        amount_paid: price
      })
    end)
    |> Repo.transaction()
  end

  defp deduct_currency(account_id, currency_type, amount) do
    currency = Repo.get_by(AccountCurrency, account_id: account_id)

    if currency do
      case currency_type do
        :premium ->
          case AccountCurrency.deduct_premium_changeset(currency, amount) do
            {:ok, changeset} -> Repo.update(changeset)
            {:error, _} = error -> error
          end

        :bonus ->
          case AccountCurrency.deduct_bonus_changeset(currency, amount) do
            {:ok, changeset} -> Repo.update(changeset)
            {:error, _} = error -> error
          end

        :gold ->
          # Gold is character-level, handled differently
          {:ok, currency}
      end
    else
      {:error, :insufficient_funds}
    end
  end

  defp unlock_collectible(account_id, %{item_type: "mount", item_id: item_id}) do
    Collections.unlock_account_mount(account_id, item_id, "store")
  end

  defp unlock_collectible(account_id, %{item_type: "pet", item_id: item_id}) do
    Collections.unlock_account_pet(account_id, item_id, "store")
  end

  defp unlock_collectible(_account_id, _item) do
    # Other item types (costume, dye, service) handled separately
    {:ok, :no_collectible}
  end

  # Purchase History

  @spec get_purchase_history(integer()) :: [StorePurchase.t()]
  def get_purchase_history(account_id) do
    StorePurchase
    |> where([p], p.account_id == ^account_id)
    |> order_by([p], desc: p.inserted_at)
    |> preload(:store_item)
    |> Repo.all()
  end
end
