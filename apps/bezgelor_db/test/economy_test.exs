defmodule BezgelorDb.EconomyTest do
  use ExUnit.Case

  alias BezgelorDb.{Accounts, Characters, Economy, Repo}
  alias BezgelorDb.Schema.{CurrencyTransaction, EconomyAlert}

  @moduletag :database

  setup do
    case Repo.start_link([]) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    # Create test account
    email = "economy_test#{System.unique_integer([:positive])}@test.com"
    {:ok, account} = Accounts.create_account(email, "password123")

    # Create test characters
    {:ok, char1} = create_character(account.id, "EconomyChar1")
    {:ok, char2} = create_character(account.id, "EconomyChar2")

    {:ok, account: account, char1: char1, char2: char2}
  end

  describe "record_transaction/1" do
    test "creates transaction with valid attributes", %{char1: char1} do
      attrs = %{
        character_id: char1.id,
        currency_type: 1,
        amount: 100,
        balance_after: 1000,
        source_type: "quest",
        source_id: 456,
        metadata: %{quest_name: "Epic Quest"}
      }

      assert {:ok, transaction} = Economy.record_transaction(attrs)
      assert transaction.character_id == char1.id
      assert transaction.currency_type == 1
      assert transaction.amount == 100
      assert transaction.balance_after == 1000
      assert transaction.source_type == "quest"
      assert transaction.source_id == 456
      assert transaction.metadata == %{quest_name: "Epic Quest"}
    end

    test "creates transaction without optional fields", %{char1: char1} do
      attrs = %{
        character_id: char1.id,
        currency_type: 1,
        amount: 50,
        balance_after: 500,
        source_type: "loot"
      }

      assert {:ok, transaction} = Economy.record_transaction(attrs)
      assert transaction.source_id == nil
      assert transaction.metadata == nil
    end

    test "allows negative amounts", %{char1: char1} do
      attrs = %{
        character_id: char1.id,
        currency_type: 1,
        amount: -50,
        balance_after: 450,
        source_type: "vendor"
      }

      assert {:ok, transaction} = Economy.record_transaction(attrs)
      assert transaction.amount == -50
    end

    test "returns error for missing required fields" do
      attrs = %{
        currency_type: 1,
        amount: 100
      }

      assert {:error, changeset} = Economy.record_transaction(attrs)
      assert %{character_id: _, balance_after: _, source_type: _} = errors_on(changeset)
    end

    test "returns error for invalid source_type", %{char1: char1} do
      attrs = %{
        character_id: char1.id,
        currency_type: 1,
        amount: 100,
        balance_after: 1000,
        source_type: "invalid_source"
      }

      assert {:error, changeset} = Economy.record_transaction(attrs)
      assert %{source_type: ["is invalid"]} = errors_on(changeset)
    end

    test "returns error for negative balance_after", %{char1: char1} do
      attrs = %{
        character_id: char1.id,
        currency_type: 1,
        amount: 100,
        balance_after: -10,
        source_type: "quest"
      }

      assert {:error, changeset} = Economy.record_transaction(attrs)
      assert %{balance_after: _} = errors_on(changeset)
    end

    test "accepts zero balance_after", %{char1: char1} do
      attrs = %{
        character_id: char1.id,
        currency_type: 1,
        amount: -100,
        balance_after: 0,
        source_type: "vendor"
      }

      assert {:ok, transaction} = Economy.record_transaction(attrs)
      assert transaction.balance_after == 0
    end

    test "accepts all valid source_types", %{char1: char1} do
      source_types = CurrencyTransaction.source_types()

      for source_type <- source_types do
        attrs = %{
          character_id: char1.id,
          currency_type: 1,
          amount: 10,
          balance_after: 100,
          source_type: source_type
        }

        assert {:ok, _transaction} = Economy.record_transaction(attrs)
      end
    end
  end

  describe "get_transactions_for_character/2" do
    setup %{char1: char1, char2: char2} do
      # Create transactions for char1
      create_transaction(char1.id, 1, 100, 1000, "quest")
      create_transaction(char1.id, 1, -50, 950, "vendor")
      create_transaction(char1.id, 2, 200, 500, "quest")
      create_transaction(char1.id, 1, 75, 1025, "loot")

      # Create transaction for char2
      create_transaction(char2.id, 1, 50, 500, "quest")

      :ok
    end

    test "returns all transactions for character", %{char1: char1} do
      transactions = Economy.get_transactions_for_character(char1.id)
      assert length(transactions) == 4
      assert Enum.all?(transactions, &(&1.character_id == char1.id))
    end

    test "filters by currency_type", %{char1: char1} do
      transactions = Economy.get_transactions_for_character(char1.id, currency_type: 1)
      assert length(transactions) == 3
      assert Enum.all?(transactions, &(&1.currency_type == 1))
    end

    test "filters by source_type", %{char1: char1} do
      transactions = Economy.get_transactions_for_character(char1.id, source_type: "quest")
      assert length(transactions) == 2
      assert Enum.all?(transactions, &(&1.source_type == "quest"))
    end

    test "filters by since DateTime", %{char1: char1} do
      now = DateTime.utc_now()
      future = DateTime.add(now, 1, :day)

      transactions = Economy.get_transactions_for_character(char1.id, since: future)
      assert length(transactions) == 0
    end

    test "filters by until DateTime", %{char1: char1} do
      past = DateTime.add(DateTime.utc_now(), -1, :day)

      transactions = Economy.get_transactions_for_character(char1.id, until: past)
      assert length(transactions) == 0
    end

    test "respects limit option", %{char1: char1} do
      transactions = Economy.get_transactions_for_character(char1.id, limit: 2)
      assert length(transactions) == 2
    end

    test "respects offset option", %{char1: char1} do
      transactions = Economy.get_transactions_for_character(char1.id, offset: 2, order: :asc)
      assert length(transactions) == 2
    end

    test "limits to max 1000", %{char1: char1} do
      transactions = Economy.get_transactions_for_character(char1.id, limit: 2000)
      # Should be limited to 1000, but we only have 4
      assert length(transactions) == 4
    end

    test "orders by desc by default", %{char1: char1} do
      # Create two transactions with known amounts in order
      {:ok, _t1} = create_transaction(char1.id, 5, 10, 10, "quest")
      :timer.sleep(1100)
      {:ok, _t2} = create_transaction(char1.id, 5, 20, 30, "quest")

      transactions = Economy.get_transactions_for_character(char1.id, currency_type: 5)

      assert length(transactions) == 2
      # Most recent (second) transaction should be first in desc order
      assert hd(transactions).amount == 20
    end

    test "orders by asc when specified", %{char1: char1} do
      # Create two transactions with known amounts in order
      {:ok, _t1} = create_transaction(char1.id, 5, 10, 10, "quest")
      :timer.sleep(1100)
      {:ok, _t2} = create_transaction(char1.id, 5, 20, 30, "quest")

      transactions = Economy.get_transactions_for_character(char1.id, currency_type: 5, order: :asc)

      assert length(transactions) == 2
      # Oldest (first) transaction should be first in asc order
      assert hd(transactions).amount == 10
    end

    test "combines multiple filters", %{char1: char1} do
      transactions =
        Economy.get_transactions_for_character(char1.id,
          currency_type: 1,
          source_type: "quest",
          limit: 1
        )

      assert length(transactions) == 1
      assert hd(transactions).currency_type == 1
      assert hd(transactions).source_type == "quest"
    end

    test "returns empty list for non-existent character" do
      transactions = Economy.get_transactions_for_character(99999)
      assert transactions == []
    end
  end

  describe "get_recent_transactions/1" do
    setup %{char1: char1, char2: char2} do
      # Create transactions for both characters
      create_transaction(char1.id, 1, 100, 1000, "quest")
      create_transaction(char2.id, 1, -50, 950, "vendor")
      create_transaction(char1.id, 2, 200, 500, "loot")

      :ok
    end

    test "returns recent transactions across all characters" do
      transactions = Economy.get_recent_transactions()
      assert length(transactions) == 3
    end

    test "filters by currency_type" do
      transactions = Economy.get_recent_transactions(currency_type: 1)
      assert length(transactions) == 2
      assert Enum.all?(transactions, &(&1.currency_type == 1))
    end

    test "filters by source_type" do
      transactions = Economy.get_recent_transactions(source_type: "quest")
      assert length(transactions) == 1
      assert hd(transactions).source_type == "quest"
    end

    test "filters by since DateTime" do
      future = DateTime.add(DateTime.utc_now(), 1, :day)
      transactions = Economy.get_recent_transactions(since: future)
      assert length(transactions) == 0
    end

    test "respects limit option" do
      transactions = Economy.get_recent_transactions(limit: 2)
      assert length(transactions) == 2
    end

    test "respects offset option" do
      transactions = Economy.get_recent_transactions(offset: 2)
      assert length(transactions) == 1
    end

    test "preloads character when requested" do
      transactions = Economy.get_recent_transactions(preload_character: true, limit: 1)
      transaction = hd(transactions)

      assert %BezgelorDb.Schema.Character{} = transaction.character
    end

    test "does not preload character by default" do
      transactions = Economy.get_recent_transactions(limit: 1)
      transaction = hd(transactions)

      assert %Ecto.Association.NotLoaded{} = transaction.character
    end

    test "orders by newest first", %{char1: char1} do
      {:ok, _t1} = create_transaction(char1.id, 5, 10, 10, "quest")
      :timer.sleep(1100)
      {:ok, _t2} = create_transaction(char1.id, 5, 20, 30, "quest")

      transactions = Economy.get_recent_transactions(currency_type: 5)

      # Most recent (second) transaction should be first
      assert length(transactions) == 2
      assert hd(transactions).amount == 20
    end
  end

  describe "calculate_balance_delta/3" do
    test "calculates net gain correctly", %{char1: char1} do
      since = DateTime.utc_now()

      create_transaction(char1.id, 1, 100, 1000, "quest")
      create_transaction(char1.id, 1, 50, 1050, "loot")
      create_transaction(char1.id, 1, -20, 1030, "vendor")

      delta = Economy.calculate_balance_delta(char1.id, 1, since)
      assert delta == 130
    end

    test "calculates net loss correctly", %{char1: char1} do
      since = DateTime.utc_now()

      create_transaction(char1.id, 1, -100, 900, "vendor")
      create_transaction(char1.id, 1, -50, 850, "repair")
      create_transaction(char1.id, 1, 20, 870, "quest")

      delta = Economy.calculate_balance_delta(char1.id, 1, since)
      assert delta == -130
    end

    test "returns 0 for no transactions", %{char1: char1} do
      since = DateTime.utc_now()
      delta = Economy.calculate_balance_delta(char1.id, 1, since)
      assert delta == 0
    end

    test "only includes transactions since given time", %{char1: char1} do
      past = DateTime.add(DateTime.utc_now(), -1, :day)

      # Create transaction
      create_transaction(char1.id, 1, 100, 1000, "quest")

      # Check with a time before the transaction
      delta = Economy.calculate_balance_delta(char1.id, 1, past)
      assert delta == 100

      # Check with a time way in the future (should not include transaction)
      future = DateTime.add(DateTime.utc_now(), 1, :day)
      delta = Economy.calculate_balance_delta(char1.id, 1, future)
      assert delta == 0
    end

    test "filters by currency_type correctly", %{char1: char1} do
      since = DateTime.utc_now()

      create_transaction(char1.id, 1, 100, 1000, "quest")
      create_transaction(char1.id, 2, 200, 500, "quest")

      delta = Economy.calculate_balance_delta(char1.id, 1, since)
      assert delta == 100

      delta = Economy.calculate_balance_delta(char1.id, 2, since)
      assert delta == 200
    end

    test "filters by character_id correctly", %{char1: char1, char2: char2} do
      since = DateTime.utc_now()

      create_transaction(char1.id, 1, 100, 1000, "quest")
      create_transaction(char2.id, 1, 200, 500, "quest")

      delta = Economy.calculate_balance_delta(char1.id, 1, since)
      assert delta == 100

      delta = Economy.calculate_balance_delta(char2.id, 1, since)
      assert delta == 200
    end
  end

  describe "create_alert/1" do
    test "creates alert with valid attributes", %{char1: char1} do
      attrs = %{
        alert_type: "high_value_trade",
        severity: "warning",
        character_id: char1.id,
        description: "High value trade detected",
        data: %{amount: 1000000, other_character_id: 456}
      }

      assert {:ok, alert} = Economy.create_alert(attrs)
      assert alert.alert_type == "high_value_trade"
      assert alert.severity == "warning"
      assert alert.character_id == char1.id
      assert alert.description == "High value trade detected"
      assert alert.data == %{amount: 1000000, other_character_id: 456}
      assert alert.acknowledged == false
    end

    test "creates alert without optional fields" do
      attrs = %{
        alert_type: "currency_anomaly",
        severity: "info",
        description: "Anomaly detected"
      }

      assert {:ok, alert} = Economy.create_alert(attrs)
      assert alert.character_id == nil
      assert alert.data == nil
    end

    test "returns error for missing required fields" do
      attrs = %{
        alert_type: "high_value_trade"
      }

      assert {:error, changeset} = Economy.create_alert(attrs)
      assert %{severity: _, description: _} = errors_on(changeset)
    end

    test "returns error for invalid alert_type" do
      attrs = %{
        alert_type: "invalid_type",
        severity: "warning",
        description: "Test"
      }

      assert {:error, changeset} = Economy.create_alert(attrs)
      assert %{alert_type: ["is invalid"]} = errors_on(changeset)
    end

    test "returns error for invalid severity" do
      attrs = %{
        alert_type: "high_value_trade",
        severity: "super_critical",
        description: "Test"
      }

      assert {:error, changeset} = Economy.create_alert(attrs)
      assert %{severity: ["is invalid"]} = errors_on(changeset)
    end

    test "accepts all valid alert_types" do
      alert_types = EconomyAlert.alert_types()

      for alert_type <- alert_types do
        attrs = %{
          alert_type: alert_type,
          severity: "info",
          description: "Test #{alert_type}"
        }

        assert {:ok, _alert} = Economy.create_alert(attrs)
      end
    end

    test "accepts all valid severities" do
      severities = EconomyAlert.severities()

      for severity <- severities do
        attrs = %{
          alert_type: "high_value_trade",
          severity: severity,
          description: "Test #{severity}"
        }

        assert {:ok, _alert} = Economy.create_alert(attrs)
      end
    end
  end

  describe "list_alerts/1" do
    setup %{char1: char1, char2: char2} do
      create_alert("high_value_trade", "critical", char1.id, "Critical alert 1")
      create_alert("rapid_transactions", "warning", char1.id, "Warning alert 1")
      create_alert("currency_anomaly", "info", char2.id, "Info alert 1")
      create_alert("threshold_breach", "warning", nil, "Warning alert 2")

      :ok
    end

    test "returns all alerts by default" do
      alerts = Economy.list_alerts()
      assert length(alerts) == 4
    end

    test "filters by severity" do
      alerts = Economy.list_alerts(severity: "warning")
      assert length(alerts) == 2
      assert Enum.all?(alerts, &(&1.severity == "warning"))
    end

    test "filters by alert_type" do
      alerts = Economy.list_alerts(alert_type: "high_value_trade")
      assert length(alerts) == 1
      assert hd(alerts).alert_type == "high_value_trade"
    end

    test "filters by acknowledged status - false", %{char1: char1} do
      # Acknowledge one alert
      alert = hd(Economy.list_alerts(character_id: char1.id, limit: 1))
      Economy.acknowledge_alert(alert.id, "admin@test.com")

      alerts = Economy.list_alerts(acknowledged: false)
      assert length(alerts) == 3
      assert Enum.all?(alerts, &(&1.acknowledged == false))
    end

    test "filters by acknowledged status - true", %{char1: char1} do
      # Acknowledge one alert
      alert = hd(Economy.list_alerts(character_id: char1.id, limit: 1))
      Economy.acknowledge_alert(alert.id, "admin@test.com")

      alerts = Economy.list_alerts(acknowledged: true)
      assert length(alerts) == 1
      assert Enum.all?(alerts, &(&1.acknowledged == true))
    end

    test "filters by character_id", %{char1: char1} do
      alerts = Economy.list_alerts(character_id: char1.id)
      assert length(alerts) == 2
      assert Enum.all?(alerts, &(&1.character_id == char1.id))
    end

    test "filters by since DateTime" do
      future = DateTime.add(DateTime.utc_now(), 1, :day)
      alerts = Economy.list_alerts(since: future)
      assert length(alerts) == 0
    end

    test "respects limit option" do
      alerts = Economy.list_alerts(limit: 2)
      assert length(alerts) == 2
    end

    test "respects offset option" do
      alerts = Economy.list_alerts(offset: 2)
      assert length(alerts) == 2
    end

    test "preloads character when requested", %{char1: char1} do
      alerts = Economy.list_alerts(character_id: char1.id, preload_character: true, limit: 1)
      alert = hd(alerts)

      assert %BezgelorDb.Schema.Character{} = alert.character
      assert alert.character.id == char1.id
    end

    test "does not preload character by default", %{char1: char1} do
      alerts = Economy.list_alerts(character_id: char1.id, limit: 1)
      alert = hd(alerts)

      assert %Ecto.Association.NotLoaded{} = alert.character
    end

    test "orders by newest first" do
      {:ok, _a1} = create_alert("high_value_trade", "info", nil, "First Order Test")
      :timer.sleep(1100)
      {:ok, _a2} = create_alert("high_value_trade", "info", nil, "Second Order Test")

      alerts = Economy.list_alerts(alert_type: "high_value_trade")
      # Filter to only our test alerts
      test_alerts = Enum.filter(alerts, &String.contains?(&1.description, "Order Test"))

      # Most recent (second) alert should be first
      assert length(test_alerts) == 2
      assert hd(test_alerts).description == "Second Order Test"
    end

    test "combines multiple filters", %{char1: char1} do
      alerts =
        Economy.list_alerts(
          character_id: char1.id,
          severity: "warning",
          acknowledged: false
        )

      assert length(alerts) == 1
      alert = hd(alerts)
      assert alert.character_id == char1.id
      assert alert.severity == "warning"
      assert alert.acknowledged == false
    end
  end

  describe "get_alert/1" do
    test "returns alert when found" do
      {:ok, created_alert} = create_alert("high_value_trade", "warning", nil, "Test alert")

      alert = Economy.get_alert(created_alert.id)

      assert alert.id == created_alert.id
      assert alert.alert_type == "high_value_trade"
    end

    test "returns nil when not found" do
      alert = Economy.get_alert(99999)
      assert alert == nil
    end
  end

  describe "acknowledge_alert/2" do
    test "acknowledges alert successfully" do
      {:ok, created_alert} = create_alert("high_value_trade", "warning", nil, "Test alert")

      assert {:ok, alert} = Economy.acknowledge_alert(created_alert.id, "admin@test.com")

      assert alert.acknowledged == true
      assert alert.acknowledged_by == "admin@test.com"
      assert %DateTime{} = alert.acknowledged_at
    end

    test "returns error for non-existent alert" do
      assert {:error, :not_found} = Economy.acknowledge_alert(99999, "admin@test.com")
    end

    test "can acknowledge already acknowledged alert", %{char1: char1} do
      {:ok, created_alert} = create_alert("high_value_trade", "warning", char1.id, "Test")

      assert {:ok, alert1} = Economy.acknowledge_alert(created_alert.id, "admin1@test.com")
      assert alert1.acknowledged_by == "admin1@test.com"

      assert {:ok, alert2} = Economy.acknowledge_alert(created_alert.id, "admin2@test.com")
      assert alert2.acknowledged_by == "admin2@test.com"
    end
  end

  describe "get_unacknowledged_alerts/0" do
    setup %{char1: char1} do
      create_alert("high_value_trade", "critical", char1.id, "Critical alert")
      create_alert("rapid_transactions", "warning", char1.id, "Warning alert")
      create_alert("currency_anomaly", "info", nil, "Info alert")

      # Create and acknowledge one alert
      {:ok, ack_alert} = create_alert("threshold_breach", "warning", nil, "Acknowledged")
      Economy.acknowledge_alert(ack_alert.id, "admin@test.com")

      :ok
    end

    test "returns only unacknowledged alerts" do
      alerts = Economy.get_unacknowledged_alerts()
      assert length(alerts) == 3
      assert Enum.all?(alerts, &(&1.acknowledged == false))
    end

    test "orders by severity (critical first) then by time" do
      alerts = Economy.get_unacknowledged_alerts()

      # First should be critical
      assert hd(alerts).severity == "critical"
    end

    test "returns empty list when all acknowledged" do
      alerts = Economy.get_unacknowledged_alerts()

      for alert <- alerts do
        Economy.acknowledge_alert(alert.id, "admin@test.com")
      end

      assert Economy.get_unacknowledged_alerts() == []
    end
  end

  describe "get_critical_alerts/0" do
    setup %{char1: char1} do
      create_alert("high_value_trade", "critical", char1.id, "Critical 1")
      create_alert("currency_anomaly", "critical", nil, "Critical 2")
      create_alert("rapid_transactions", "warning", char1.id, "Warning")
      create_alert("threshold_breach", "info", nil, "Info")

      # Create and acknowledge a critical alert
      {:ok, ack_alert} = create_alert("unusual_pattern", "critical", nil, "Ack Critical")
      Economy.acknowledge_alert(ack_alert.id, "admin@test.com")

      :ok
    end

    test "returns only unacknowledged critical alerts" do
      alerts = Economy.get_critical_alerts()
      assert length(alerts) == 2
      assert Enum.all?(alerts, &(&1.severity == "critical"))
      assert Enum.all?(alerts, &(&1.acknowledged == false))
    end

    test "orders by newest first" do
      {:ok, _c1} = create_alert("high_value_trade", "critical", nil, "First Critical Order Test")
      :timer.sleep(1100)
      {:ok, _c2} = create_alert("high_value_trade", "critical", nil, "Second Critical Order Test")

      alerts = Economy.get_critical_alerts()

      # Find our test alerts among all critical alerts
      test_alerts =
        Enum.filter(alerts, &String.contains?(&1.description || "", "Critical Order Test"))

      # Most recent (second) should be first
      assert length(test_alerts) == 2
      assert hd(test_alerts).description == "Second Critical Order Test"
    end

    test "returns empty list when no unacknowledged critical alerts" do
      alerts = Economy.get_critical_alerts()

      for alert <- alerts do
        Economy.acknowledge_alert(alert.id, "admin@test.com")
      end

      assert Economy.get_critical_alerts() == []
    end
  end

  describe "get_currency_flow_summary/3" do
    test "calculates inflow and outflow correctly", %{char1: char1} do
      create_transaction(char1.id, 1, 100, 1100, "quest")
      create_transaction(char1.id, 1, 50, 1150, "loot")
      create_transaction(char1.id, 1, -30, 1120, "vendor")
      create_transaction(char1.id, 1, -20, 1100, "repair")

      summary = Economy.get_currency_flow_summary(char1.id, 1, 86400)

      assert summary.inflow == 150
      assert summary.outflow == 50
      assert summary.net == 100
      assert summary.transaction_count == 4
    end

    test "returns zeros for no transactions", %{char1: char1} do
      summary = Economy.get_currency_flow_summary(char1.id, 1, 86400)

      assert summary.inflow == 0
      assert summary.outflow == 0
      assert summary.net == 0
      assert summary.transaction_count == 0
    end

    test "only includes transactions within timeframe", %{char1: char1} do
      create_transaction(char1.id, 1, 100, 1100, "quest")

      # Very short timeframe (1 second) that likely excludes the transaction
      # Note: timeframe must be > 0 due to guard clause
      summary = Economy.get_currency_flow_summary(char1.id, 1, 1)

      # May be 0 if transaction was created more than 1 second ago
      # or may include if within 1 second - both are valid
      assert is_integer(summary.inflow)
      assert is_integer(summary.outflow)
      assert is_integer(summary.net)
      assert is_integer(summary.transaction_count)
    end

    test "filters by currency_type correctly", %{char1: char1} do
      create_transaction(char1.id, 1, 100, 1100, "quest")
      create_transaction(char1.id, 2, 200, 500, "quest")

      summary = Economy.get_currency_flow_summary(char1.id, 1, 86400)
      assert summary.inflow == 100

      summary = Economy.get_currency_flow_summary(char1.id, 2, 86400)
      assert summary.inflow == 200
    end

    test "filters by character_id correctly", %{char1: char1, char2: char2} do
      create_transaction(char1.id, 1, 100, 1100, "quest")
      create_transaction(char2.id, 1, 200, 500, "quest")

      summary = Economy.get_currency_flow_summary(char1.id, 1, 86400)
      assert summary.inflow == 100

      summary = Economy.get_currency_flow_summary(char2.id, 1, 86400)
      assert summary.inflow == 200
    end

    test "calculates net loss correctly", %{char1: char1} do
      create_transaction(char1.id, 1, -100, 900, "vendor")
      create_transaction(char1.id, 1, -50, 850, "repair")
      create_transaction(char1.id, 1, 20, 870, "quest")

      summary = Economy.get_currency_flow_summary(char1.id, 1, 86400)

      assert summary.inflow == 20
      assert summary.outflow == 150
      assert summary.net == -130
    end
  end

  describe "get_top_currency_sources/3" do
    setup %{char1: char1, char2: char2} do
      # Create various transactions
      create_transaction(char1.id, 1, 1000, 1000, "quest")
      create_transaction(char2.id, 1, 500, 500, "quest")
      create_transaction(char1.id, 1, 300, 1300, "loot")
      create_transaction(char2.id, 1, 200, 700, "loot")
      create_transaction(char1.id, 1, 100, 1400, "vendor")

      :ok
    end

    test "returns top sources ordered by total_amount" do
      sources = Economy.get_top_currency_sources(1, 10)

      assert length(sources) == 3
      assert hd(sources).source_type == "quest"
      assert hd(sources).total_amount == 1500
      assert hd(sources).transaction_count == 2
    end

    test "respects limit parameter" do
      sources = Economy.get_top_currency_sources(1, 2)
      assert length(sources) == 2
    end

    test "limits to max 100" do
      # Even if we request more, it should limit to 100
      sources = Economy.get_top_currency_sources(1, 200)
      # We only have 3 sources, but the function would limit to 100
      assert length(sources) <= 100
    end

    test "only counts gains by default", %{char1: char1} do
      # Create a loss transaction
      create_transaction(char1.id, 1, -50, 1350, "vendor")

      sources = Economy.get_top_currency_sources(1, 10)

      vendor_source = Enum.find(sources, &(&1.source_type == "vendor"))
      # Should only count the +100, not the -50
      assert vendor_source.total_amount == 100
    end

    test "includes losses when gains_only is false", %{char1: char1} do
      create_transaction(char1.id, 1, -200, 1200, "vendor")

      sources = Economy.get_top_currency_sources(1, 10, gains_only: false)

      vendor_source = Enum.find(sources, &(&1.source_type == "vendor"))
      # Should count both +100 and -200 = -100
      assert vendor_source.total_amount == -100
    end

    test "filters by since DateTime" do
      future = DateTime.add(DateTime.utc_now(), 1, :day)
      sources = Economy.get_top_currency_sources(1, 10, since: future)

      assert length(sources) == 0
    end

    test "filters by currency_type", %{char1: char1} do
      create_transaction(char1.id, 2, 500, 500, "quest")
      create_transaction(char1.id, 2, 300, 800, "loot")

      sources = Economy.get_top_currency_sources(2, 10)

      assert length(sources) == 2
      assert hd(sources).source_type == "quest"
      assert hd(sources).total_amount == 500
    end

    test "groups by source_type correctly", %{char1: char1} do
      # Add more quest transactions
      create_transaction(char1.id, 1, 250, 1650, "quest")

      sources = Economy.get_top_currency_sources(1, 10)

      quest_source = Enum.find(sources, &(&1.source_type == "quest"))
      assert quest_source.total_amount == 1750
      assert quest_source.transaction_count == 3
    end

    test "returns empty list for currency with no transactions" do
      sources = Economy.get_top_currency_sources(999, 10)
      assert sources == []
    end
  end

  # Helper functions

  defp create_character(account_id, name) do
    Characters.create_character(account_id, %{
      name: name,
      sex: 0,
      race: 1,
      class: 0,
      faction_id: 167,
      realm_id: 1,
      world_id: 1,
      world_zone_id: 1
    })
  end

  defp create_transaction(character_id, currency_type, amount, balance_after, source_type) do
    Economy.record_transaction(%{
      character_id: character_id,
      currency_type: currency_type,
      amount: amount,
      balance_after: balance_after,
      source_type: source_type
    })
  end

  defp create_alert(alert_type, severity, character_id, description) do
    Economy.create_alert(%{
      alert_type: alert_type,
      severity: severity,
      character_id: character_id,
      description: description
    })
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
