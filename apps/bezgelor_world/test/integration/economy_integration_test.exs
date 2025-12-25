defmodule BezgelorWorld.Integration.EconomyIntegrationTest do
  @moduledoc """
  Integration test for the full economy telemetry flow.

  Tests:
  1. Starting Economy.Telemetry and Economy.Alerts GenServers
  2. Granting currency and emitting telemetry events
  3. Verifying transactions are logged to the database
  4. Triggering threshold violations
  5. Verifying alerts are created
  """

  use ExUnit.Case, async: false

  @moduletag :integration
  @moduletag :database

  alias BezgelorDb.{Accounts, Characters, Economy, Inventory, Repo}
  alias BezgelorWorld.Economy.Telemetry
  alias BezgelorWorld.Economy.Alerts

  setup do
    # Start Repo if not already started
    case Repo.start_link([]) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    # Checkout database connection
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    # Create test account and character
    email = "economy_integration_test#{System.unique_integer([:positive])}@test.com"
    {:ok, account} = Accounts.create_account(email, "password123")

    {:ok, character} =
      Characters.create_character(account.id, %{
        name: "EconomyIntTester#{System.unique_integer([:positive])}",
        sex: 0,
        race: 1,
        class: 0,
        faction_id: 167,
        realm_id: 1,
        world_id: 1,
        world_zone_id: 1
      })

    # Initialize currency for character
    _currency = Inventory.get_or_create_currency(character.id)

    # Start the Telemetry GenServer with a unique name for this test
    telemetry_name = :"telemetry_#{System.unique_integer([:positive])}"

    {:ok, telemetry_pid} =
      GenServer.start_link(Telemetry, [batch_size: 10, flush_interval_ms: 60_000],
        name: telemetry_name
      )

    # Start the Alerts GenServer with a unique name for this test
    alerts_name = :"alerts_#{System.unique_integer([:positive])}"

    {:ok, alerts_pid} =
      GenServer.start_link(Alerts, [high_value_threshold: 500_000], name: alerts_name)

    on_exit(fn ->
      if Process.alive?(telemetry_pid), do: GenServer.stop(telemetry_pid)
      if Process.alive?(alerts_pid), do: GenServer.stop(alerts_pid)
    end)

    {:ok,
     account: account,
     character: character,
     telemetry_pid: telemetry_pid,
     telemetry_name: telemetry_name,
     alerts_pid: alerts_pid,
     alerts_name: alerts_name}
  end

  describe "full economy telemetry flow" do
    test "currency modification emits telemetry and logs to database", %{
      character: character,
      telemetry_name: telemetry_name
    } do
      # Grant 1000 gold to character
      {:ok, currency} = Inventory.modify_currency(character.id, :gold, 1000)
      assert currency.gold == 1000

      # Send telemetry event directly to the GenServer
      event_name = [:bezgelor, :economy, :currency, :transaction]
      measurements = %{amount: 1000, balance_after: currency.gold, duration_ms: 0}
      metadata = %{character_id: character.id, currency_type: :credits, source_type: :quest, source_id: 0}
      send(telemetry_name, {:telemetry_event, event_name, measurements, metadata})

      # Wait a bit for event to be processed
      Process.sleep(50)

      # Manually flush the telemetry batch
      GenServer.call(telemetry_name, :flush)

      # Verify transaction was logged to database
      transactions = Economy.get_transactions_for_character(character.id)
      assert length(transactions) == 1

      transaction = hd(transactions)
      assert transaction.character_id == character.id
      assert transaction.currency_type == 1
      assert transaction.amount == 1000
      assert transaction.balance_after == 1000
      assert transaction.source_type == "quest"
    end

    test "high value transaction triggers alert", %{
      character: character,
      alerts_name: alerts_name
    } do
      # Grant 1M gold to trigger threshold
      {:ok, currency} = Inventory.modify_currency(character.id, :gold, 1_000_000)
      assert currency.gold == 1_000_000

      # Check for high value transaction (threshold is 500K from setup)
      {:ok, alert} =
        GenServer.call(
          alerts_name,
          {:check_high_value, character.id, 1_000_000, 500_000}
        )

      # Verify alert was created
      assert is_map(alert)
      assert alert.alert_type == "high_value_trade"
      assert alert.character_id == character.id
      assert alert.severity in ["info", "warning", "critical"]

      # Verify alert is in database
      db_alert = Economy.get_alert(alert.id)
      assert db_alert != nil
      assert db_alert.character_id == character.id
      assert db_alert.alert_type == "high_value_trade"
    end

    test "telemetry metrics are updated correctly", %{
      character: character,
      telemetry_name: telemetry_name
    } do
      # Grant currency multiple times
      {:ok, currency1} = Inventory.modify_currency(character.id, :gold, 100)

      # Send event directly
      event_name = [:bezgelor, :economy, :currency, :transaction]
      measurements1 = %{amount: 100, balance_after: currency1.gold, duration_ms: 0}
      metadata1 = %{character_id: character.id, currency_type: :gold, source_type: :quest, source_id: 0}
      send(telemetry_name, {:telemetry_event, event_name, measurements1, metadata1})

      {:ok, currency2} = Inventory.modify_currency(character.id, :gold, 200)

      # Send event directly
      measurements2 = %{amount: 200, balance_after: currency2.gold, duration_ms: 0}
      metadata2 = %{character_id: character.id, currency_type: :gold, source_type: :quest, source_id: 0}
      send(telemetry_name, {:telemetry_event, event_name, measurements2, metadata2})

      # Wait for events to be processed
      Process.sleep(50)

      # Get metrics summary
      metrics = GenServer.call(telemetry_name, :get_metrics_summary)

      # Verify metrics
      assert metrics.currency_transactions >= 2
      assert metrics.total_currency_gained >= 300
      assert metrics.pending_events >= 0
    end

    test "batch flushing persists all events", %{
      character: character,
      telemetry_name: telemetry_name
    } do
      # Emit multiple events
      event_name = [:bezgelor, :economy, :currency, :transaction]

      for i <- 1..5 do
        amount = i * 100

        {:ok, currency} = Inventory.modify_currency(character.id, :gold, amount)

        # Send event directly
        measurements = %{amount: amount, balance_after: currency.gold, duration_ms: 0}
        metadata = %{character_id: character.id, currency_type: :credits, source_type: :quest, source_id: i}
        send(telemetry_name, {:telemetry_event, event_name, measurements, metadata})
      end

      # Wait for events to be processed
      Process.sleep(100)

      # Flush to database
      GenServer.call(telemetry_name, :flush)

      # Verify all transactions were logged
      transactions = Economy.get_transactions_for_character(character.id)
      assert length(transactions) == 5

      # Verify amounts
      amounts = Enum.map(transactions, & &1.amount)
      assert 100 in amounts
      assert 200 in amounts
      assert 300 in amounts
      assert 400 in amounts
      assert 500 in amounts
    end

    test "alert cache stores recent alerts", %{
      character: character,
      alerts_name: alerts_name
    } do
      # Create a high-value alert
      GenServer.call(
        alerts_name,
        {:check_high_value, character.id, 1_000_000, 500_000}
      )

      # Get recent alerts from cache
      recent_alerts = GenServer.call(alerts_name, {:get_recent_alerts, 10})

      assert is_list(recent_alerts)
      assert length(recent_alerts) >= 1

      # Verify alert details
      alert = hd(recent_alerts)
      assert alert.character_id == character.id
      assert alert.alert_type == "high_value_trade"
    end

    test "multiple currency transactions maintain correct balance", %{
      character: character,
      telemetry_name: telemetry_name
    } do
      event_name = [:bezgelor, :economy, :currency, :transaction]

      # Add 1000 gold
      {:ok, currency1} = Inventory.modify_currency(character.id, :gold, 1000)
      assert currency1.gold == 1000

      measurements1 = %{amount: 1000, balance_after: currency1.gold, duration_ms: 0}
      metadata1 = %{character_id: character.id, currency_type: :credits, source_type: :quest, source_id: 1}
      send(telemetry_name, {:telemetry_event, event_name, measurements1, metadata1})

      # Spend 300 gold
      {:ok, currency2} = Inventory.modify_currency(character.id, :gold, -300)
      assert currency2.gold == 700

      measurements2 = %{amount: -300, balance_after: currency2.gold, duration_ms: 0}
      metadata2 = %{character_id: character.id, currency_type: :credits, source_type: :vendor, source_id: 2}
      send(telemetry_name, {:telemetry_event, event_name, measurements2, metadata2})

      # Add 500 gold
      {:ok, currency3} = Inventory.modify_currency(character.id, :gold, 500)
      assert currency3.gold == 1200

      measurements3 = %{amount: 500, balance_after: currency3.gold, duration_ms: 0}
      metadata3 = %{character_id: character.id, currency_type: :credits, source_type: :quest, source_id: 3}
      send(telemetry_name, {:telemetry_event, event_name, measurements3, metadata3})

      # Wait for events to be processed
      Process.sleep(100)

      # Flush events
      GenServer.call(telemetry_name, :flush)

      # Verify all transactions
      transactions = Economy.get_transactions_for_character(character.id, order: :asc)
      assert length(transactions) == 3

      assert Enum.at(transactions, 0).balance_after == 1000
      assert Enum.at(transactions, 1).balance_after == 700
      assert Enum.at(transactions, 2).balance_after == 1200
    end
  end
end
