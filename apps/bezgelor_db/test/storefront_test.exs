defmodule BezgelorDb.StorefrontTest do
  use ExUnit.Case

  alias BezgelorDb.{Accounts, Collections, Storefront, Repo}

  alias BezgelorDb.Schema.{
    AccountCurrency,
    DailyDeal,
    PromoCode,
    StoreCategory,
    StoreItem,
    StorePromotion
  }

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
    |> AccountCurrency.changeset(%{
      account_id: account.id,
      premium_currency: 1000,
      bonus_currency: 500
    })
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

    test "create_store_item creates item" do
      {:ok, item} =
        Storefront.create_store_item(%{
          item_type: "pet",
          item_id: 6001,
          name: "Fluffy Cat",
          bonus_price: 50
        })

      assert item.name == "Fluffy Cat"
      assert item.item_type == "pet"
    end

    test "list_featured_items returns featured items" do
      # Create a featured item
      {:ok, _item} =
        Storefront.create_store_item(%{
          item_type: "costume",
          item_id: 7001,
          name: "Shiny Outfit",
          premium_price: 200,
          featured: true
        })

      items = Storefront.list_featured_items()
      assert Enum.all?(items, & &1.featured)
    end

    test "list_sale_items returns items on sale" do
      sale_ends = DateTime.add(DateTime.utc_now(), 3600, :second)

      {:ok, _item} =
        Storefront.create_store_item(%{
          item_type: "dye",
          item_id: 8001,
          name: "Red Dye",
          premium_price: 100,
          sale_price: 50,
          sale_ends_at: sale_ends
        })

      items = Storefront.list_sale_items()
      assert length(items) >= 1
    end
  end

  describe "purchases" do
    test "purchase_item deducts premium currency", %{account: account, store_item: store_item} do
      {:ok, _purchase} = Storefront.purchase_item(account.id, store_item.id, :premium)

      currency = Repo.get_by(AccountCurrency, account_id: account.id)
      # 1000 - 100
      assert currency.premium_currency == 900
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

    test "get_purchase_history returns account purchases", %{
      account: account,
      store_item: store_item
    } do
      {:ok, _} = Storefront.purchase_item(account.id, store_item.id, :premium)

      history = Storefront.get_purchase_history(account.id)
      assert length(history) == 1
    end
  end

  describe "categories" do
    test "create and list categories" do
      {:ok, category} =
        Storefront.create_category(%{
          name: "Mounts",
          slug: "mounts-#{System.unique_integer([:positive])}"
        })

      categories = Storefront.list_categories()
      assert Enum.any?(categories, &(&1.id == category.id))
    end

    test "get_category_by_slug returns category" do
      slug = "test-category-#{System.unique_integer([:positive])}"
      {:ok, _category} = Storefront.create_category(%{name: "Test", slug: slug})

      {:ok, found} = Storefront.get_category_by_slug(slug)
      assert found.slug == slug
    end

    test "hierarchical categories" do
      {:ok, parent} =
        Storefront.create_category(%{
          name: "Parent",
          slug: "parent-#{System.unique_integer([:positive])}"
        })

      {:ok, child} =
        Storefront.create_category(%{
          name: "Child",
          slug: "child-#{System.unique_integer([:positive])}",
          parent_id: parent.id
        })

      children = Storefront.get_subcategories(parent.id)
      assert Enum.any?(children, &(&1.id == child.id))
    end

    test "list_items_by_category" do
      {:ok, category} =
        Storefront.create_category(%{
          name: "Pets",
          slug: "pets-#{System.unique_integer([:positive])}"
        })

      {:ok, item} =
        Storefront.create_store_item(%{
          item_type: "pet",
          item_id: 9001,
          name: "Test Pet",
          premium_price: 100,
          category_id: category.id
        })

      items = Storefront.list_items_by_category(category.id)
      assert Enum.any?(items, &(&1.id == item.id))
    end
  end

  describe "promotions" do
    test "create and list promotions" do
      now = DateTime.utc_now()
      starts = DateTime.add(now, -3600, :second)
      ends = DateTime.add(now, 3600, :second)

      {:ok, promo} =
        Storefront.create_promotion(%{
          name: "Summer Sale",
          promotion_type: "sale",
          discount_percent: 20,
          starts_at: starts,
          ends_at: ends
        })

      promos = Storefront.list_active_promotions()
      assert Enum.any?(promos, &(&1.id == promo.id))
    end

    test "get_applicable_promotion finds promotion for item", %{store_item: store_item} do
      now = DateTime.utc_now()
      starts = DateTime.add(now, -3600, :second)
      ends = DateTime.add(now, 3600, :second)

      # Create promotion that applies to all items
      {:ok, _promo} =
        Storefront.create_promotion(%{
          name: "Store-wide Sale",
          promotion_type: "sale",
          discount_percent: 10,
          starts_at: starts,
          ends_at: ends,
          applies_to: %{}
        })

      promo = Storefront.get_applicable_promotion(store_item)
      assert promo != nil
    end
  end

  describe "daily deals" do
    test "create and get daily deals", %{store_item: store_item} do
      today = Date.utc_today()

      {:ok, deal} =
        Storefront.create_daily_deal(%{
          store_item_id: store_item.id,
          discount_percent: 30,
          active_date: today
        })

      deals = Storefront.get_daily_deals()
      assert Enum.any?(deals, &(&1.id == deal.id))
    end

    test "daily deal calculates discounted price", %{store_item: store_item} do
      today = Date.utc_today()

      {:ok, deal} =
        Storefront.create_daily_deal(%{
          store_item_id: store_item.id,
          discount_percent: 25,
          active_date: today
        })

      discounted = DailyDeal.calculate_price(deal, 100)
      # 100 - 25%
      assert discounted == 75
    end

    test "purchase daily deal applies discount", %{account: account, store_item: store_item} do
      today = Date.utc_today()

      {:ok, deal} =
        Storefront.create_daily_deal(%{
          store_item_id: store_item.id,
          discount_percent: 50,
          active_date: today
        })

      {:ok, purchase} = Storefront.purchase_daily_deal(account.id, deal.id, :premium)

      # Original price 100, 50% off = 50
      assert purchase.amount_paid == 50
      assert purchase.discount_applied == 50
    end
  end

  describe "promo codes" do
    test "create and validate promo code", %{account: account} do
      {:ok, promo} =
        Storefront.create_promo_code(%{
          code: "SAVE20",
          code_type: "discount",
          discount_percent: 20
        })

      {:ok, validated} = Storefront.validate_promo_code("save20", account.id)
      assert validated.id == promo.id
    end

    test "promo code is case insensitive", %{account: account} do
      {:ok, promo} =
        Storefront.create_promo_code(%{
          code: "TESTCODE",
          code_type: "discount",
          discount_percent: 10
        })

      {:ok, validated} = Storefront.validate_promo_code("testcode", account.id)
      assert validated.id == promo.id
    end

    test "expired promo code returns error", %{account: account} do
      past = DateTime.add(DateTime.utc_now(), -86400, :second)

      {:ok, _promo} =
        Storefront.create_promo_code(%{
          code: "EXPIRED123",
          code_type: "discount",
          discount_percent: 10,
          ends_at: past
        })

      {:error, :expired} = Storefront.validate_promo_code("EXPIRED123", account.id)
    end

    test "apply_promo_code calculates discount" do
      promo = %PromoCode{code_type: "discount", discount_percent: 25}
      {:ok, discount} = Storefront.apply_promo_code(promo, 100)
      assert discount == 25
    end

    test "purchase with promo code", %{account: account, store_item: store_item} do
      {:ok, _promo} =
        Storefront.create_promo_code(%{
          code: "DISCOUNT30",
          code_type: "discount",
          discount_percent: 30
        })

      {:ok, purchase} =
        Storefront.purchase_item(
          account.id,
          store_item.id,
          :premium,
          promo_code: "DISCOUNT30"
        )

      # 100 - 30% = 70
      assert purchase.amount_paid == 70
      assert purchase.discount_applied == 30
    end

    test "promo code tracks redemption", %{account: account, store_item: store_item} do
      {:ok, promo} =
        Storefront.create_promo_code(%{
          code: "ONCE123",
          code_type: "discount",
          discount_percent: 10,
          uses_per_account: 1
        })

      # First use should work
      {:ok, _} =
        Storefront.purchase_item(account.id, store_item.id, :premium, promo_code: "ONCE123")

      # Create another item to purchase
      {:ok, item2} =
        Storefront.create_store_item(%{
          item_type: "dye",
          item_id: 9999,
          name: "Another Item",
          premium_price: 50
        })

      # Second use should fail
      {:error, {:invalid_promo, :already_redeemed}} =
        Storefront.purchase_item(account.id, item2.id, :premium, promo_code: "ONCE123")
    end
  end

  describe "schema helpers" do
    test "StoreItem.on_sale? returns true for items on sale" do
      sale_ends = DateTime.add(DateTime.utc_now(), 3600, :second)
      item = %StoreItem{sale_price: 50, sale_ends_at: sale_ends}
      assert StoreItem.on_sale?(item)
    end

    test "StoreItem.on_sale? returns false for expired sales" do
      sale_ends = DateTime.add(DateTime.utc_now(), -3600, :second)
      item = %StoreItem{sale_price: 50, sale_ends_at: sale_ends}
      refute StoreItem.on_sale?(item)
    end

    test "StoreItem.is_new? returns true for new items" do
      new_until = DateTime.add(DateTime.utc_now(), 3600, :second)
      item = %StoreItem{new_until: new_until}
      assert StoreItem.is_new?(item)
    end

    test "DailyDeal.available? checks stock" do
      deal = %DailyDeal{quantity_limit: 10, quantity_sold: 5}
      assert DailyDeal.available?(deal)

      sold_out = %DailyDeal{quantity_limit: 10, quantity_sold: 10}
      refute DailyDeal.available?(sold_out)
    end

    test "PromoCode.usable? checks active and limits" do
      active = %PromoCode{
        is_active: true,
        max_uses: nil,
        current_uses: 0,
        starts_at: nil,
        ends_at: nil
      }

      assert PromoCode.usable?(active)

      inactive = %PromoCode{is_active: false}
      refute PromoCode.usable?(inactive)

      exhausted = %PromoCode{is_active: true, max_uses: 5, current_uses: 5}
      refute PromoCode.usable?(exhausted)
    end

    test "StorePromotion.active? checks time window" do
      now = DateTime.utc_now()
      starts = DateTime.add(now, -3600, :second)
      ends = DateTime.add(now, 3600, :second)

      active = %StorePromotion{is_active: true, starts_at: starts, ends_at: ends}
      assert StorePromotion.active?(active)

      inactive = %StorePromotion{is_active: false, starts_at: starts, ends_at: ends}
      refute StorePromotion.active?(inactive)
    end
  end
end
