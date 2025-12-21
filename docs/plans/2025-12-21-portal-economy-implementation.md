# Portal Economy Support - Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement comprehensive economy tracking with transaction logging, real-time dashboard, and threshold-based alerts with Discord notifications.

**Architecture:** Dual-write pattern - currency modifications happen atomically with transaction logging in the same DB transaction. Telemetry events are emitted for real-time dashboard updates via Phoenix PubSub with 5-second debouncing. Alert thresholds are monitored in a GenServer that sends Discord webhooks when violated.

**Tech Stack:** Elixir/Phoenix, Ecto, Telemetry, Phoenix PubSub, LiveView, HTTPoison (Discord webhooks)

---

## Task 1: Create CurrencyTransaction Schema

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/schema/currency_transaction.ex`
- Test: `apps/bezgelor_db/test/schema/currency_transaction_test.exs`

**Step 1: Write the failing test**

```elixir
# apps/bezgelor_db/test/schema/currency_transaction_test.exs
defmodule BezgelorDb.Schema.CurrencyTransactionTest do
  use BezgelorDb.DataCase

  alias BezgelorDb.Schema.CurrencyTransaction

  describe "changeset/2" do
    test "valid changeset with required fields" do
      attrs = %{
        character_id: 1,
        account_id: 1,
        currency_type: :gold,
        amount: 100,
        balance_after: 500,
        source: :quest_reward
      }

      changeset = CurrencyTransaction.changeset(%CurrencyTransaction{}, attrs)
      assert changeset.valid?
    end

    test "requires character_id, currency_type, amount, balance_after, source" do
      changeset = CurrencyTransaction.changeset(%CurrencyTransaction{}, %{})
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).character_id
      assert "can't be blank" in errors_on(changeset).currency_type
      assert "can't be blank" in errors_on(changeset).amount
      assert "can't be blank" in errors_on(changeset).balance_after
      assert "can't be blank" in errors_on(changeset).source
    end

    test "accepts optional source_id and metadata" do
      attrs = %{
        character_id: 1,
        account_id: 1,
        currency_type: :gold,
        amount: -50,
        balance_after: 450,
        source: :vendor_buy,
        source_id: 12345,
        metadata: %{"vendor_name" => "Protostar Vendor"}
      }

      changeset = CurrencyTransaction.changeset(%CurrencyTransaction{}, attrs)
      assert changeset.valid?
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test apps/bezgelor_db/test/schema/currency_transaction_test.exs -v`
Expected: FAIL with "CurrencyTransaction not defined"

**Step 3: Write the schema**

```elixir
# apps/bezgelor_db/lib/bezgelor_db/schema/currency_transaction.ex
defmodule BezgelorDb.Schema.CurrencyTransaction do
  @moduledoc """
  Schema for currency transaction log entries.

  Immutable log of all currency changes for economy tracking and auditing.
  Each entry records who, what, how much, from where, and the resulting balance.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BezgelorDb.Schema.{Account, Character}

  @type t :: %__MODULE__{}

  @currency_types [
    :gold,
    :elder_gems,
    :renown,
    :prestige,
    :glory,
    :crafting_vouchers,
    :war_coins,
    :shade_silver,
    :protostar_promissory_notes
  ]

  @source_types [
    :quest_reward,
    :vendor_buy,
    :vendor_sell,
    :loot_pickup,
    :mail_received,
    :mail_sent,
    :trade_received,
    :trade_sent,
    :auction_sold,
    :auction_purchased,
    :auction_fee,
    :repair_cost,
    :taxi_fee,
    :tradeskill_cost,
    :guild_deposit,
    :guild_withdraw,
    :housing_purchase,
    :admin_grant,
    :admin_remove,
    :other
  ]

  schema "currency_transactions" do
    belongs_to :character, Character
    belongs_to :account, Account

    field :currency_type, Ecto.Enum, values: @currency_types
    field :amount, :integer
    field :balance_after, :integer

    field :source, Ecto.Enum, values: @source_types
    field :source_id, :integer
    field :metadata, :map, default: %{}

    field :session_id, :string

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc "Returns list of valid currency types"
  def currency_types, do: @currency_types

  @doc "Returns list of valid source types"
  def source_types, do: @source_types

  def changeset(transaction, attrs) do
    transaction
    |> cast(attrs, [
      :character_id,
      :account_id,
      :currency_type,
      :amount,
      :balance_after,
      :source,
      :source_id,
      :metadata,
      :session_id
    ])
    |> validate_required([:character_id, :currency_type, :amount, :balance_after, :source])
    |> foreign_key_constraint(:character_id)
    |> foreign_key_constraint(:account_id)
  end
end
```

**Step 4: Run test to verify it passes**

Run: `mix test apps/bezgelor_db/test/schema/currency_transaction_test.exs -v`
Expected: PASS

**Step 5: Commit**

```bash
git add apps/bezgelor_db/lib/bezgelor_db/schema/currency_transaction.ex apps/bezgelor_db/test/schema/currency_transaction_test.exs
git commit -m "feat(db): add CurrencyTransaction schema for economy tracking"
```

---

## Task 2: Create EconomyAlert Schema

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/schema/economy_alert.ex`
- Test: `apps/bezgelor_db/test/schema/economy_alert_test.exs`

**Step 1: Write the failing test**

```elixir
# apps/bezgelor_db/test/schema/economy_alert_test.exs
defmodule BezgelorDb.Schema.EconomyAlertTest do
  use BezgelorDb.DataCase

  alias BezgelorDb.Schema.EconomyAlert

  describe "changeset/2" do
    test "valid changeset with required fields" do
      attrs = %{
        character_id: 1,
        type: :excessive_gold_gain,
        details: %{"amount" => 150_000, "threshold" => 100_000},
        status: :open
      }

      changeset = EconomyAlert.changeset(%EconomyAlert{}, attrs)
      assert changeset.valid?
    end

    test "requires type, details, status" do
      changeset = EconomyAlert.changeset(%EconomyAlert{}, %{})
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).type
      assert "can't be blank" in errors_on(changeset).status
    end

    test "resolve_changeset adds resolution fields" do
      alert = %EconomyAlert{
        type: :excessive_gold_gain,
        details: %{},
        status: :open
      }

      changeset = EconomyAlert.resolve_changeset(alert, :resolved, 42, "False positive")
      assert changeset.valid?
      assert get_change(changeset, :status) == :resolved
      assert get_change(changeset, :resolved_by_id) == 42
      assert get_change(changeset, :resolution_notes) == "False positive"
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test apps/bezgelor_db/test/schema/economy_alert_test.exs -v`
Expected: FAIL with "EconomyAlert not defined"

**Step 3: Write the schema**

```elixir
# apps/bezgelor_db/lib/bezgelor_db/schema/economy_alert.ex
defmodule BezgelorDb.Schema.EconomyAlert do
  @moduledoc """
  Schema for economy alert records.

  Tracks threshold violations and suspicious economic activity for investigation.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BezgelorDb.Schema.Character

  @type t :: %__MODULE__{}

  @alert_types [
    :excessive_gold_gain,
    :high_balance,
    :suspicious_pattern,
    :rapid_transactions
  ]

  @status_types [:open, :investigating, :resolved, :dismissed]

  schema "economy_alerts" do
    belongs_to :character, Character

    field :type, Ecto.Enum, values: @alert_types
    field :details, :map, default: %{}
    field :status, Ecto.Enum, values: @status_types, default: :open

    field :resolved_by_id, :integer
    field :resolution_notes, :string

    timestamps(type: :utc_datetime)
  end

  @doc "Returns list of valid alert types"
  def alert_types, do: @alert_types

  @doc "Returns list of valid status types"
  def status_types, do: @status_types

  def changeset(alert, attrs) do
    alert
    |> cast(attrs, [:character_id, :type, :details, :status])
    |> validate_required([:type, :status])
    |> foreign_key_constraint(:character_id)
  end

  def resolve_changeset(alert, status, resolved_by_id, notes \\ nil)
      when status in [:resolved, :dismissed, :investigating] do
    alert
    |> change(%{
      status: status,
      resolved_by_id: resolved_by_id,
      resolution_notes: notes
    })
  end
