defmodule BezgelorDb.StorefrontTest do
  use ExUnit.Case

  alias BezgelorDb.{Accounts, Collections, Storefront, Repo}
  alias BezgelorDb.Schema.{AccountCurrency, StoreItem}

  @moduletag :database

  setup do
    case Repo.start_link([]) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    email = "store_test#{System.unique_integer([:positive])}@test.com"
    {:ok, account} = Accounts.create_account(email, "password123")

    # Give account some currency
    %AccountCurrency{}
    |> AccountCurrency.changeset(%{account_id: account.id, premium_currency: 1000, bonus_currency: 500})
    |> Repo.insert!()

    # Create a store item
    {:ok, store_item} =
      %StoreItem{}
      |> StoreItem.changeset(%{
        item_type: "mount",
        item_id: 5001,
        name: "Sparkle Horse",
        premium_price: 100,
        category: "mounts"
      })
      |> Repo.insert()

    {:ok, account: account, store_item: store_item}
  end

  describe "store items" do
    test "list_available_items returns active items", %{store_item: store_item} do
      items = Storefront.list_available_items()
      assert length(items) >= 1
      assert Enum.any?(items, &(&1.id == store_item.id))
    end

    test "get_store_item returns item by id", %{store_item: store_item} do
      {:ok, item} = Storefront.get_store_item(store_item.id)
      assert item.name == "Sparkle Horse"
    end

    test "list_by_category filters items", %{store_item: _store_item} do
      items = Storefront.list_by_category("mounts")
      assert length(items) >= 1
      assert Enum.all?(items, &(&1.category == "mounts"))
    end
  end

  describe "purchases" do
    test "purchase_item deducts premium currency", %{account: account, store_item: store_item} do
      {:ok, _purchase} = Storefront.purchase_item(account.id, store_item.id, :premium)

      currency = Repo.get_by(AccountCurrency, account_id: account.id)
      assert currency.premium_currency == 900  # 1000 - 100
    end

    test "purchase_item unlocks collectible", %{account: account, store_item: store_item} do
      {:ok, _purchase} = Storefront.purchase_item(account.id, store_item.id, :premium)

      # Mount should be unlocked
      mounts = Collections.get_account_mounts(account.id)
      assert 5001 in mounts
    end

    test "purchase_item fails with insufficient funds", %{account: account} do
      # Create expensive item
      {:ok, expensive} =
        %StoreItem{}
        |> StoreItem.changeset(%{
          item_type: "mount",
          item_id: 5002,
          name: "Diamond Steed",
          premium_price: 9999
        })
        |> Repo.insert()

      {:error, :insufficient_funds} = Storefront.purchase_item(account.id, expensive.id, :premium)
    end

    test "purchase_item records purchase history", %{account: account, store_item: store_item} do
      {:ok, purchase} = Storefront.purchase_item(account.id, store_item.id, :premium)

      assert purchase.account_id == account.id
      assert purchase.store_item_id == store_item.id
      assert purchase.currency_type == "premium"
      assert purchase.amount_paid == 100
    end

    test "get_purchase_history returns account purchases", %{account: account, store_item: store_item} do
      {:ok, _} = Storefront.purchase_item(account.id, store_item.id, :premium)

      history = Storefront.get_purchase_history(account.id)
      assert length(history) == 1
    end
  end
end
