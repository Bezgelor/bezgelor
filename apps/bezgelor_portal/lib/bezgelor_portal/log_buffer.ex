defmodule BezgelorPortal.LogBuffer do
  @moduledoc """
  A ring buffer for storing recent log entries.

  Captures logs from the Erlang logger and stores them in memory
  for viewing in the admin panel.
  """
  use GenServer
  require Logger

  @max_entries 1000
  @table :log_buffer

  # Client API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "Get recent log entries"
  def get_logs(limit \\ 500) do
    case :ets.info(@table) do
      :undefined -> []
      _ ->
        @table
        |> :ets.tab2list()
        |> Enum.sort_by(fn {ts, _} -> ts end, {:desc, DateTime})
        |> Enum.take(limit)
        |> Enum.map(fn {_ts, entry} -> entry end)
    end
  end

  @doc "Add a log entry"
  def add_log(entry) do
    GenServer.cast(__MODULE__, {:add_log, entry})
  end

  @doc "Clear all logs"
  def clear do
    GenServer.cast(__MODULE__, :clear)
  end

  @doc "Subscribe to new log entries"
  def subscribe do
    Phoenix.PubSub.subscribe(BezgelorPortal.PubSub, "log_buffer")
  end

  @doc "Unsubscribe from log entries"
  def unsubscribe do
    Phoenix.PubSub.unsubscribe(BezgelorPortal.PubSub, "log_buffer")
  end

  # Server callbacks

  @impl true
  def init(_) do
    # Create ETS table for log storage
    :ets.new(@table, [:named_table, :ordered_set, :public, read_concurrency: true])

    # Add logger handler to capture all application logs
    :logger.add_handler(:log_buffer_handler, __MODULE__.Handler, %{})

    Logger.info("Log buffer started - capturing server logs for admin viewer")

    {:ok, %{counter: 0}}
  end

  @impl true
  def handle_cast({:add_log, entry}, state) do
    timestamp = DateTime.utc_now()
    counter = state.counter + 1

    # Use {timestamp, counter} as key for ordering
    :ets.insert(@table, {{timestamp, counter}, entry})

    # Prune old entries if over limit
    prune_if_needed()

    # Broadcast to subscribers
    Phoenix.PubSub.broadcast(BezgelorPortal.PubSub, "log_buffer", {:new_log, entry})

    {:noreply, %{state | counter: counter}}
  end

  @impl true
  def handle_cast(:clear, state) do
    :ets.delete_all_objects(@table)
    {:noreply, state}
  end

  defp prune_if_needed do
    size = :ets.info(@table, :size)
    if size > @max_entries do
      # Delete oldest entries
      to_delete = size - @max_entries
      @table
      |> :ets.tab2list()
      |> Enum.sort_by(fn {ts, _} -> ts end, {:asc, DateTime})
      |> Enum.take(to_delete)
      |> Enum.each(fn {key, _} -> :ets.delete(@table, key) end)
    end
  end

  # Logger handler
  defmodule Handler do
    @moduledoc false

    def log(%{level: level, meta: meta, msg: msg}, _config) do
      message = format_message(msg)
      module = format_module(Map.get(meta, :mfa))

      entry = %{
        level: level,
        message: message,
        module: module,
        timestamp: DateTime.utc_now()
      }

      BezgelorPortal.LogBuffer.add_log(entry)
    end

    defp format_message({:string, msg}), do: IO.iodata_to_binary(msg)
    defp format_message({:report, report}), do: inspect(report, limit: 200)
    defp format_message(msg) when is_binary(msg), do: msg
    defp format_message(msg), do: inspect(msg, limit: 200)

    defp format_module(nil), do: "system"
    defp format_module({module, _fun, _arity}) when is_atom(module) do
      module
      |> Module.split()
      |> Enum.take(-2)
      |> Enum.join(".")
    end
    defp format_module(_), do: "system"
  end
end