end
```

**Step 4: Run test to verify it passes**

Run: `mix test apps/bezgelor_db/test/schema/economy_alert_test.exs -v`
Expected: PASS

**Step 5: Commit**

```bash
git add apps/bezgelor_db/lib/bezgelor_db/schema/economy_alert.ex apps/bezgelor_db/test/schema/economy_alert_test.exs
git commit -m "feat(db): add EconomyAlert schema for threshold violations"
```

---

## Task 3: Create Database Migration

**Files:**
- Create: `apps/bezgelor_db/priv/repo/migrations/20251221000000_create_economy_tables.exs`

**Step 1: Write the migration**

```elixir
# apps/bezgelor_db/priv/repo/migrations/20251221000000_create_economy_tables.exs
defmodule BezgelorDb.Repo.Migrations.CreateEconomyTables do
  use Ecto.Migration

  def change do
    # Currency transaction log - immutable audit trail
    create table(:currency_transactions) do
      add :character_id, references(:characters, on_delete: :delete_all), null: false
      add :account_id, references(:accounts, on_delete: :nilify_all)

      add :currency_type, :string, null: false
      add :amount, :integer, null: false
      add :balance_after, :integer, null: false

      add :source, :string, null: false
      add :source_id, :integer
      add :metadata, :map, default: %{}

      add :session_id, :string

      add :inserted_at, :utc_datetime, null: false
    end

    # Primary query pattern: transactions for a character over time
    create index(:currency_transactions, [:character_id, :inserted_at])

    # Filter by source type
    create index(:currency_transactions, [:source, :inserted_at])

    # Time-range queries for dashboard
    create index(:currency_transactions, [:inserted_at])

    # Economy alerts for threshold violations
    create table(:economy_alerts) do
      add :character_id, references(:characters, on_delete: :delete_all)

      add :type, :string, null: false
      add :details, :map, default: %{}
      add :status, :string, null: false, default: "open"

      add :resolved_by_id, :integer
      add :resolution_notes, :text

      timestamps(type: :utc_datetime)
    end

    # Open alerts query
    create index(:economy_alerts, [:status])
    create index(:economy_alerts, [:character_id])
    create index(:economy_alerts, [:type, :inserted_at])
  end
end
```

**Step 2: Run migration**

Run: `mix ecto.migrate`
Expected: Migration successful

**Step 3: Verify with rollback/re-migrate**

Run: `mix ecto.rollback && mix ecto.migrate`
Expected: Both succeed

**Step 4: Commit**

```bash
git add apps/bezgelor_db/priv/repo/migrations/20251221000000_create_economy_tables.exs
git commit -m "feat(db): add economy tables migration"
```

---

## Task 4: Create Economy Context Module

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/economy.ex`
- Test: `apps/bezgelor_db/test/economy_test.exs`

**Step 1: Write the failing test for modify_currency**

```elixir
# apps/bezgelor_db/test/economy_test.exs
defmodule BezgelorDb.EconomyTest do
  use BezgelorDb.DataCase

  alias BezgelorDb.{Economy, Characters, Accounts}
  alias BezgelorDb.Schema.CurrencyTransaction

  @moduletag :database

  setup do
    {:ok, account} = Accounts.create_account(%{username: "testuser", email: "test@test.com"})

    {:ok, character} =
      Characters.create_character(account.id, %{
        name: "TestChar",
        race: 1,
        class: 1,
        sex: 0,
        faction_id: 167,
        world_id: 426,
        world_zone_id: 6,
        location_x: 0.0,
        location_y: 0.0,
        location_z: 0.0
      }, %{})

    %{account: account, character: character}
  end

  describe "modify_currency/5" do
    test "adds currency and logs transaction", %{character: character} do
      assert {:ok, currency} =
               Economy.modify_currency(character.id, :gold, 1000, :quest_reward, source_id: 123)

      assert currency.gold == 1000

      # Verify transaction was logged
      [tx] = Economy.list_transactions(character_id: character.id)
      assert tx.amount == 1000
      assert tx.balance_after == 1000
      assert tx.source == :quest_reward
      assert tx.source_id == 123
    end

    test "subtracts currency and logs negative transaction", %{character: character} do
      # First add some gold
      {:ok, _} = Economy.modify_currency(character.id, :gold, 1000, :admin_grant)

      # Then spend some
      {:ok, currency} = Economy.modify_currency(character.id, :gold, -200, :vendor_buy)
      assert currency.gold == 800

      # Verify both transactions logged
      txs = Economy.list_transactions(character_id: character.id)
      assert length(txs) == 2
    end

    test "returns error for insufficient funds", %{character: character} do
      assert {:error, :insufficient_funds} =
               Economy.modify_currency(character.id, :gold, -100, :vendor_buy)
    end

    test "stores metadata in transaction", %{character: character} do
      {:ok, _} =
        Economy.modify_currency(character.id, :gold, 500, :admin_grant,
          metadata: %{reason: "Bug compensation", admin_id: 42}
        )

      [tx] = Economy.list_transactions(character_id: character.id)
      assert tx.metadata["reason"] == "Bug compensation"
      assert tx.metadata["admin_id"] == 42
    end
  end

  describe "list_transactions/1" do
    test "filters by source", %{character: character} do
      {:ok, _} = Economy.modify_currency(character.id, :gold, 100, :quest_reward)
      {:ok, _} = Economy.modify_currency(character.id, :gold, 50, :loot_pickup)
      {:ok, _} = Economy.modify_currency(character.id, :gold, 200, :quest_reward)

      txs = Economy.list_transactions(character_id: character.id, source: :quest_reward)
      assert length(txs) == 2
      assert Enum.all?(txs, &(&1.source == :quest_reward))
    end

    test "limits results", %{character: character} do
      for i <- 1..10 do
        Economy.modify_currency(character.id, :gold, i * 10, :quest_reward)
      end

      txs = Economy.list_transactions(character_id: character.id, limit: 5)
      assert length(txs) == 5
    end
  end

  describe "total_currency_in_circulation/1" do
    test "sums all character balances", %{character: character, account: account} do
      {:ok, _} = Economy.modify_currency(character.id, :gold, 1000, :quest_reward)

      # Create second character with gold
      {:ok, char2} =
        Characters.create_character(account.id, %{
          name: "TestChar2",
          race: 1,
          class: 1,
          sex: 0,
          faction_id: 167,
          world_id: 426,
          world_zone_id: 6,
          location_x: 0.0,
          location_y: 0.0,
          location_z: 0.0
        }, %{})

      {:ok, _} = Economy.modify_currency(char2.id, :gold, 500, :quest_reward)

      assert Economy.total_currency_in_circulation(:gold) == 1500
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test apps/bezgelor_db/test/economy_test.exs -v`
Expected: FAIL with "Economy not defined"

**Step 3: Write the Economy context**

