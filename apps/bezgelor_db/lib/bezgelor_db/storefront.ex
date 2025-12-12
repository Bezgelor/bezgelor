defmodule BezgelorDb.Storefront do
  @moduledoc """
  Storefront context for managing store items, categories, promotions, and purchases.

  ## Features

  - **Categories**: Hierarchical organization of store items
  - **Store Items**: Products available for purchase with multiple currency options
  - **Promotions**: Time-limited sales, bundles, and bonus currency events
  - **Daily Deals**: Rotating featured items with discounts
  - **Promo Codes**: Redeemable codes for discounts, items, or currency
  - **Purchases**: Transaction history with discount tracking
  """

  import Ecto.Query
  alias BezgelorDb.Repo

  alias BezgelorDb.Schema.{
    AccountCurrency,
    DailyDeal,
    PromoCode,
    PromoRedemption,
    StoreCategory,
    StoreItem,
    StorePromotion,
    StorePurchase
  }

  alias BezgelorDb.Collections
  alias Ecto.Multi

  # ============================================================================
  # Categories
  # ============================================================================

  @doc "List all active categories."
  @spec list_categories() :: [StoreCategory.t()]
  def list_categories do
    StoreCategory
    |> where([c], c.is_active == true)
    |> order_by([c], [asc: c.sort_order, asc: c.name])
    |> Repo.all()
  end

  @doc "List root categories (no parent)."
  @spec list_root_categories() :: [StoreCategory.t()]
  def list_root_categories do
    StoreCategory
    |> where([c], c.is_active == true and is_nil(c.parent_id))
    |> order_by([c], [asc: c.sort_order, asc: c.name])
    |> Repo.all()
  end

  @doc "Get category by slug."
  @spec get_category_by_slug(String.t()) :: {:ok, StoreCategory.t()} | {:error, :not_found}
  def get_category_by_slug(slug) do
    case Repo.get_by(StoreCategory, slug: slug, is_active: true) do
      nil -> {:error, :not_found}
      category -> {:ok, category}
    end
  end

  @doc "Get subcategories of a category."
  @spec get_subcategories(integer()) :: [StoreCategory.t()]
  def get_subcategories(parent_id) do
    StoreCategory
    |> where([c], c.parent_id == ^parent_id and c.is_active == true)
    |> order_by([c], [asc: c.sort_order, asc: c.name])
    |> Repo.all()
  end

  @doc "Create a category."
  @spec create_category(map()) :: {:ok, StoreCategory.t()} | {:error, Ecto.Changeset.t()}
  def create_category(attrs) do
    %StoreCategory{}
    |> StoreCategory.changeset(attrs)
    |> Repo.insert()
  end

  # ============================================================================
  # Store Items
  # ============================================================================

  @doc "List all available store items."
  @spec list_available_items() :: [StoreItem.t()]
  def list_available_items do
    now = DateTime.utc_now()

    StoreItem
    |> where([i], i.active == true)
    |> where([i], is_nil(i.available_from) or i.available_from <= ^now)
    |> where([i], is_nil(i.available_until) or i.available_until >= ^now)
    |> order_by([i], [desc: i.featured, asc: i.sort_order, asc: i.name])
    |> Repo.all()
  end

  @doc "List items by category ID."
  @spec list_items_by_category(integer()) :: [StoreItem.t()]
  def list_items_by_category(category_id) do
    now = DateTime.utc_now()

    StoreItem
    |> where([i], i.active == true and i.category_id == ^category_id)
    |> where([i], is_nil(i.available_from) or i.available_from <= ^now)
    |> where([i], is_nil(i.available_until) or i.available_until >= ^now)
    |> order_by([i], [desc: i.featured, asc: i.sort_order, asc: i.name])
    |> Repo.all()
  end

  @doc "List items by category slug (legacy support)."
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

  @doc "List featured items."
  @spec list_featured_items(integer()) :: [StoreItem.t()]
  def list_featured_items(limit \\ 10) do
    now = DateTime.utc_now()

    StoreItem
    |> where([i], i.active == true and i.featured == true)
    |> where([i], is_nil(i.available_from) or i.available_from <= ^now)
    |> where([i], is_nil(i.available_until) or i.available_until >= ^now)
    |> order_by([i], [asc: i.sort_order, asc: i.name])
    |> limit(^limit)
    |> Repo.all()
  end

  @doc "List items on sale."
  @spec list_sale_items() :: [StoreItem.t()]
  def list_sale_items do
    now = DateTime.utc_now()

    StoreItem
    |> where([i], i.active == true and not is_nil(i.sale_price))
    |> where([i], i.sale_ends_at > ^now)
    |> order_by([i], [asc: i.sale_ends_at, asc: i.name])
    |> Repo.all()
  end

  @doc "List new items."
  @spec list_new_items() :: [StoreItem.t()]
  def list_new_items do
    now = DateTime.utc_now()

    StoreItem
    |> where([i], i.active == true and not is_nil(i.new_until))
    |> where([i], i.new_until > ^now)
    |> order_by([i], [desc: i.inserted_at, asc: i.name])
    |> Repo.all()
  end

  @doc "Get store item by ID."
  @spec get_store_item(integer()) :: {:ok, StoreItem.t()} | {:error, :not_found}
  def get_store_item(id) do
    case Repo.get(StoreItem, id) do
      nil -> {:error, :not_found}
      item -> {:ok, item}
    end
  end

  @doc "Create a store item."
  @spec create_store_item(map()) :: {:ok, StoreItem.t()} | {:error, Ecto.Changeset.t()}
  def create_store_item(attrs) do
    %StoreItem{}
    |> StoreItem.changeset(attrs)
    |> Repo.insert()
  end

  # ============================================================================
  # Promotions
  # ============================================================================

  @doc "List active promotions."
  @spec list_active_promotions() :: [StorePromotion.t()]
  def list_active_promotions do
    now = DateTime.utc_now()

    StorePromotion
    |> where([p], p.is_active == true)
    |> where([p], p.starts_at <= ^now and p.ends_at >= ^now)
    |> order_by([p], [asc: p.ends_at])
    |> Repo.all()
  end

  @doc """
  Get applicable promotion for an item.

  Filters promotions in database using JSONB operators instead of loading all
  promotions and filtering in memory.
  """
  @spec get_applicable_promotion(StoreItem.t()) :: StorePromotion.t() | nil
  def get_applicable_promotion(%StoreItem{id: item_id, category_id: category_id}) do
    now = DateTime.utc_now()

    # Build query that filters in database using JSONB operators
    # This replaces the previous pattern of loading all promotions and filtering in memory
    base_query =
      StorePromotion
      |> where([p], p.is_active == true)
      |> where([p], p.starts_at <= ^now and p.ends_at >= ^now)

    # Filter by applicability in the database:
    # - Empty/null applies_to means applies to all items
    # - Check if item_id is in the item_ids array
    # - Check if category_id is in the category_ids array (conditionally added)
    query =
      base_query
      |> where(
        [p],
        # Empty applies_to means applies to all
        is_nil(p.applies_to) or
          p.applies_to == ^%{} or
          # Item ID is in the promotion's item_ids array
          fragment("?->'item_ids' @> ?::jsonb", p.applies_to, ^[item_id])
      )

    # Add category check if category_id is not nil
    query =
      if category_id do
        query
        |> or_where(
          [p],
          p.is_active == true and
            p.starts_at <= ^now and p.ends_at >= ^now and
            fragment("?->'category_ids' @> ?::jsonb", p.applies_to, ^[category_id])
        )
      else
        query
      end

    query
    |> order_by([p], desc: p.discount_percent)
    |> limit(1)
    |> Repo.one()
  end

  @doc "Create a promotion."
  @spec create_promotion(map()) :: {:ok, StorePromotion.t()} | {:error, Ecto.Changeset.t()}
  def create_promotion(attrs) do
    %StorePromotion{}
    |> StorePromotion.changeset(attrs)
    |> Repo.insert()
  end

  # ============================================================================
  # Daily Deals
  # ============================================================================

  @doc "Get today's daily deals."
  @spec get_daily_deals() :: [DailyDeal.t()]
  def get_daily_deals do
    today = Date.utc_today()

    DailyDeal
    |> where([d], d.active_date == ^today)
    |> preload(:store_item)
    |> Repo.all()
    |> Enum.filter(&DailyDeal.available?/1)
  end

  @doc "Get daily deal by ID."
  @spec get_daily_deal(integer()) :: {:ok, DailyDeal.t()} | {:error, :not_found}
  def get_daily_deal(id) do
    case Repo.get(DailyDeal, id) |> Repo.preload(:store_item) do
      nil -> {:error, :not_found}
      deal -> {:ok, deal}
    end
  end

  @doc "Create a daily deal."
  @spec create_daily_deal(map()) :: {:ok, DailyDeal.t()} | {:error, Ecto.Changeset.t()}
  def create_daily_deal(attrs) do
    %DailyDeal{}
    |> DailyDeal.changeset(attrs)
    |> Repo.insert()
  end

  # ============================================================================
  # Promo Codes
  # ============================================================================

  @doc "Validate and get promo code."
  @spec validate_promo_code(String.t(), integer()) ::
          {:ok, PromoCode.t()} | {:error, :not_found | :expired | :max_uses | :already_redeemed}
  def validate_promo_code(code, account_id) do
    normalized_code = String.upcase(code)

    case Repo.get_by(PromoCode, code: normalized_code) do
      nil ->
        {:error, :not_found}

      promo_code ->
        cond do
          not PromoCode.usable?(promo_code) ->
            {:error, :expired}

          exceeded_account_uses?(promo_code, account_id) ->
            {:error, :already_redeemed}

          true ->
            {:ok, promo_code}
        end
    end
  end

  defp exceeded_account_uses?(%PromoCode{id: promo_id, uses_per_account: max}, account_id) do
    count =
      PromoRedemption
      |> where([r], r.promo_code_id == ^promo_id and r.account_id == ^account_id)
      |> Repo.aggregate(:count)

    count >= max
  end

  @doc "Apply promo code to calculate discount."
  @spec apply_promo_code(PromoCode.t(), integer()) :: {:ok, integer()} | {:error, :not_applicable}
  def apply_promo_code(%PromoCode{code_type: "discount", discount_percent: pct}, price)
      when not is_nil(pct) do
    discount = trunc(price * pct / 100)
    {:ok, discount}
  end

  def apply_promo_code(%PromoCode{code_type: "discount", discount_amount: amt}, _price)
      when not is_nil(amt) do
    {:ok, amt}
  end

  def apply_promo_code(%PromoCode{code_type: "currency"}, _price) do
    # Currency codes don't affect purchase price
    {:ok, 0}
  end

  def apply_promo_code(%PromoCode{code_type: "item"}, _price) do
    # Item codes don't affect purchase price
    {:ok, 0}
  end

  def apply_promo_code(_, _), do: {:error, :not_applicable}

  @doc "Create a promo code."
  @spec create_promo_code(map()) :: {:ok, PromoCode.t()} | {:error, Ecto.Changeset.t()}
  def create_promo_code(attrs) do
    %PromoCode{}
    |> PromoCode.changeset(attrs)
    |> Repo.insert()
  end

  # ============================================================================
  # Purchases
  # ============================================================================

  @doc "Purchase an item."
  @spec purchase_item(integer(), integer(), :premium | :bonus | :gold, keyword()) ::
          {:ok, StorePurchase.t()}
          | {:error, :not_found | :insufficient_funds | :no_price | :invalid_promo | term()}
  def purchase_item(account_id, store_item_id, currency_type, opts \\ []) do
    promo_code = Keyword.get(opts, :promo_code)
    daily_deal_id = Keyword.get(opts, :daily_deal_id)
    character_id = Keyword.get(opts, :character_id)

    with {:ok, item} <- get_store_item(store_item_id),
         {:ok, base_price} <- get_price(item, currency_type),
         {:ok, promo, discount} <- resolve_promo_discount(promo_code, account_id, base_price),
         {:ok, deal, deal_discount} <- resolve_deal_discount(daily_deal_id, base_price),
         final_discount = max(discount, deal_discount),
         final_price = max(0, base_price - final_discount),
         {:ok, result} <-
           execute_purchase(account_id, item, currency_type, base_price, final_price, %{
             promo_code: promo,
             daily_deal: deal,
             discount: final_discount,
             character_id: character_id
           }) do
      {:ok, result.purchase}
    else
      {:error, :currency, :insufficient_funds, _} -> {:error, :insufficient_funds}
      {:error, _} = error -> error
    end
  end

  @doc "Purchase a daily deal."
  @spec purchase_daily_deal(integer(), integer(), :premium | :bonus | :gold) ::
          {:ok, StorePurchase.t()} | {:error, term()}
  def purchase_daily_deal(account_id, daily_deal_id, currency_type) do
    with {:ok, deal} <- get_daily_deal(daily_deal_id),
         true <- DailyDeal.available?(deal) do
      purchase_item(account_id, deal.store_item_id, currency_type, daily_deal_id: daily_deal_id)
    else
      false -> {:error, :deal_unavailable}
      error -> error
    end
  end

  defp get_price(item, :premium), do: price_or_error(item.premium_price)
  defp get_price(item, :bonus), do: price_or_error(item.bonus_price)
  defp get_price(item, :gold), do: price_or_error(item.gold_price)

  defp price_or_error(nil), do: {:error, :no_price}
  defp price_or_error(price), do: {:ok, price}

  defp resolve_promo_discount(nil, _account_id, _price), do: {:ok, nil, 0}

  defp resolve_promo_discount(code, account_id, price) do
    case validate_promo_code(code, account_id) do
      {:ok, promo} ->
        case apply_promo_code(promo, price) do
          {:ok, discount} -> {:ok, promo, discount}
          {:error, _} -> {:ok, promo, 0}
        end

      {:error, reason} ->
        {:error, {:invalid_promo, reason}}
    end
  end

  defp resolve_deal_discount(nil, _price), do: {:ok, nil, 0}

  defp resolve_deal_discount(deal_id, price) do
    case get_daily_deal(deal_id) do
      {:ok, deal} ->
        if DailyDeal.available?(deal) do
          discount = price - DailyDeal.calculate_price(deal, price)
          {:ok, deal, discount}
        else
          {:error, :deal_unavailable}
        end

      {:error, :not_found} ->
        {:error, :deal_not_found}
    end
  end

  defp execute_purchase(account_id, item, currency_type, original_price, final_price, context) do
    Multi.new()
    |> Multi.run(:currency, fn _repo, _changes ->
      deduct_currency(account_id, currency_type, final_price)
    end)
    |> Multi.run(:unlock, fn _repo, _changes ->
      unlock_collectible(account_id, item)
    end)
    |> Multi.run(:promo_redemption, fn _repo, _changes ->
      if context.promo_code do
        record_promo_redemption(context.promo_code, account_id)
      else
        {:ok, nil}
      end
    end)
    |> Multi.run(:deal_increment, fn _repo, _changes ->
      if context.daily_deal do
        increment_deal_sold(context.daily_deal)
      else
        {:ok, nil}
      end
    end)
    |> Multi.insert(:purchase, fn _changes ->
      %StorePurchase{}
      |> StorePurchase.changeset(%{
        account_id: account_id,
        store_item_id: item.id,
        currency_type: Atom.to_string(currency_type),
        amount_paid: final_price,
        original_price: original_price,
        discount_applied: context.discount,
        character_id: context.character_id,
        promo_code_id: context.promo_code && context.promo_code.id,
        daily_deal_id: context.daily_deal && context.daily_deal.id
      })
    end)
    |> Repo.transaction()
  end

  defp deduct_currency(account_id, currency_type, amount) do
    # Allow free items (amount = 0)
    if amount == 0 do
      {:ok, :free}
    else
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
  end

  defp unlock_collectible(account_id, %{item_type: "mount", item_id: item_id}) do
    Collections.unlock_account_mount(account_id, item_id, "store")
  end

  defp unlock_collectible(account_id, %{item_type: "pet", item_id: item_id}) do
    Collections.unlock_account_pet(account_id, item_id, "store")
  end

  defp unlock_collectible(_account_id, _item) do
    # Other item types (costume, dye, service, bundle) handled separately
    {:ok, :no_collectible}
  end

  defp record_promo_redemption(%PromoCode{id: promo_id} = _promo, account_id) do
    # Increment global uses
    Repo.update_all(
      from(p in PromoCode, where: p.id == ^promo_id),
      inc: [current_uses: 1]
    )

    # Record redemption
    %PromoRedemption{}
    |> PromoRedemption.changeset(%{
      promo_code_id: promo_id,
      account_id: account_id,
      redeemed_at: DateTime.utc_now()
    })
    |> Repo.insert()
  end

  defp increment_deal_sold(%DailyDeal{id: deal_id}) do
    {1, _} =
      Repo.update_all(
        from(d in DailyDeal, where: d.id == ^deal_id),
        inc: [quantity_sold: 1]
      )

    {:ok, :incremented}
  end

  # ============================================================================
  # Account Balance
  # ============================================================================

  @doc """
  Get account currency balance.

  Returns the account's premium and bonus currency amounts.

  ## Returns
    - `{:ok, %{premium: integer(), bonus: integer()}}` if found
    - `{:error, :not_found}` if no currency record exists
  """
  @spec get_account_balance(integer()) :: {:ok, map()} | {:error, :not_found}
  def get_account_balance(account_id) do
    case Repo.get_by(AccountCurrency, account_id: account_id) do
      nil ->
        {:error, :not_found}

      currency ->
        {:ok, %{premium: currency.premium_currency, bonus: currency.bonus_currency}}
    end
  end

  # ============================================================================
  # Purchase History
  # ============================================================================

  @doc "Get purchase history for an account."
  @spec get_purchase_history(integer()) :: [StorePurchase.t()]
  def get_purchase_history(account_id) do
    StorePurchase
    |> where([p], p.account_id == ^account_id)
    |> order_by([p], desc: p.inserted_at)
    |> preload([:store_item, :promo_code, :daily_deal])
    |> Repo.all()
  end

  @doc "Get recent purchases for an account."
  @spec get_recent_purchases(integer(), integer()) :: [StorePurchase.t()]
  def get_recent_purchases(account_id, limit \\ 10) do
    StorePurchase
    |> where([p], p.account_id == ^account_id)
    |> order_by([p], desc: p.inserted_at)
    |> limit(^limit)
    |> preload(:store_item)
    |> Repo.all()
  end

  # ============================================================================
  # Gifting
  # ============================================================================

  @doc """
  Gift a store item to another player.

  Creates a purchase for the gifter and unlocks the item for the recipient.
  """
  @spec gift_item(integer(), integer(), integer(), :premium | :bonus, String.t() | nil) ::
          {:ok, StorePurchase.t()}
          | {:error, :not_found | :insufficient_funds | :no_price | :recipient_not_found | term()}
  def gift_item(gifter_account_id, recipient_account_id, store_item_id, currency_type, message \\ nil) do
    with {:ok, item} <- get_store_item(store_item_id),
         {:ok, base_price} <- get_price(item, currency_type),
         {:ok, result} <-
           execute_gift(gifter_account_id, recipient_account_id, item, currency_type, base_price, message) do
      {:ok, result.purchase}
    else
      {:error, :currency, :insufficient_funds, _} -> {:error, :insufficient_funds}
      {:error, _} = error -> error
    end
  end

  defp execute_gift(gifter_account_id, recipient_account_id, item, currency_type, price, message) do
    Multi.new()
    |> Multi.run(:currency, fn _repo, _changes ->
      deduct_currency(gifter_account_id, currency_type, price)
    end)
    |> Multi.run(:unlock, fn _repo, _changes ->
      unlock_collectible(recipient_account_id, item)
    end)
    |> Multi.insert(:purchase, fn _changes ->
      %StorePurchase{}
      |> StorePurchase.changeset(%{
        account_id: gifter_account_id,
        store_item_id: item.id,
        currency_type: Atom.to_string(currency_type),
        amount_paid: price,
        original_price: price,
        discount_applied: 0,
        metadata: %{
          "gift" => true,
          "recipient_account_id" => recipient_account_id,
          "gift_message" => message
        }
      })
    end)
    |> Repo.transaction()
  end

  # ============================================================================
  # Promo Code Redemption
  # ============================================================================

  @doc """
  Redeem a promo code for its rewards.

  Unlike discount codes (used at purchase), this redeems item or currency codes directly.
  """
  @spec redeem_promo_code(String.t(), integer()) ::
          {:ok, PromoCode.t()}
          | {:error, :not_found | :expired | :already_redeemed | :not_redeemable}
  def redeem_promo_code(code, account_id) do
    with {:ok, promo} <- validate_promo_code(code, account_id),
         {:ok, _} <- apply_promo_rewards(promo, account_id),
         {:ok, _} <- record_promo_redemption(promo, account_id) do
      {:ok, promo}
    end
  end

  defp apply_promo_rewards(%PromoCode{code_type: "discount"}, _account_id) do
    # Discount codes can't be redeemed directly, only used at purchase
    {:error, :not_redeemable}
  end

  defp apply_promo_rewards(%PromoCode{code_type: "item", granted_item_id: item_id}, account_id)
       when not is_nil(item_id) do
    # Grant the item to the account's collection
    # For now, we'll unlock it as a mount - in a real system, we'd check the item type
    Collections.unlock_account_mount(account_id, item_id, "promo_code")
  end

  defp apply_promo_rewards(
         %PromoCode{
           code_type: "currency",
           granted_currency_amount: amount,
           granted_currency_type: currency_type
         },
         account_id
       )
       when not is_nil(amount) and not is_nil(currency_type) do
    grant_currency(account_id, String.to_existing_atom(currency_type), amount)
  end

  defp apply_promo_rewards(_, _), do: {:error, :not_redeemable}

  defp grant_currency(account_id, currency_type, amount) do
    currency = Repo.get_by(AccountCurrency, account_id: account_id)

    if currency do
      changeset =
        case currency_type do
          :premium ->
            AccountCurrency.changeset(currency, %{
              premium_currency: currency.premium_currency + amount
            })

          :bonus ->
            AccountCurrency.changeset(currency, %{
              bonus_currency: currency.bonus_currency + amount
            })
        end

      Repo.update(changeset)
    else
      # Create currency record if it doesn't exist
      %AccountCurrency{}
      |> AccountCurrency.changeset(%{
        account_id: account_id,
        premium_currency: if(currency_type == :premium, do: amount, else: 0),
        bonus_currency: if(currency_type == :bonus, do: amount, else: 0)
      })
      |> Repo.insert()
    end
  end
end
