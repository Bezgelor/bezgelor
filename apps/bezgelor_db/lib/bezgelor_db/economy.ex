defmodule BezgelorDb.Economy do
  @moduledoc """
  Economy management context.

  ## Overview

  Provides functions for managing the game economy including:
  - Recording and querying currency transactions
  - Creating and managing economy alerts
  - Analyzing currency flow and patterns
  - Detecting suspicious economic activity

  ## Currency Transactions

  All currency changes are tracked through the CurrencyTransaction schema,
  providing an audit trail for debugging, exploit detection, and economic analysis.

  ## Economy Alerts

  Suspicious or notable economic activity triggers alerts that can be monitored
  and investigated by administrators.

  ## Usage

      # Record a transaction
      {:ok, transaction} = Economy.record_transaction(%{
        character_id: 123,
        currency_type: 1,
        amount: 100,
        balance_after: 1000,
        source_type: "quest",
        source_id: 456
      })

      # Get transactions for a character
      transactions = Economy.get_transactions_for_character(123, limit: 50)

      # Create an alert
      {:ok, alert} = Economy.create_alert(%{
        alert_type: "high_value_trade",
        severity: "warning",
        character_id: 123,
        description: "High value trade detected"
      })

      # Get unacknowledged critical alerts
      critical_alerts = Economy.get_critical_alerts()
  """

  import Ecto.Query
  alias BezgelorDb.Repo
  alias BezgelorDb.Schema.{CurrencyTransaction, EconomyAlert}

  # Maximum limit for list queries to prevent abuse
  @max_query_limit 1000
  @default_limit 100

  # ============================================================================
  # Currency Transactions
  # ============================================================================

  @doc """
  Record a currency transaction.

  ## Parameters

  - `attrs` - Map with transaction attributes:
    - `:character_id` - Character ID (required)
    - `:currency_type` - Currency type ID (required)
    - `:amount` - Amount changed (positive = gain, negative = loss) (required)
    - `:balance_after` - Balance after transaction (required)
    - `:source_type` - Source type (vendor, quest, trade, etc.) (required)
    - `:source_id` - Optional source entity ID
    - `:metadata` - Optional JSON metadata

  ## Returns

  - `{:ok, transaction}` on success
  - `{:error, changeset}` on validation failure

  ## Example

      {:ok, transaction} = Economy.record_transaction(%{
        character_id: 123,
        currency_type: 1,
        amount: 100,
        balance_after: 1000,
        source_type: "quest",
        source_id: 456,
        metadata: %{quest_name: "Epic Quest"}
      })
  """
  @spec record_transaction(map()) ::
          {:ok, CurrencyTransaction.t()} | {:error, Ecto.Changeset.t()}
  def record_transaction(attrs) do
    %CurrencyTransaction{}
    |> CurrencyTransaction.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Get transactions for a character.

  ## Options

  - `:currency_type` - Filter by currency type
  - `:source_type` - Filter by source type
  - `:since` - Only transactions after this DateTime
  - `:until` - Only transactions before this DateTime
  - `:limit` - Maximum results (default: 100, max: 1000)
  - `:offset` - Offset for pagination (default: 0)
  - `:order` - Sort order, :desc or :asc (default: :desc)

  ## Returns

  List of transactions ordered by inserted_at (newest first by default).

  ## Example

      # Get last 50 gold transactions
      transactions = Economy.get_transactions_for_character(123,
        currency_type: 1,
        limit: 50
      )

      # Get quest transactions from last week
      week_ago = DateTime.add(DateTime.utc_now(), -7, :day)
      transactions = Economy.get_transactions_for_character(123,
        source_type: "quest",
        since: week_ago
      )
  """
  @spec get_transactions_for_character(integer(), keyword()) :: [CurrencyTransaction.t()]
  def get_transactions_for_character(character_id, opts \\ []) do
    currency_type = Keyword.get(opts, :currency_type)
    source_type = Keyword.get(opts, :source_type)
    since = Keyword.get(opts, :since)
    until_time = Keyword.get(opts, :until)
    limit = opts |> Keyword.get(:limit, @default_limit) |> min(@max_query_limit)
    offset = opts |> Keyword.get(:offset, 0) |> max(0)
    order = Keyword.get(opts, :order, :desc)

    query =
      from(t in CurrencyTransaction,
        where: t.character_id == ^character_id
      )

    query =
      if currency_type do
        from(t in query, where: t.currency_type == ^currency_type)
      else
        query
      end

    query =
      if source_type do
        from(t in query, where: t.source_type == ^source_type)
      else
        query
      end

    query =
      if since do
        from(t in query, where: t.inserted_at >= ^since)
      else
        query
      end

    query =
      if until_time do
        from(t in query, where: t.inserted_at <= ^until_time)
      else
        query
      end

    query =
      case order do
        :asc ->
          from(t in query, order_by: [asc: t.inserted_at])

        _ ->
          from(t in query, order_by: [desc: t.inserted_at])
      end

    query =
      from(t in query,
        limit: ^limit,
        offset: ^offset
      )

    Repo.all(query)
  end

  @doc """
  Get recent transactions across all characters.

  ## Options

  - `:currency_type` - Filter by currency type
  - `:source_type` - Filter by source type
  - `:since` - Only transactions after this DateTime
  - `:limit` - Maximum results (default: 100, max: 1000)
  - `:offset` - Offset for pagination (default: 0)
  - `:preload_character` - Preload character association (default: false)

  ## Returns

  List of transactions ordered by inserted_at (newest first).

  ## Example

      # Get last 100 transactions
      transactions = Economy.get_recent_transactions(limit: 100)

      # Get high-value gold gains in the last hour
      hour_ago = DateTime.add(DateTime.utc_now(), -1, :hour)
      transactions = Economy.get_recent_transactions(
        currency_type: 1,
        since: hour_ago,
        preload_character: true
      )
  """
  @spec get_recent_transactions(keyword()) :: [CurrencyTransaction.t()]
  def get_recent_transactions(opts \\ []) do
    currency_type = Keyword.get(opts, :currency_type)
    source_type = Keyword.get(opts, :source_type)
    since = Keyword.get(opts, :since)
    limit = opts |> Keyword.get(:limit, @default_limit) |> min(@max_query_limit)
    offset = opts |> Keyword.get(:offset, 0) |> max(0)
    preload_character = Keyword.get(opts, :preload_character, false)

    query =
      from(t in CurrencyTransaction,
        order_by: [desc: t.inserted_at],
        limit: ^limit,
        offset: ^offset
      )

    query =
      if currency_type do
        from(t in query, where: t.currency_type == ^currency_type)
      else
        query
      end

    query =
      if source_type do
        from(t in query, where: t.source_type == ^source_type)
      else
        query
      end

    query =
      if since do
        from(t in query, where: t.inserted_at >= ^since)
      else
        query
      end

    query =
      if preload_character do
        from(t in query, preload: :character)
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Calculate balance delta for a character over a time period.

  Calculates the net change in currency for a character since a given time.

  ## Parameters

  - `character_id` - The character ID
  - `currency_type` - Currency type ID
  - `since` - Start DateTime

  ## Returns

  Integer representing net change (positive = net gain, negative = net loss).

  ## Example

      # Calculate gold gained in the last day
      day_ago = DateTime.add(DateTime.utc_now(), -1, :day)
      delta = Economy.calculate_balance_delta(123, 1, day_ago)
  """
  @spec calculate_balance_delta(integer(), integer(), DateTime.t()) :: integer()
  def calculate_balance_delta(character_id, currency_type, since) do
    query =
      from(t in CurrencyTransaction,
        where:
          t.character_id == ^character_id and
            t.currency_type == ^currency_type and
            t.inserted_at >= ^since,
        select: sum(t.amount)
      )

    Repo.one(query) || 0
  end

  # ============================================================================
  # Economy Alerts
  # ============================================================================

  @doc """
  Create an economy alert.

  ## Parameters

  - `attrs` - Map with alert attributes:
    - `:alert_type` - Type of alert (required)
    - `:severity` - Severity level (info, warning, critical) (required)
    - `:description` - Human-readable description (required)
    - `:character_id` - Optional character ID
    - `:data` - Optional JSON data

  ## Returns

  - `{:ok, alert}` on success
  - `{:error, changeset}` on validation failure

  ## Example

      {:ok, alert} = Economy.create_alert(%{
        alert_type: "high_value_trade",
        severity: "warning",
        character_id: 123,
        description: "Trade of 1000000 gold detected",
        data: %{amount: 1000000, other_character_id: 456}
      })
  """
  @spec create_alert(map()) :: {:ok, EconomyAlert.t()} | {:error, Ecto.Changeset.t()}
  def create_alert(attrs) do
    %EconomyAlert{}
    |> EconomyAlert.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  List economy alerts with filtering.

  ## Options

  - `:severity` - Filter by severity (info, warning, critical)
  - `:alert_type` - Filter by alert type
  - `:acknowledged` - Filter by acknowledged status (true/false)
  - `:character_id` - Filter by character ID
  - `:since` - Only alerts after this DateTime
  - `:limit` - Maximum results (default: 100, max: 1000)
  - `:offset` - Offset for pagination (default: 0)
  - `:preload_character` - Preload character association (default: false)

  ## Returns

  List of alerts ordered by inserted_at (newest first).

  ## Example

      # Get unacknowledged warnings
      alerts = Economy.list_alerts(
        severity: "warning",
        acknowledged: false
      )

      # Get all critical alerts from last week
      week_ago = DateTime.add(DateTime.utc_now(), -7, :day)
      alerts = Economy.list_alerts(
        severity: "critical",
        since: week_ago,
        preload_character: true
      )
  """
  @spec list_alerts(keyword()) :: [EconomyAlert.t()]
  def list_alerts(opts \\ []) do
    severity = Keyword.get(opts, :severity)
    alert_type = Keyword.get(opts, :alert_type)
    acknowledged = Keyword.get(opts, :acknowledged)
    character_id = Keyword.get(opts, :character_id)
    since = Keyword.get(opts, :since)
    limit = opts |> Keyword.get(:limit, @default_limit) |> min(@max_query_limit)
    offset = opts |> Keyword.get(:offset, 0) |> max(0)
    preload_character = Keyword.get(opts, :preload_character, false)

    query =
      from(a in EconomyAlert,
        order_by: [desc: a.inserted_at],
        limit: ^limit,
        offset: ^offset
      )

    query =
      if severity do
        from(a in query, where: a.severity == ^severity)
      else
        query
      end

    query =
      if alert_type do
        from(a in query, where: a.alert_type == ^alert_type)
      else
        query
      end

    query =
      if is_boolean(acknowledged) do
        from(a in query, where: a.acknowledged == ^acknowledged)
      else
        query
      end

    query =
      if character_id do
        from(a in query, where: a.character_id == ^character_id)
      else
        query
      end

    query =
      if since do
        from(a in query, where: a.inserted_at >= ^since)
      else
        query
      end

    query =
      if preload_character do
        from(a in query, preload: :character)
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Get a single economy alert by ID.

  ## Parameters

  - `id` - The alert ID

  ## Returns

  - `EconomyAlert` struct if found
  - `nil` if not found

  ## Example

      alert = Economy.get_alert(123)
  """
  @spec get_alert(integer()) :: EconomyAlert.t() | nil
  def get_alert(id) when is_integer(id) do
    Repo.get(EconomyAlert, id)
  end

  @doc """
  Acknowledge an economy alert.

  Marks an alert as acknowledged by a specific admin.

  ## Parameters

  - `id` - The alert ID
  - `admin_username` - Username of the admin acknowledging the alert

  ## Returns

  - `{:ok, alert}` on success
  - `{:error, :not_found}` if alert doesn't exist
  - `{:error, changeset}` on validation failure

  ## Example

      {:ok, alert} = Economy.acknowledge_alert(123, "admin@example.com")
  """
  @spec acknowledge_alert(integer(), String.t()) ::
          {:ok, EconomyAlert.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def acknowledge_alert(id, admin_username) when is_integer(id) and is_binary(admin_username) do
    case get_alert(id) do
      nil ->
        {:error, :not_found}

      alert ->
        alert
        |> EconomyAlert.acknowledge_changeset(admin_username)
        |> Repo.update()
    end
  end

  @doc """
  Get all unacknowledged alerts.

  ## Returns

  List of unacknowledged alerts ordered by severity (critical first) then by time (newest first).

  ## Example

      unacknowledged = Economy.get_unacknowledged_alerts()
  """
  @spec get_unacknowledged_alerts() :: [EconomyAlert.t()]
  def get_unacknowledged_alerts do
    from(a in EconomyAlert,
      where: a.acknowledged == false,
      order_by: [
        desc:
          fragment(
            "CASE ? WHEN 'critical' THEN 3 WHEN 'warning' THEN 2 WHEN 'info' THEN 1 END",
            a.severity
          ),
        desc: a.inserted_at
      ]
    )
    |> Repo.all()
  end

  @doc """
  Get unacknowledged critical alerts.

  Returns only critical severity alerts that haven't been acknowledged.

  ## Returns

  List of critical unacknowledged alerts ordered by time (newest first).

  ## Example

      critical = Economy.get_critical_alerts()
  """
  @spec get_critical_alerts() :: [EconomyAlert.t()]
  def get_critical_alerts do
    from(a in EconomyAlert,
      where: a.acknowledged == false and a.severity == "critical",
      order_by: [desc: a.inserted_at]
    )
    |> Repo.all()
  end

  # ============================================================================
  # Analytics Helpers
  # ============================================================================

  @doc """
  Get currency flow summary for a character.

  Calculates total inflow and outflow for a specific currency over a timeframe.

  ## Parameters

  - `character_id` - The character ID
  - `currency_type` - Currency type ID
  - `timeframe` - Time period in seconds (e.g., 86400 for 24 hours)

  ## Returns

  Map with:
  - `:inflow` - Total currency gained
  - `:outflow` - Total currency spent (positive number)
  - `:net` - Net change (inflow - outflow)
  - `:transaction_count` - Number of transactions

  ## Example

      # Get gold flow for last 24 hours
      summary = Economy.get_currency_flow_summary(123, 1, 86400)
      # => %{inflow: 5000, outflow: 3000, net: 2000, transaction_count: 42}
  """
  @spec get_currency_flow_summary(integer(), integer(), integer()) :: map()
  def get_currency_flow_summary(character_id, currency_type, timeframe)
      when is_integer(timeframe) and timeframe > 0 do
    since = DateTime.add(DateTime.utc_now(), -timeframe, :second)

    query =
      from(t in CurrencyTransaction,
        where:
          t.character_id == ^character_id and
            t.currency_type == ^currency_type and
            t.inserted_at >= ^since,
        select: %{
          inflow: sum(fragment("CASE WHEN ? > 0 THEN ? ELSE 0 END", t.amount, t.amount)),
          outflow: sum(fragment("CASE WHEN ? < 0 THEN ABS(?) ELSE 0 END", t.amount, t.amount)),
          count: count(t.id)
        }
      )

    result = Repo.one(query)

    inflow = result.inflow || 0
    outflow = result.outflow || 0

    %{
      inflow: inflow,
      outflow: outflow,
      net: inflow - outflow,
      transaction_count: result.count || 0
    }
  end

  @doc """
  Get top currency sources.

  Returns the top sources of currency generation for a specific currency type.

  ## Parameters

  - `currency_type` - Currency type ID
  - `limit` - Number of top sources to return (default: 10)

  ## Options

  - `:since` - Only consider transactions after this DateTime
  - `:gains_only` - Only count positive transactions (default: true)

  ## Returns

  List of maps with:
  - `:source_type` - Source type name
  - `:total_amount` - Total currency from this source
  - `:transaction_count` - Number of transactions

  Ordered by total_amount descending.

  ## Example

      # Get top 5 gold sources
      top_sources = Economy.get_top_currency_sources(1, 5)
      # => [
      #   %{source_type: "quest", total_amount: 50000, transaction_count: 123},
      #   %{source_type: "loot", total_amount: 30000, transaction_count: 456},
      #   ...
      # ]
  """
  @spec get_top_currency_sources(integer(), integer(), keyword()) :: [map()]
  def get_top_currency_sources(currency_type, limit \\ 10, opts \\ []) do
    since = Keyword.get(opts, :since)
    gains_only = Keyword.get(opts, :gains_only, true)
    limit = min(limit, 100)

    query =
      from(t in CurrencyTransaction,
        where: t.currency_type == ^currency_type,
        group_by: t.source_type,
        select: %{
          source_type: t.source_type,
          total_amount: sum(t.amount),
          transaction_count: count(t.id)
        },
        order_by: [desc: sum(t.amount)],
        limit: ^limit
      )

    query =
      if gains_only do
        from(t in query, where: t.amount > 0)
      else
        query
      end

    query =
      if since do
        from(t in query, where: t.inserted_at >= ^since)
      else
        query
      end

    Repo.all(query)
  end
end