```elixir
# apps/bezgelor_db/lib/bezgelor_db/economy.ex
defmodule BezgelorDb.Economy do
  @moduledoc """
  Economy tracking context.

  All currency modifications MUST go through this module to ensure
  transaction logging. Direct updates to CharacterCurrency are prohibited
  in application code.

  ## Usage

      # Add gold from a quest
      Economy.modify_currency(character_id, :gold, 100, :quest_reward, source_id: quest_id)

      # Spend gold at vendor
      Economy.modify_currency(character_id, :gold, -50, :vendor_buy, source_id: vendor_id)

      # Admin grant with reason
      Economy.modify_currency(character_id, :gold, 1000, :admin_grant,
        metadata: %{reason: "Bug compensation", admin_id: admin.id})
  """

  import Ecto.Query

  alias BezgelorDb.Repo
  alias BezgelorDb.Schema.{CharacterCurrency, CurrencyTransaction, EconomyAlert, Character}

  require Logger

  # ============================================================================
  # Currency Modification (Core API)
  # ============================================================================

  @doc """
  Modify a character's currency with full transaction logging.

  This is the single entry point for all currency changes. The modification
  and transaction log are written in the same database transaction.

  ## Options

    * `:source_id` - ID of the source (quest_id, vendor_id, mail_id, etc.)
    * `:metadata` - Map of additional context (reason, admin notes, etc.)
    * `:session_id` - Player session ID for grouping transactions

  ## Returns

    * `{:ok, currency}` - Updated CharacterCurrency record
    * `{:error, :insufficient_funds}` - Not enough currency
    * `{:error, :invalid_currency}` - Unknown currency type
  """
  @spec modify_currency(integer(), atom(), integer(), atom(), keyword()) ::
          {:ok, CharacterCurrency.t()} | {:error, atom()}
  def modify_currency(character_id, currency_type, amount, source, opts \\ []) do
    source_id = Keyword.get(opts, :source_id)
    metadata = Keyword.get(opts, :metadata, %{})
    session_id = Keyword.get(opts, :session_id)

    Repo.transaction(fn ->
      # 1. Get or create currency record
      currency = get_or_create_currency(character_id)
      current_balance = Map.get(currency, currency_type, 0)
      new_balance = current_balance + amount

      # 2. Check for insufficient funds
      if new_balance < 0 do
        Repo.rollback(:insufficient_funds)
      end

      # 3. Update currency
      case CharacterCurrency.modify_changeset(currency, currency_type, amount) do
        {:ok, changeset} ->
          {:ok, updated} = Repo.update(changeset)

          # 4. Log transaction (same DB transaction = atomic)
          {:ok, _tx} =
            create_transaction(%{
              character_id: character_id,
              account_id: get_account_id(character_id),
              currency_type: currency_type,
              amount: amount,
              balance_after: new_balance,
              source: source,
              source_id: source_id,
              metadata: metadata,
              session_id: session_id
            })

          # 5. Emit telemetry for real-time dashboard
          :telemetry.execute(
            [:bezgelor, :economy, :transaction],
            %{amount: amount, balance: new_balance},
            %{
              currency: currency_type,
              source: source,
              character_id: character_id,
              source_id: source_id
            }
          )

          updated

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  defp get_or_create_currency(character_id) do
    case Repo.get_by(CharacterCurrency, character_id: character_id) do
      nil ->
        {:ok, currency} =
          %CharacterCurrency{}
          |> CharacterCurrency.changeset(%{character_id: character_id})
          |> Repo.insert()

        currency

      currency ->
        currency
    end
  end

  defp get_account_id(character_id) do
    case Repo.get(Character, character_id) do
      nil -> nil
      character -> character.account_id
    end
  end

  defp create_transaction(attrs) do
    %CurrencyTransaction{}
    |> CurrencyTransaction.changeset(attrs)
    |> Repo.insert()
  end

  # ============================================================================
  # Transaction Queries
  # ============================================================================

  @doc """
  List currency transactions with optional filters.

  ## Options

    * `:character_id` - Filter by character
    * `:account_id` - Filter by account
    * `:source` - Filter by source type
    * `:currency_type` - Filter by currency
    * `:from` - Start date (DateTime)
    * `:to` - End date (DateTime)
    * `:limit` - Max results (default 100)
    * `:offset` - Pagination offset
  """
  @spec list_transactions(keyword()) :: [CurrencyTransaction.t()]
  def list_transactions(opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)

    CurrencyTransaction
    |> apply_transaction_filters(opts)
    |> order_by([t], desc: t.inserted_at)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  defp apply_transaction_filters(query, opts) do
    query
    |> filter_by(:character_id, Keyword.get(opts, :character_id))
    |> filter_by(:account_id, Keyword.get(opts, :account_id))
    |> filter_by(:source, Keyword.get(opts, :source))
    |> filter_by(:currency_type, Keyword.get(opts, :currency_type))
    |> filter_from(Keyword.get(opts, :from))
    |> filter_to(Keyword.get(opts, :to))
  end

  defp filter_by(query, _field, nil), do: query
  defp filter_by(query, field, value), do: where(query, [t], field(t, ^field) == ^value)

  defp filter_from(query, nil), do: query
  defp filter_from(query, from), do: where(query, [t], t.inserted_at >= ^from)

  defp filter_to(query, nil), do: query
  defp filter_to(query, to), do: where(query, [t], t.inserted_at <= ^to)

  @doc """
  Count transactions matching filters.
  """
  @spec count_transactions(keyword()) :: integer()
  def count_transactions(opts \\ []) do
    CurrencyTransaction
    |> apply_transaction_filters(opts)
    |> Repo.aggregate(:count)
  end

  # ============================================================================
  # Analytics Queries
  # ============================================================================

  @doc """
  Get total currency in circulation across all characters.
  """
  @spec total_currency_in_circulation(atom()) :: integer()
  def total_currency_in_circulation(currency_type) do
    CharacterCurrency
    |> select([c], field(c, ^currency_type))
    |> Repo.all()
    |> Enum.sum()
  end

  @doc """
  Sum transactions for a currency type within a date range.

  ## Options

    * `:from` - Start date
    * `:to` - End date
    * `:direction` - :positive, :negative, or :all (default)
  """
  @spec sum_transactions(atom(), keyword()) :: integer()
  def sum_transactions(currency_type, opts \\ []) do
    direction = Keyword.get(opts, :direction, :all)

    query =
      CurrencyTransaction
      |> where([t], t.currency_type == ^currency_type)
      |> filter_from(Keyword.get(opts, :from))
      |> filter_to(Keyword.get(opts, :to))

    query =
      case direction do
        :positive -> where(query, [t], t.amount > 0)
        :negative -> where(query, [t], t.amount < 0)
        :all -> query
      end

    Repo.aggregate(query, :sum, :amount) || 0
  end

  @doc """
  Get top currency holders.
  """
  @spec top_currency_holders(atom(), keyword()) :: [map()]
  def top_currency_holders(currency_type, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)

    CharacterCurrency
    |> join(:inner, [cc], c in Character, on: cc.character_id == c.id)
    |> where([cc, c], is_nil(c.deleted_at))
    |> select([cc, c], %{
      character_id: cc.character_id,
      character_name: c.name,
      balance: field(cc, ^currency_type)
    })
    |> order_by([cc], desc: field(cc, ^currency_type))
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Get transaction breakdown by source for a date range.
  """
  @spec transactions_by_source(keyword()) :: [map()]
  def transactions_by_source(opts \\ []) do
    CurrencyTransaction
    |> filter_from(Keyword.get(opts, :from))
    |> filter_to(Keyword.get(opts, :to))
    |> filter_by(:currency_type, Keyword.get(opts, :currency_type, :gold))
    |> group_by([t], t.source)
    |> select([t], %{
      source: t.source,
      count: count(t.id),
      total: sum(t.amount),
      income: sum(fragment("CASE WHEN amount > 0 THEN amount ELSE 0 END")),
      expense: sum(fragment("CASE WHEN amount < 0 THEN amount ELSE 0 END"))
    })
    |> Repo.all()
  end

  # ============================================================================
  # Alert Management
  # ============================================================================

  @doc """
  Create an economy alert.
  """
  @spec create_alert(map()) :: {:ok, EconomyAlert.t()} | {:error, Ecto.Changeset.t()}
  def create_alert(attrs) do
    %EconomyAlert{}
    |> EconomyAlert.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  List alerts with optional filters.

  ## Options

    * `:status` - Filter by status (:open, :investigating, :resolved, :dismissed)
    * `:type` - Filter by alert type
    * `:character_id` - Filter by character
    * `:limit` - Max results
  """
  @spec list_alerts(keyword()) :: [EconomyAlert.t()]
  def list_alerts(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    EconomyAlert
    |> filter_by(:status, Keyword.get(opts, :status))
    |> filter_by(:type, Keyword.get(opts, :type))
    |> filter_by(:character_id, Keyword.get(opts, :character_id))
    |> order_by([a], desc: a.inserted_at)
    |> limit(^limit)
    |> preload(:character)
    |> Repo.all()
  end

  @doc """
  Update alert status with resolution info.
  """
  @spec resolve_alert(EconomyAlert.t() | integer(), atom(), integer(), String.t() | nil) ::
          {:ok, EconomyAlert.t()} | {:error, term()}
  def resolve_alert(alert, status, resolved_by_id, notes \\ nil)

  def resolve_alert(%EconomyAlert{} = alert, status, resolved_by_id, notes) do
    alert
    |> EconomyAlert.resolve_changeset(status, resolved_by_id, notes)
    |> Repo.update()
  end

  def resolve_alert(alert_id, status, resolved_by_id, notes) when is_integer(alert_id) do
    case Repo.get(EconomyAlert, alert_id) do
      nil -> {:error, :not_found}
      alert -> resolve_alert(alert, status, resolved_by_id, notes)
    end
  end

  @doc """
  Get count of open alerts.
  """
  @spec open_alert_count() :: integer()
  def open_alert_count do
    EconomyAlert
    |> where([a], a.status == :open)
    |> Repo.aggregate(:count)
  end
end
```

