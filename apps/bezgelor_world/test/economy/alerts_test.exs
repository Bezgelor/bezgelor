defmodule BezgelorWorld.Economy.AlertsTest do
  @moduledoc """
  Comprehensive unit tests for the Economy.Alerts GenServer.

  Tests cover:
  - Initialization with default and custom configurations
  - High-value transaction threshold detection
  - Rapid transaction pattern detection
  - Cache management and trimming
  - Alert severity determination
  - Database integration

  All tests use isolated GenServer instances with unique names to avoid conflicts.
  """

  use ExUnit.Case, async: false

  alias BezgelorDb.{Accounts, Characters, Economy, Inventory, Repo}
  alias BezgelorWorld.Economy.Alerts

  @moduletag :database

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
    email = "alerts_test_#{System.unique_integer([:positive])}@test.com"
    {:ok, account} = Accounts.create_account(email, "password123")

    # Use shorter name with unique suffix that fits in 24 char limit
    unique_id = :erlang.unique_integer([:positive]) |> rem(99999)

    {:ok, character} =
      Characters.create_character(account.id, %{
        name: "Alert#{unique_id}",
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

    # Create unique GenServer name for this test
    genserver_name = :"alerts_test_#{System.unique_integer([:positive])}"

    {:ok, account: account, character: character, genserver_name: genserver_name}
  end

  describe "initialization" do
    test "starts with default configuration", %{genserver_name: name} do
      {:ok, pid} = GenServer.start_link(Alerts, [], name: name)

      # Verify server is running
      assert Process.alive?(pid)
      assert Process.whereis(name) == pid

      # Get state indirectly by checking get_recent_alerts works
      alerts = GenServer.call(name, {:get_recent_alerts, 10})
      assert is_list(alerts)

      GenServer.stop(pid)
    end

    test "starts with configured thresholds", %{genserver_name: name} do
      opts = [
        cache_size: 50,
        high_value_threshold: 500_000,
        rapid_transaction_count: 30,
        rapid_transaction_timeframe: 600
      ]

      {:ok, pid} = GenServer.start_link(Alerts, opts, name: name)
      assert Process.alive?(pid)

      # Verify configuration by testing threshold behavior
      # With threshold 500_000, amount of 400_000 should be below
      result = GenServer.call(name, {:check_high_value, 999, 400_000, nil})
      assert result == {:ok, :below_threshold}

      GenServer.stop(pid)
    end

    test "loads cache from database on init", %{character: character, genserver_name: name} do
      # Create some alerts in the database first
      {:ok, alert1} =
        Economy.create_alert(%{
          alert_type: "high_value_trade",
          severity: "warning",
          character_id: character.id,
          description: "Test alert 1"
        })

      {:ok, alert2} =
        Economy.create_alert(%{
          alert_type: "rapid_transactions",
          severity: "info",
          character_id: character.id,
          description: "Test alert 2"
        })

      # Start GenServer - it should load these from database
      {:ok, pid} = GenServer.start_link(Alerts, [cache_size: 10], name: name)

      # Get recent alerts from cache
      cached_alerts = GenServer.call(name, {:get_recent_alerts, 10})

      # Should include the alerts we created
      alert_ids = Enum.map(cached_alerts, & &1.id)
      assert alert1.id in alert_ids
      assert alert2.id in alert_ids

      GenServer.stop(pid)
    end
  end

  describe "high-value threshold detection" do
    setup %{genserver_name: name} do
      {:ok, pid} = GenServer.start_link(Alerts, [high_value_threshold: 1_000_000], name: name)
      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
      {:ok, pid: pid}
    end

    test "returns :below_threshold when amount < threshold", %{
      character: character,
      genserver_name: name
    } do
      result = GenServer.call(name, {:check_high_value, character.id, 500_000, 1_000_000})
      assert result == {:ok, :below_threshold}
    end

    test "creates alert when amount >= threshold", %{
      character: character,
      genserver_name: name
    } do
      {:ok, alert} =
        GenServer.call(name, {:check_high_value, character.id, 1_000_000, 1_000_000})

      assert is_map(alert)
      assert alert.alert_type == "high_value_trade"
      assert alert.character_id == character.id
      assert alert.severity in ["info", "warning", "critical"]

      # Verify it was saved to database
      db_alert = Economy.get_alert(alert.id)
      assert db_alert != nil
      assert db_alert.character_id == character.id
    end

    test "uses config threshold when none provided", %{
      character: character,
      genserver_name: name
    } do
      # Config has threshold of 1_000_000
      # Amount of 500_000 should be below
      result = GenServer.call(name, {:check_high_value, character.id, 500_000, nil})
      assert result == {:ok, :below_threshold}

      # Amount of 1_000_000 should trigger
      {:ok, alert} = GenServer.call(name, {:check_high_value, character.id, 1_000_000, nil})
      assert is_map(alert)
    end

    test "severity determination: info for 1-3x threshold", %{
      character: character,
      genserver_name: name
    } do
      # Exactly 1x threshold
      {:ok, alert1} =
        GenServer.call(name, {:check_high_value, character.id, 1_000_000, 1_000_000})

      assert alert1.severity == "info"

      # 2x threshold
      {:ok, alert2} =
        GenServer.call(name, {:check_high_value, character.id, 2_000_000, 1_000_000})

      assert alert2.severity == "info"

      # Just under 3x threshold
      {:ok, alert3} =
        GenServer.call(name, {:check_high_value, character.id, 2_999_999, 1_000_000})

      assert alert3.severity == "info"
    end

    test "severity determination: warning for 3-10x threshold", %{
      character: character,
      genserver_name: name
    } do
      # Exactly 3x threshold
      {:ok, alert1} =
        GenServer.call(name, {:check_high_value, character.id, 3_000_000, 1_000_000})

      assert alert1.severity == "warning"

      # 5x threshold
      {:ok, alert2} =
        GenServer.call(name, {:check_high_value, character.id, 5_000_000, 1_000_000})

      assert alert2.severity == "warning"

      # Just under 10x threshold
      {:ok, alert3} =
        GenServer.call(name, {:check_high_value, character.id, 9_999_999, 1_000_000})

      assert alert3.severity == "warning"
    end

    test "severity determination: critical for 10x+ threshold", %{
      character: character,
      genserver_name: name
    } do
      # Exactly 10x threshold
      {:ok, alert1} =
        GenServer.call(name, {:check_high_value, character.id, 10_000_000, 1_000_000})

      assert alert1.severity == "critical"

      # 20x threshold
      {:ok, alert2} =
        GenServer.call(name, {:check_high_value, character.id, 20_000_000, 1_000_000})

      assert alert2.severity == "critical"

      # 100x threshold
      {:ok, alert3} =
        GenServer.call(name, {:check_high_value, character.id, 100_000_000, 1_000_000})

      assert alert3.severity == "critical"
    end

    test "handles negative amounts by using absolute value", %{
      character: character,
      genserver_name: name
    } do
      # Negative amount of -1_000_000 should trigger (abs value >= threshold)
      {:ok, alert} =
        GenServer.call(name, {:check_high_value, character.id, -1_000_000, 1_000_000})

      assert is_map(alert)
      assert alert.alert_type == "high_value_trade"
      assert alert.data.amount == 1_000_000
    end
  end

  describe "rapid transaction detection" do
    setup %{genserver_name: name} do
      {:ok, pid} =
        GenServer.start_link(Alerts, [rapid_transaction_count: 20, rapid_transaction_timeframe: 300],
          name: name
        )

      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
      {:ok, pid: pid}
    end

    test "returns :below_threshold when count < threshold", %{
      character: character,
      genserver_name: name
    } do
      # Character has no transactions, so count is 0
      result = GenServer.call(name, {:check_rapid_transactions, character.id, 20, 300})
      assert result == {:ok, :below_threshold}
    end

    test "creates alert when count >= threshold", %{
      character: character,
      genserver_name: name
    } do
      # Create 25 transactions in the last 5 minutes
      for i <- 1..25 do
        {:ok, _} =
          Economy.record_transaction(%{
            character_id: character.id,
            currency_type: 1,
            amount: 100,
            balance_after: i * 100,
            source_type: "quest",
            source_id: i
          })
      end

      # Check for rapid transactions (threshold is 20)
      {:ok, alert} = GenServer.call(name, {:check_rapid_transactions, character.id, 20, 300})

      assert is_map(alert)
      assert alert.alert_type == "rapid_transactions"
      assert alert.character_id == character.id
      assert alert.severity in ["info", "warning", "critical"]
      assert alert.data.transaction_count == 25
      assert alert.data.timeframe_seconds == 300

      # Verify it was saved to database
      db_alert = Economy.get_alert(alert.id)
      assert db_alert != nil
      assert db_alert.character_id == character.id
    end

    test "uses config timeframe when none provided", %{
      character: character,
      genserver_name: name
    } do
      # Create 25 transactions
      for i <- 1..25 do
        {:ok, _} =
          Economy.record_transaction(%{
            character_id: character.id,
            currency_type: 1,
            amount: 100,
            balance_after: i * 100,
            source_type: "quest",
            source_id: i
          })
      end

      # Use nil timeframe, should use config default of 300
      {:ok, alert} = GenServer.call(name, {:check_rapid_transactions, character.id, 20, nil})

      assert is_map(alert)
      assert alert.data.timeframe_seconds == 300
    end

    test "severity determination: info for < 50 transactions", %{
      character: character,
      genserver_name: name
    } do
      # Create 25 transactions
      for i <- 1..25 do
        {:ok, _} =
          Economy.record_transaction(%{
            character_id: character.id,
            currency_type: 1,
            amount: 100,
            balance_after: i * 100,
            source_type: "quest",
            source_id: i
          })
      end

      {:ok, alert} = GenServer.call(name, {:check_rapid_transactions, character.id, 20, 300})
      assert alert.severity == "info"
    end

    test "severity determination: warning for 50-99 transactions", %{genserver_name: name} do
      # Create a different character for this test to avoid transaction contamination
      email = "rapid_warning_#{System.unique_integer([:positive])}@test.com"
      {:ok, account} = Accounts.create_account(email, "password123")

      # Use shorter name with unique suffix that fits in 24 char limit
      unique_id = :erlang.unique_integer([:positive]) |> rem(99999)

      {:ok, character} =
        Characters.create_character(account.id, %{
          name: "Rapid#{unique_id}",
          sex: 0,
          race: 1,
          class: 0,
          faction_id: 167,
          realm_id: 1,
          world_id: 1,
          world_zone_id: 1
        })

      # Create 75 transactions
      for i <- 1..75 do
        {:ok, _} =
          Economy.record_transaction(%{
            character_id: character.id,
            currency_type: 1,
            amount: 100,
            balance_after: i * 100,
            source_type: "quest",
            source_id: i
          })
      end

      {:ok, alert} = GenServer.call(name, {:check_rapid_transactions, character.id, 20, 300})
      assert alert.severity == "warning"
    end

    test "severity determination: critical for 100+ transactions", %{genserver_name: name} do
      # Create a different character for this test to avoid transaction contamination
      email = "rapid_critical_#{System.unique_integer([:positive])}@test.com"
      {:ok, account} = Accounts.create_account(email, "password123")

      # Use shorter name with unique suffix that fits in 24 char limit
      unique_id = :erlang.unique_integer([:positive]) |> rem(99999)

      {:ok, character} =
        Characters.create_character(account.id, %{
          name: "Critical#{unique_id}",
          sex: 0,
          race: 1,
          class: 0,
          faction_id: 167,
          realm_id: 1,
          world_id: 1,
          world_zone_id: 1
        })

      # Create 150 transactions
      for i <- 1..150 do
        {:ok, _} =
          Economy.record_transaction(%{
            character_id: character.id,
            currency_type: 1,
            amount: 100,
            balance_after: i * 100,
            source_type: "quest",
            source_id: i
          })
      end

      {:ok, alert} = GenServer.call(name, {:check_rapid_transactions, character.id, 20, 300})
      assert alert.severity == "critical"
    end

    test "only counts transactions within timeframe", %{genserver_name: name} do
      # Create a different character for this test
      email = "timeframe_#{System.unique_integer([:positive])}@test.com"
      {:ok, account} = Accounts.create_account(email, "password123")

      # Use shorter name with unique suffix that fits in 24 char limit
      unique_id = :erlang.unique_integer([:positive]) |> rem(99999)

      {:ok, character} =
        Characters.create_character(account.id, %{
          name: "Time#{unique_id}",
          sex: 0,
          race: 1,
          class: 0,
          faction_id: 167,
          realm_id: 1,
          world_id: 1,
          world_zone_id: 1
        })

      # Create 10 transactions (below threshold of 20)
      for i <- 1..10 do
        {:ok, _} =
          Economy.record_transaction(%{
            character_id: character.id,
            currency_type: 1,
            amount: 100,
            balance_after: i * 100,
            source_type: "quest",
            source_id: i
          })
      end

      # Should be below threshold
      result = GenServer.call(name, {:check_rapid_transactions, character.id, 20, 300})
      assert result == {:ok, :below_threshold}
    end
  end

  describe "cache management" do
    test "alerts are added to cache", %{character: character, genserver_name: name} do
      {:ok, pid} = GenServer.start_link(Alerts, [cache_size: 100], name: name)

      # Create an alert
      {:ok, alert} =
        GenServer.call(name, {:check_high_value, character.id, 1_000_000, 500_000})

      # Get recent alerts from cache
      cached_alerts = GenServer.call(name, {:get_recent_alerts, 10})

      # Should include the alert we just created
      assert Enum.any?(cached_alerts, fn a -> a.id == alert.id end)

      GenServer.stop(pid)
    end

    test "cache is trimmed to configured size", %{genserver_name: name} do
      # Start with small cache size
      {:ok, pid} = GenServer.start_link(Alerts, [cache_size: 5], name: name)

      # Create 10 alerts (more than cache size)
      for i <- 1..10 do
        email = "cache_trim_#{i}_#{System.unique_integer([:positive])}@test.com"
        {:ok, account} = Accounts.create_account(email, "password123")

        # Use shorter name with unique suffix that fits in 24 char limit
        unique_id = :erlang.unique_integer([:positive]) |> rem(99999)

        {:ok, character} =
          Characters.create_character(account.id, %{
            name: "Trim#{unique_id}",
            sex: 0,
            race: 1,
            class: 0,
            faction_id: 167,
            realm_id: 1,
            world_id: 1,
            world_zone_id: 1
          })

        GenServer.call(name, {:check_high_value, character.id, 1_000_000, 500_000})
      end

      # Get all cached alerts
      cached_alerts = GenServer.call(name, {:get_recent_alerts, 100})

      # Should only have 5 alerts (cache size limit)
      assert length(cached_alerts) <= 5

      GenServer.stop(pid)
    end

    test "get_recent_alerts respects limit", %{character: character, genserver_name: name} do
      {:ok, pid} = GenServer.start_link(Alerts, [cache_size: 100], name: name)

      # Create 10 alerts
      for _i <- 1..10 do
        GenServer.call(name, {:check_high_value, character.id, 1_000_000, 500_000})
      end

      # Request only 3 alerts
      alerts = GenServer.call(name, {:get_recent_alerts, 3})

      assert length(alerts) == 3

      GenServer.stop(pid)
    end

    test "clear_cache reloads from database", %{character: character, genserver_name: name} do
      # Create an alert in database before starting GenServer
      {:ok, db_alert} =
        Economy.create_alert(%{
          alert_type: "high_value_trade",
          severity: "warning",
          character_id: character.id,
          description: "Pre-existing alert"
        })

      {:ok, pid} = GenServer.start_link(Alerts, [cache_size: 100], name: name)

      # Cache should have the pre-existing alert
      cached_before = GenServer.call(name, {:get_recent_alerts, 10})
      assert Enum.any?(cached_before, fn a -> a.id == db_alert.id end)

      # Create new alert through GenServer
      {:ok, new_alert} =
        GenServer.call(name, {:check_high_value, character.id, 2_000_000, 500_000})

      # Clear cache
      :ok = GenServer.call(name, :clear_cache)

      # Get alerts again
      cached_after = GenServer.call(name, {:get_recent_alerts, 10})

      # Should still have both alerts (reloaded from database)
      assert Enum.any?(cached_after, fn a -> a.id == db_alert.id end)
      assert Enum.any?(cached_after, fn a -> a.id == new_alert.id end)

      GenServer.stop(pid)
    end
  end

  describe "configuration" do
    test "custom cache_size is respected", %{character: character, genserver_name: name} do
      {:ok, pid} = GenServer.start_link(Alerts, [cache_size: 3], name: name)

      # Create 5 alerts
      for _i <- 1..5 do
        GenServer.call(name, {:check_high_value, character.id, 1_000_000, 500_000})
      end

      # Request more than cache size
      alerts = GenServer.call(name, {:get_recent_alerts, 100})

      # Should only have 3 (cache_size limit)
      assert length(alerts) <= 3

      GenServer.stop(pid)
    end

    test "custom high_value_threshold is respected", %{character: character, genserver_name: name} do
      {:ok, pid} = GenServer.start_link(Alerts, [high_value_threshold: 2_000_000], name: name)

      # Amount of 1_500_000 should be below custom threshold
      result = GenServer.call(name, {:check_high_value, character.id, 1_500_000, nil})
      assert result == {:ok, :below_threshold}

      # Amount of 2_000_000 should trigger
      {:ok, alert} = GenServer.call(name, {:check_high_value, character.id, 2_000_000, nil})
      assert is_map(alert)

      GenServer.stop(pid)
    end

    test "custom rapid_transaction_count is respected", %{genserver_name: name} do
      {:ok, pid} = GenServer.start_link(Alerts, [rapid_transaction_count: 50], name: name)

      # Create a character with 40 transactions
      email = "custom_count_#{System.unique_integer([:positive])}@test.com"
      {:ok, account} = Accounts.create_account(email, "password123")

      # Use shorter name with unique suffix that fits in 24 char limit
      unique_id = :erlang.unique_integer([:positive]) |> rem(99999)

      {:ok, character} =
        Characters.create_character(account.id, %{
          name: "Count#{unique_id}",
          sex: 0,
          race: 1,
          class: 0,
          faction_id: 167,
          realm_id: 1,
          world_id: 1,
          world_zone_id: 1
        })

      for i <- 1..40 do
        {:ok, _} =
          Economy.record_transaction(%{
            character_id: character.id,
            currency_type: 1,
            amount: 100,
            balance_after: i * 100,
            source_type: "quest",
            source_id: i
          })
      end

      # Should be below custom threshold of 50
      result = GenServer.call(name, {:check_rapid_transactions, character.id, nil, 300})
      assert result == {:ok, :below_threshold}

      GenServer.stop(pid)
    end

    test "custom rapid_transaction_timeframe is respected", %{genserver_name: name} do
      {:ok, pid} = GenServer.start_link(Alerts, [rapid_transaction_timeframe: 600], name: name)

      # Create a character with transactions
      email = "custom_timeframe_#{System.unique_integer([:positive])}@test.com"
      {:ok, account} = Accounts.create_account(email, "password123")

      # Use shorter name with unique suffix that fits in 24 char limit
      unique_id = :erlang.unique_integer([:positive]) |> rem(99999)

      {:ok, character} =
        Characters.create_character(account.id, %{
          name: "Frame#{unique_id}",
          sex: 0,
          race: 1,
          class: 0,
          faction_id: 167,
          realm_id: 1,
          world_id: 1,
          world_zone_id: 1
        })

      for i <- 1..30 do
        {:ok, _} =
          Economy.record_transaction(%{
            character_id: character.id,
            currency_type: 1,
            amount: 100,
            balance_after: i * 100,
            source_type: "quest",
            source_id: i
          })
      end

      # Check with nil timeframe, should use config default of 600
      {:ok, alert} = GenServer.call(name, {:check_rapid_transactions, character.id, 20, nil})
      assert alert.data.timeframe_seconds == 600

      GenServer.stop(pid)
    end
  end
end