**Step 4: Run test to verify it passes**

Run: `mix test apps/bezgelor_db/test/economy_test.exs -v`
Expected: PASS

**Step 5: Commit**

```bash
git add apps/bezgelor_db/lib/bezgelor_db/economy.ex apps/bezgelor_db/test/economy_test.exs
git commit -m "feat(db): add Economy context with transaction logging"
```

---

## Task 5: Create Economy Telemetry GenServer

**Files:**
- Create: `apps/bezgelor_world/lib/bezgelor_world/economy/telemetry.ex`
- Test: `apps/bezgelor_world/test/economy/telemetry_test.exs`

**Step 1: Write the failing test**

```elixir
# apps/bezgelor_world/test/economy/telemetry_test.exs
defmodule BezgelorWorld.Economy.TelemetryTest do
  use ExUnit.Case, async: false

  alias BezgelorWorld.Economy.Telemetry

  setup do
    # Start the GenServer for this test
    start_supervised!(Telemetry)
    :ok
  end

  describe "handle_cast/2" do
    test "buffers transactions" do
      Telemetry.record_transaction(%{amount: 100, balance: 500}, %{
        currency: :gold,
        source: :quest_reward,
        character_id: 1
      })

      state = :sys.get_state(Telemetry)
      assert length(state.buffer) == 1
    end
  end

  describe "flush" do
    test "aggregates and broadcasts buffered transactions" do
      # Subscribe to PubSub
      Phoenix.PubSub.subscribe(BezgelorPortal.PubSub, "economy:updates")

      # Add some transactions
      Telemetry.record_transaction(%{amount: 100}, %{currency: :gold, source: :quest_reward, character_id: 1})
      Telemetry.record_transaction(%{amount: 50}, %{currency: :gold, source: :loot_pickup, character_id: 2})

      # Force flush
      send(Telemetry, :flush)

      # Should receive broadcast
      assert_receive {:economy_update, summary}, 1000
      assert summary.transaction_count == 2
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test apps/bezgelor_world/test/economy/telemetry_test.exs -v`
Expected: FAIL with "Telemetry not defined"

**Step 3: Write the Telemetry GenServer**

```elixir
# apps/bezgelor_world/lib/bezgelor_world/economy/telemetry.ex
defmodule BezgelorWorld.Economy.Telemetry do
  @moduledoc """
  Economy telemetry handler with debounced PubSub broadcasting.

  Buffers incoming transaction telemetry events and broadcasts aggregated
  summaries to the Portal dashboard at regular intervals (default 5 seconds).

  ## How It Works

  1. Economy.modify_currency/5 emits telemetry events
  2. This GenServer receives events via telemetry handler
  3. Events are buffered in memory
  4. Every 5 seconds, buffer is aggregated and broadcast via PubSub
  5. Dashboard LiveViews receive the broadcast and update in real-time
  """

  use GenServer

  require Logger

  @debounce_interval Application.compile_env(:bezgelor_world, [:economy, :dashboard_update_interval_ms], 5_000)
  @pubsub BezgelorPortal.PubSub
  @topic "economy:updates"

  # ============================================================================
  # Client API
  # ============================================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Record a transaction (called from telemetry handler or directly).
  """
  def record_transaction(measurements, metadata) do
    GenServer.cast(__MODULE__, {:transaction, measurements, metadata})
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl true
  def init(_opts) do
    # Attach telemetry handler
    :telemetry.attach(
      "economy-telemetry-handler",
      [:bezgelor, :economy, :transaction],
      &handle_telemetry_event/4,
      nil
    )

    schedule_flush()

    {:ok, %{buffer: [], last_flush: System.monotonic_time(:millisecond)}}
  end

  @impl true
  def handle_cast({:transaction, measurements, metadata}, state) do
    entry =
      measurements
      |> Map.merge(metadata)
      |> Map.put(:timestamp, DateTime.utc_now())

    {:noreply, %{state | buffer: [entry | state.buffer]}}
  end

  @impl true
  def handle_info(:flush, state) do
    if state.buffer != [] do
      summary = aggregate_buffer(state.buffer)

      # Broadcast to dashboard subscribers
      Phoenix.PubSub.broadcast(@pubsub, @topic, {:economy_update, summary})

      Logger.debug("Economy telemetry flush: #{summary.transaction_count} transactions")
    end

    schedule_flush()
    {:noreply, %{state | buffer: [], last_flush: System.monotonic_time(:millisecond)}}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp handle_telemetry_event(_event, measurements, metadata, _config) do
    record_transaction(measurements, metadata)
  end

  defp schedule_flush do
    Process.send_after(self(), :flush, @debounce_interval)
  end

  defp aggregate_buffer(transactions) do
    %{
      transaction_count: length(transactions),
      by_currency: group_and_summarize(transactions, :currency),
      by_source: group_and_summarize(transactions, :source),
      recent: Enum.take(transactions, 10),
      timestamp: DateTime.utc_now()
    }
  end

  defp group_and_summarize(transactions, key) do
    transactions
    |> Enum.group_by(&Map.get(&1, key))
    |> Enum.map(fn {group, txs} ->
      %{
        key: group,
        count: length(txs),
        total: txs |> Enum.map(&Map.get(&1, :amount, 0)) |> Enum.sum()
      }
    end)
  end
end
```

**Step 4: Run test to verify it passes**

Run: `mix test apps/bezgelor_world/test/economy/telemetry_test.exs -v`
Expected: PASS

**Step 5: Commit**

```bash
git add apps/bezgelor_world/lib/bezgelor_world/economy/telemetry.ex apps/bezgelor_world/test/economy/telemetry_test.exs
git commit -m "feat(world): add Economy.Telemetry for real-time dashboard updates"
```

---

## Task 6: Create Economy Alerts GenServer

**Files:**
- Create: `apps/bezgelor_world/lib/bezgelor_world/economy/alerts.ex`
- Test: `apps/bezgelor_world/test/economy/alerts_test.exs`

**Step 1: Write the failing test**

```elixir
# apps/bezgelor_world/test/economy/alerts_test.exs
defmodule BezgelorWorld.Economy.AlertsTest do
  use ExUnit.Case, async: false

  alias BezgelorWorld.Economy.Alerts

  setup do
    start_supervised!(Alerts)
    :ok
  end

  describe "threshold detection" do
    test "triggers alert when hourly gain exceeds threshold" do
      # Subscribe to alerts
      Phoenix.PubSub.subscribe(BezgelorPortal.PubSub, "economy:alerts")

      # Configure low threshold for testing
      Application.put_env(:bezgelor_world, :economy, gold_gain_per_hour_threshold: 100)

      # Record gains that exceed threshold
      Alerts.record_gain(1, 60, %{source: :quest_reward})
      Alerts.record_gain(1, 50, %{source: :loot_pickup})

      # Should trigger alert
      assert_receive {:new_alert, :excessive_gold_gain, details}, 1000
      assert details.character_id == 1
      assert details.amount >= 100
    end
  end

  describe "get_threshold/1" do
    test "returns configured threshold" do
      Application.put_env(:bezgelor_world, :economy, gold_gain_per_hour_threshold: 50_000)
      assert Alerts.get_threshold(:gold_gain_per_hour) == 50_000
    end

    test "returns default when not configured" do
      Application.delete_env(:bezgelor_world, :economy)
      assert Alerts.get_threshold(:gold_gain_per_hour) == 100_000
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test apps/bezgelor_world/test/economy/alerts_test.exs -v`
Expected: FAIL with "Alerts not defined"

**Step 3: Write the Alerts GenServer**

```elixir
# apps/bezgelor_world/lib/bezgelor_world/economy/alerts.ex
defmodule BezgelorWorld.Economy.Alerts do
  @moduledoc """
  Economy alert detection with Discord webhook integration.

  Monitors economy telemetry events for threshold violations and triggers
  alerts when suspicious activity is detected.

  ## Thresholds (configurable)

    * `:gold_gain_per_hour` - Max gold a character can gain in one hour (default 100,000)
    * `:gold_balance_max` - Max gold balance before alert (default 1,000,000)
    * `:transactions_per_minute` - Max transactions per minute (default 60)

  ## Discord Integration

  Set `ECONOMY_DISCORD_WEBHOOK` env var to enable Discord notifications.
  """

  use GenServer

  alias BezgelorDb.Economy

  require Logger

  @default_thresholds %{
    gold_gain_per_hour: 100_000,
    gold_balance_max: 1_000_000,
    transactions_per_minute: 60
  }

  @pubsub BezgelorPortal.PubSub
  @alerts_topic "economy:alerts"

  # ============================================================================
  # Client API
  # ============================================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Record a currency gain for threshold tracking"
  def record_gain(character_id, amount, metadata) when amount > 0 do
    GenServer.cast(__MODULE__, {:record_gain, character_id, amount, metadata})
  end

  def record_gain(_character_id, _amount, _metadata), do: :ok

  @doc "Get a threshold value"
  def get_threshold(key) do
    config = Application.get_env(:bezgelor_world, :economy, [])
    threshold_key = :"#{key}_threshold"
    Keyword.get(config, threshold_key) || Map.get(@default_thresholds, key)
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl true
  def init(_opts) do
    # Attach telemetry handler for transaction events
    :telemetry.attach(
      "economy-alerts-handler",
      [:bezgelor, :economy, :transaction],
      &handle_telemetry_event/4,
      nil
    )

    # Periodic balance checks
    :timer.send_interval(60_000, :check_balances)

    # Hourly cleanup of old tracking data
    :timer.send_interval(3_600_000, :cleanup)

    {:ok, %{hourly_gains: %{}, minute_counts: %{}}}
  end

  @impl true
  def handle_cast({:record_gain, character_id, amount, metadata}, state) do
    # Track hourly gains
    hour_key = {character_id, current_hour()}
    current = Map.get(state.hourly_gains, hour_key, 0)
    new_total = current + amount

    # Check threshold (only alert on first crossing)
    threshold = get_threshold(:gold_gain_per_hour)

    if new_total > threshold and current <= threshold do
      trigger_alert(:excessive_gold_gain, %{
        character_id: character_id,
        amount: new_total,
        threshold: threshold,
        source: Map.get(metadata, :source)
      })
    end

    # Track transaction rate
    minute_key = {character_id, current_minute()}
    minute_count = Map.get(state.minute_counts, minute_key, 0) + 1

    if minute_count > get_threshold(:transactions_per_minute) and
         Map.get(state.minute_counts, minute_key, 0) <= get_threshold(:transactions_per_minute) do
      trigger_alert(:rapid_transactions, %{
        character_id: character_id,
        count: minute_count,
        threshold: get_threshold(:transactions_per_minute)
      })
    end

    {:noreply,
     %{
       state
       | hourly_gains: Map.put(state.hourly_gains, hour_key, new_total),
         minute_counts: Map.put(state.minute_counts, minute_key, minute_count)
     }}
  end

  @impl true
  def handle_info(:check_balances, state) do
    # Check for characters exceeding balance threshold
    threshold = get_threshold(:gold_balance_max)
    high_balances = Economy.top_currency_holders(:gold, limit: 100)

    Enum.each(high_balances, fn holder ->
      if holder.balance > threshold do
        trigger_alert(:high_balance, %{
          character_id: holder.character_id,
          character_name: holder.character_name,
          balance: holder.balance,
          threshold: threshold
        })
      end
    end)

    {:noreply, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    # Remove tracking data older than 2 hours
    current = current_hour()

    hourly_gains =
      state.hourly_gains
      |> Enum.reject(fn {{_char_id, hour}, _amount} -> hour < current - 2 end)
      |> Enum.into(%{})

    minute_counts =
      state.minute_counts
      |> Enum.reject(fn {{_char_id, minute}, _count} -> minute < current_minute() - 5 end)
      |> Enum.into(%{})

    {:noreply, %{state | hourly_gains: hourly_gains, minute_counts: minute_counts}}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp handle_telemetry_event(_event, %{amount: amount}, metadata, _config) when amount > 0 do
    record_gain(metadata.character_id, amount, metadata)
  end

  defp handle_telemetry_event(_, _, _, _), do: :ok

  defp trigger_alert(type, details) do
    Logger.warning("Economy alert: #{type} - #{inspect(details)}")

    # 1. Log to database
    Economy.create_alert(%{
      type: type,
      character_id: details[:character_id],
      details: details,
      status: :open
    })

    # 2. Broadcast to dashboard
    Phoenix.PubSub.broadcast(@pubsub, @alerts_topic, {:new_alert, type, details})

    # 3. Send Discord webhook
    send_discord_alert(type, details)
  end

  defp send_discord_alert(type, details) do
    webhook_url =
      Application.get_env(:bezgelor_world, :economy, [])
      |> Keyword.get(:discord_webhook_url)

    if webhook_url do
      payload = format_discord_embed(type, details)

      Task.start(fn ->
        case HTTPoison.post(webhook_url, Jason.encode!(payload), [
               {"Content-Type", "application/json"}
             ]) do
          {:ok, _} -> :ok
          {:error, reason} -> Logger.error("Discord webhook failed: #{inspect(reason)}")
        end
      end)
    end
  end

  defp format_discord_embed(type, details) do
    title =
      case type do
        :excessive_gold_gain -> "Excessive Gold Gain"
        :high_balance -> "High Balance Alert"
        :rapid_transactions -> "Rapid Transaction Activity"
        :suspicious_pattern -> "Suspicious Pattern Detected"
        _ -> "Economy Alert"
      end

    %{
      embeds: [
        %{
          title: title,
          color: 16_711_680,
          fields:
            Enum.map(details, fn {k, v} ->
              %{name: to_string(k), value: to_string(v), inline: true}
            end),
          timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
        }
      ]
    }
  end

  defp current_hour do
    DateTime.utc_now()
    |> DateTime.to_unix()
    |> div(3600)
  end

  defp current_minute do
    DateTime.utc_now()
    |> DateTime.to_unix()
    |> div(60)
  end
end
```

**Step 4: Run test to verify it passes**

Run: `mix test apps/bezgelor_world/test/economy/alerts_test.exs -v`
Expected: PASS

**Step 5: Commit**

```bash
git add apps/bezgelor_world/lib/bezgelor_world/economy/alerts.ex apps/bezgelor_world/test/economy/alerts_test.exs
git commit -m "feat(world): add Economy.Alerts for threshold detection and Discord webhooks"
```

---

## Task 7: Add Economy GenServers to Application Supervisor

**Files:**
- Modify: `apps/bezgelor_world/lib/bezgelor_world/application.ex`

**Step 1: Add Economy children to supervisor**

In `apps/bezgelor_world/lib/bezgelor_world/application.ex`, add to `base_children` list after line ~94:

```elixir
      # Economy tracking and alerts
      BezgelorWorld.Economy.Telemetry,
      BezgelorWorld.Economy.Alerts,
```

**Step 2: Verify application starts**

Run: `mix compile && mix run --no-halt &` (then Ctrl+C)
Expected: No errors, servers start

**Step 3: Commit**

```bash
git add apps/bezgelor_world/lib/bezgelor_world/application.ex
git commit -m "feat(world): start Economy.Telemetry and Economy.Alerts in supervisor"
```

---

## Task 8: Add Economy Configuration

**Files:**
- Modify: `config/config.exs`

**Step 1: Add economy config section**

Add after other bezgelor_world config:

```elixir
# Economy tracking configuration
config :bezgelor_world, :economy,
  # Alert thresholds
  gold_gain_per_hour_threshold: 100_000,
  gold_balance_max_threshold: 1_000_000,
  transactions_per_minute_threshold: 60,
  # Discord webhook (nil = disabled)
  discord_webhook_url: System.get_env("ECONOMY_DISCORD_WEBHOOK"),
  # Dashboard update interval
  dashboard_update_interval_ms: 5_000
```

**Step 2: Commit**

```bash
git add config/config.exs
git commit -m "config: add economy tracking configuration"
```

---

## Task 9: Add Telemetry Metrics to Portal

**Files:**
- Modify: `apps/bezgelor_portal/lib/bezgelor_portal_web/telemetry.ex`

**Step 1: Add economy metrics to metrics/0 function**

Add to the `metrics` list:

```elixir
      # Economy Metrics
      counter("bezgelor.economy.transaction.count",
        tags: [:currency_type, :source],
        description: "Total currency transactions"
      ),
      sum("bezgelor.economy.transaction.amount",
        tags: [:currency_type, :source],
        description: "Sum of currency amounts (can be negative)"
      ),
      last_value("bezgelor.economy.circulation.total",
        tags: [:currency_type],
        description: "Total currency in circulation"
      ),
      counter("bezgelor.economy.alert.triggered",
        tags: [:type],
        description: "Economy alerts triggered"
      ),
```

**Step 2: Commit**

```bash
git add apps/bezgelor_portal/lib/bezgelor_portal_web/telemetry.ex
git commit -m "feat(portal): add economy telemetry metrics"
```

---

## Task 10: Migrate Quest Reward Handler

**Files:**
- Modify: `apps/bezgelor_world/lib/bezgelor_world/quest/reward_handler.ex`

**Step 1: Update import and alias**

Replace:
```elixir
alias BezgelorDb.{Characters, Inventory, Repo}
```

With:
```elixir
alias BezgelorDb.{Characters, Economy, Inventory, Repo}
```

**Step 2: Update add_currency function**

Replace the private `add_currency/3` function (around line 285-299) with:

```elixir
  # Add currency to a character's currency record
  defp add_currency(character_id, currency_type, amount)
       when is_atom(currency_type) and amount > 0 do
    Economy.modify_currency(character_id, currency_type, amount, :quest_reward)
  end
```

**Step 3: Update grant_currency function to pass source_id**

Replace `grant_currency/3` (around line 261-282):

```elixir
  # Grant currency to character
  defp grant_currency(character_id, currency_type, amount, quest_id \\ nil) do
    currency =
      case currency_type do
        1 -> :gold
        2 -> :renown
        3 -> :prestige
        4 -> :elder_gems
        5 -> :glory
        6 -> :crafting_vouchers
        _ -> :gold
      end

    case Economy.modify_currency(character_id, currency, amount, :quest_reward, source_id: quest_id) do
      {:ok, _} ->
        Logger.debug("Granted #{amount} #{currency} to character #{character_id}")
        :ok

      {:error, reason} ->
        Logger.warning("Failed to grant currency: #{inspect(reason)}")
        {:error, reason}
    end
  end
```

**Step 4: Run tests**

Run: `mix test apps/bezgelor_world/test/quest/ -v`
Expected: PASS

**Step 5: Commit**

```bash
git add apps/bezgelor_world/lib/bezgelor_world/quest/reward_handler.ex
git commit -m "refactor(quest): migrate reward_handler to Economy.modify_currency"
```

---

## Task 11: Migrate Vendor Handler

**Files:**
- Modify: `apps/bezgelor_protocol/lib/bezgelor_protocol/handler/vendor_handler.ex`

**Step 1: Update alias**

Add:
```elixir
alias BezgelorDb.Economy
```

**Step 2: Update spend_currency call (around line 107)**

Replace:
```elixir
case Inventory.spend_currency(character_id, :gold, total_cost) do
```

With:
```elixir
case Economy.modify_currency(character_id, :gold, -total_cost, :vendor_buy, source_id: vendor_id) do
```

**Step 3: Update refund on failure (around line 118)**

Replace:
```elixir
Inventory.add_currency(character_id, :gold, total_cost)
```

With:
```elixir
Economy.modify_currency(character_id, :gold, total_cost, :vendor_buy,
  source_id: vendor_id,
  metadata: %{refund: true, reason: "add_item_failed"}
)
```

**Step 4: Commit**

```bash
git add apps/bezgelor_protocol/lib/bezgelor_protocol/handler/vendor_handler.ex
git commit -m "refactor(vendor): migrate vendor_handler to Economy.modify_currency"
```

---

## Task 12: Migrate Vendor Sell Handler

**Files:**
- Modify: `apps/bezgelor_protocol/lib/bezgelor_protocol/handler/vendor_sell_handler.ex`

**Step 1: Update alias**

Add:
```elixir
alias BezgelorDb.Economy
```

**Step 2: Update add_currency call (around line 93)**

Replace:
```elixir
Inventory.add_currency(character_id, :gold, total_value)
```

With:
```elixir
Economy.modify_currency(character_id, :gold, total_value, :vendor_sell,
  source_id: vendor_id,
  metadata: %{item_id: item_id, quantity: actual_quantity}
)
```

**Step 3: Commit**

```bash
git add apps/bezgelor_protocol/lib/bezgelor_protocol/handler/vendor_sell_handler.ex
git commit -m "refactor(vendor): migrate vendor_sell_handler to Economy.modify_currency"
```

---

## Task 13: Migrate Portal Admin Character Detail

**Files:**
- Modify: `apps/bezgelor_portal/lib/bezgelor_portal_web/live/admin/character_detail_live.ex`

**Step 1: Update alias**

Add:
```elixir
alias BezgelorDb.Economy
```

**Step 2: Update modify_currency call (around line 804)**

Replace:
```elixir
case Inventory.modify_currency(character.id, currency_type, amount) do
```

With:
```elixir
case Economy.modify_currency(character.id, currency_type, amount, :admin_grant,
       metadata: %{admin_id: socket.assigns.current_account.id}
     ) do
```

**Step 3: Commit**

```bash
git add apps/bezgelor_portal/lib/bezgelor_portal_web/live/admin/character_detail_live.ex
git commit -m "refactor(portal): migrate character_detail_live to Economy.modify_currency"
```

---

## Task 14: Migrate Economy Live Gift Tab

**Files:**
- Modify: `apps/bezgelor_portal/lib/bezgelor_portal_web/live/admin/economy_live.ex`

**Step 1: Update alias**

Replace:
```elixir
alias BezgelorDb.{Authorization, Characters, Inventory}
```

With:
```elixir
alias BezgelorDb.{Authorization, Characters, Economy, Inventory}
```

**Step 2: Update send_gift for currency (around line 439-474)**

Replace the currency case in `send_gift/5`:

```elixir
  defp send_gift(admin, character, "currency", params, reason) do
    with {currency_id, ""} <- Integer.parse(params["currency_type"] || ""),
         {amount, ""} <- Integer.parse(params["amount"] || ""),
         currency_type when not is_nil(currency_type) <- currency_id_to_atom(currency_id) do
      case Economy.modify_currency(character.id, currency_type, amount, :admin_grant,
             metadata: %{reason: reason, admin_id: admin.id}
           ) do
        {:ok, _} ->
          Authorization.log_action(
            admin,
            "character.grant_currency",
            "character",
            character.id,
            %{
              currency_type: currency_type,
              amount: amount,
              reason: reason
            }
          )

          currency_name =
            currency_type |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize()

          %{success: true, message: "Granted #{amount} #{currency_name} to #{character.name}"}

        {:error, :insufficient_funds} ->
          %{success: false, message: "Insufficient funds - cannot remove more than character has"}

        {:error, :invalid_currency} ->
          %{success: false, message: "Invalid currency type"}

        {:error, _} ->
          %{success: false, message: "Failed to modify currency"}
      end
    else
      nil -> %{success: false, message: "Unknown currency type"}
      _ -> %{success: false, message: "Invalid currency type or amount"}
    end
  end
```

**Step 3: Commit**

```bash
git add apps/bezgelor_portal/lib/bezgelor_portal_web/live/admin/economy_live.ex
git commit -m "refactor(portal): migrate economy_live gift tab to Economy.modify_currency"
```

---

## Task 15: Update Economy Live Dashboard with Real Data

**Files:**
- Modify: `apps/bezgelor_portal/lib/bezgelor_portal_web/live/admin/economy_live.ex`

**Step 1: Update mount to load real data and subscribe to PubSub**

Replace the `mount/3` function:

```elixir
  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(BezgelorPortal.PubSub, "economy:updates")
      Phoenix.PubSub.subscribe(BezgelorPortal.PubSub, "economy:alerts")
    end

    today_start = Date.utc_today() |> DateTime.new!(~T[00:00:00], "Etc/UTC")

    {:ok,
     assign(socket,
       page_title: "Economy Management",
       active_tab: :overview,
       # Real stats
       stats: load_economy_stats(today_start),
       recent_transactions: Economy.list_transactions(limit: 20),
       open_alerts: Economy.list_alerts(status: :open),
       live_feed: [],
       # Gift form state
       gift_form: %{
         "recipient_type" => "character",
         "recipient" => "",
         "gift_type" => "item",
         "item_id" => "",
         "quantity" => "1",
         "currency_type" => "1",
         "amount" => "",
         "reason" => ""
       },
       gift_result: nil,
       # Transaction filters
       filters: %{character: nil, source: nil}
     ), layout: {BezgelorPortalWeb.Layouts, :admin}}
  end

  defp load_economy_stats(today_start) do
    %{
      total_gold: Economy.total_currency_in_circulation(:gold),
      daily_generated: Economy.sum_transactions(:gold, from: today_start, direction: :positive),
      daily_removed: Economy.sum_transactions(:gold, from: today_start, direction: :negative) |> abs(),
      top_holders: Economy.top_currency_holders(:gold, limit: 10),
      by_source: Economy.transactions_by_source(from: today_start, currency_type: :gold),
      open_alert_count: Economy.open_alert_count()
    }
  end
```

**Step 2: Add handle_info for PubSub messages**

Add after the existing handle_event functions:

```elixir
  @impl true
  def handle_info({:economy_update, summary}, socket) do
    today_start = Date.utc_today() |> DateTime.new!(~T[00:00:00], "Etc/UTC")

    {:noreply,
     socket
     |> update(:live_feed, fn feed -> Enum.take([summary | feed], 50) end)
     |> assign(:stats, load_economy_stats(today_start))
     |> assign(:recent_transactions, Economy.list_transactions(limit: 20))}
  end

  @impl true
  def handle_info({:new_alert, type, details}, socket) do
    {:noreply,
     socket
     |> update(:open_alerts, fn alerts ->
       [%{type: type, details: details, inserted_at: DateTime.utc_now()} | alerts]
     end)
     |> put_flash(:warning, "New economy alert: #{type}")}
  end
```

**Step 3: Update overview_tab to use real stats**

Replace the `overview_tab/1` function:

```elixir
  defp overview_tab(assigns) do
    ~H"""
    <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
      <.stat_card
        title="Total Gold in Circulation"
        value={format_gold(@stats.total_gold)}
        subtitle="Across all characters"
        icon="hero-currency-dollar"
      />
      <.stat_card
        title="Daily Gold Generated"
        value={format_gold(@stats.daily_generated)}
        subtitle="Quest rewards, loot, etc."
        icon="hero-arrow-trending-up"
      />
      <.stat_card
        title="Daily Gold Removed"
        value={format_gold(@stats.daily_removed)}
        subtitle="Vendors, repairs, etc."
        icon="hero-arrow-trending-down"
      />
      <.stat_card
        title="Open Alerts"
        value={@stats.open_alert_count}
        subtitle="Requires investigation"
        icon="hero-exclamation-triangle"
      />
    </div>

    <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mt-6">
      <!-- Top Gold Holders -->
      <div class="card bg-base-100 shadow">
        <div class="card-body">
          <h2 class="card-title">Top Gold Holders</h2>
          <table class="table table-sm">
            <thead>
              <tr>
                <th>Rank</th>
                <th>Character</th>
                <th class="text-right">Gold</th>
              </tr>
            </thead>
            <tbody>
              <%= for {holder, idx} <- Enum.with_index(@stats.top_holders, 1) do %>
                <tr>
                  <td>{idx}</td>
                  <td>{holder.character_name}</td>
                  <td class="text-right">{format_gold(holder.balance)}</td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>

      <!-- Gold Flow by Source -->
      <div class="card bg-base-100 shadow">
        <div class="card-body">
          <h2 class="card-title">Today's Gold Flow by Source</h2>
          <table class="table table-sm">
            <thead>
              <tr>
                <th>Source</th>
                <th class="text-right">Income</th>
                <th class="text-right">Expense</th>
                <th class="text-right">Net</th>
              </tr>
            </thead>
            <tbody>
              <%= for source <- @stats.by_source do %>
                <tr>
                  <td>{source.source |> to_string() |> String.replace("_", " ") |> String.capitalize()}</td>
                  <td class="text-right text-success">{format_gold(source.income || 0)}</td>
                  <td class="text-right text-error">{format_gold(abs(source.expense || 0))}</td>
                  <td class="text-right">{format_gold(source.total || 0)}</td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>
    </div>

    <!-- Live Feed -->
    <div class="card bg-base-100 shadow mt-6">
      <div class="card-body">
        <h2 class="card-title">
          <span class="loading loading-dots loading-xs"></span>
          Live Transaction Feed
        </h2>
        <div class="overflow-x-auto max-h-64 overflow-y-auto">
          <table class="table table-xs">
            <thead>
              <tr>
                <th>Time</th>
                <th>Source</th>
                <th>Count</th>
                <th>Total</th>
              </tr>
            </thead>
            <tbody>
              <%= for update <- @live_feed do %>
                <tr>
                  <td class="text-xs">{Calendar.strftime(update.timestamp, "%H:%M:%S")}</td>
                  <td>
                    <%= for source <- update.by_source do %>
                      <span class="badge badge-sm">{source.key}</span>
                    <% end %>
                  </td>
                  <td>{update.transaction_count}</td>
                  <td>
                    <%= for currency <- update.by_currency do %>
                      <span>{currency.key}: {format_gold(currency.total)}</span>
                    <% end %>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end

  defp format_gold(nil), do: "0"
  defp format_gold(amount) when is_integer(amount) do
    amount
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end
```

**Step 4: Commit**

```bash
git add apps/bezgelor_portal/lib/bezgelor_portal_web/live/admin/economy_live.ex
git commit -m "feat(portal): implement real-time economy dashboard with live data"
```

---

## Task 16: Deprecate Inventory.modify_currency

**Files:**
- Modify: `apps/bezgelor_db/lib/bezgelor_db/inventory.ex`

**Step 1: Add deprecation warning**

Update `modify_currency/3` (around line 622):

```elixir
  @doc """
  Modify a character's currency balance.

  **DEPRECATED:** Use `BezgelorDb.Economy.modify_currency/5` instead for transaction logging.

  This function will delegate to Economy with `:other` source and log a warning.
  """
  @deprecated "Use BezgelorDb.Economy.modify_currency/5 for transaction logging"
  @spec modify_currency(integer(), atom(), integer()) ::
          {:ok, CharacterCurrency.t()} | {:error, atom()}
  def modify_currency(character_id, currency_type, amount) when is_atom(currency_type) do
    Logger.warning(
      "Inventory.modify_currency/3 is deprecated. " <>
        "Use Economy.modify_currency/5 for transaction logging. " <>
        "Caller: #{inspect(Process.info(self(), :current_stacktrace))}"
    )

    BezgelorDb.Economy.modify_currency(character_id, currency_type, amount, :other)
  end
```

**Step 2: Update add_currency and spend_currency to use Economy**

```elixir
  @doc """
  Add a specific amount of currency to a character.

  **DEPRECATED:** Use `BezgelorDb.Economy.modify_currency/5` instead.
  """
  @deprecated "Use BezgelorDb.Economy.modify_currency/5 for transaction logging"
  @spec add_currency(integer(), atom(), non_neg_integer()) ::
          {:ok, CharacterCurrency.t()} | {:error, atom()}
  def add_currency(character_id, currency_type, amount)
      when is_atom(currency_type) and amount >= 0 do
    Logger.warning("Inventory.add_currency/3 is deprecated. Use Economy.modify_currency/5.")
    BezgelorDb.Economy.modify_currency(character_id, currency_type, amount, :other)
  end

  @doc """
  Spend a specific amount of currency from a character.

  **DEPRECATED:** Use `BezgelorDb.Economy.modify_currency/5` with negative amount instead.
  """
  @deprecated "Use BezgelorDb.Economy.modify_currency/5 for transaction logging"
  @spec spend_currency(integer(), atom(), non_neg_integer()) ::
          {:ok, CharacterCurrency.t()} | {:error, atom()}
  def spend_currency(character_id, currency_type, amount)
      when is_atom(currency_type) and amount >= 0 do
    Logger.warning("Inventory.spend_currency/3 is deprecated. Use Economy.modify_currency/5.")
    BezgelorDb.Economy.modify_currency(character_id, currency_type, -amount, :other)
  end
```

**Step 3: Run full test suite**

Run: `mix test`
Expected: PASS (with deprecation warnings)

**Step 4: Commit**

```bash
git add apps/bezgelor_db/lib/bezgelor_db/inventory.ex
git commit -m "deprecate: mark Inventory currency functions as deprecated, delegate to Economy"
```

---

## Task 17: Run Full Test Suite and Fix Any Issues

**Step 1: Run all tests**

Run: `mix test`

**Step 2: Fix any failures

Address test failures as they arise.

**Step 3: Commit fixes if needed**

```bash
git add -A
git commit -m "fix: address test failures from economy integration"
```

---

## Task 18: Final Verification

**Step 1: Start the server**

Run: `mix phx.server`

**Step 2: Verify in browser**

1. Navigate to `http://localhost:4000/admin/economy`
2. Verify dashboard loads with real data
3. Send a gift via gift tab
4. Verify transaction appears in live feed

**Step 3: Commit any final fixes**

```bash
git add -A
git commit -m "feat: complete portal economy implementation"
```

---

## Summary

| Task | Description |
|------|-------------|
| 1 | Create CurrencyTransaction schema |
| 2 | Create EconomyAlert schema |
| 3 | Create database migration |
| 4 | Create Economy context module |
| 5 | Create Economy.Telemetry GenServer |
| 6 | Create Economy.Alerts GenServer |
| 7 | Add GenServers to application supervisor |
| 8 | Add economy configuration |
| 9 | Add telemetry metrics to Portal |
| 10 | Migrate quest reward handler |
| 11 | Migrate vendor handler |
| 12 | Migrate vendor sell handler |
| 13 | Migrate portal character detail |
| 14 | Migrate economy live gift tab |
| 15 | Update economy dashboard with real data |
| 16 | Deprecate Inventory.modify_currency |
| 17 | Run full test suite |
| 18 | Final verification |
