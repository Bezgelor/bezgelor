defmodule BezgelorPortalWeb.Admin.LogsLive do
  @moduledoc """
  Admin LiveView for viewing server logs.

  Features:
  - Real-time log streaming
  - Filter by log level
  - Search logs
  - Auto-scroll to latest
  """
  use BezgelorPortalWeb, :live_view

  alias BezgelorPortal.LogBuffer

  @max_logs 500
  @default_level :info

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to new log events
      LogBuffer.subscribe()
    end

    # Load existing logs from buffer
    existing_logs = LogBuffer.get_logs(@max_logs)

    {:ok,
     assign(socket,
       page_title: "Server Logs",
       logs: existing_logs,
       filter_level: @default_level,
       search_query: "",
       auto_scroll: true,
       paused: false
     ),
     layout: {BezgelorPortalWeb.Layouts, :admin}}
  end

  @impl true
  def handle_info({:new_log, log_entry}, socket) do
    if socket.assigns.paused do
      {:noreply, socket}
    else
      # Filter by level before adding
      if should_show?(log_entry.level, socket.assigns.filter_level) do
        logs = [log_entry | socket.assigns.logs] |> Enum.take(@max_logs)
        {:noreply, assign(socket, logs: logs)}
      else
        {:noreply, socket}
      end
    end
  end

  defp should_show?(level, min_level) do
    level_value(level) >= level_value(min_level)
  end

  defp level_value(:debug), do: 0
  defp level_value(:info), do: 1
  defp level_value(:notice), do: 1
  defp level_value(:warning), do: 2
  defp level_value(:warn), do: 2
  defp level_value(:error), do: 3
  defp level_value(_), do: 0

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-bold">Server Logs</h1>
          <p class="text-base-content/70">Real-time server log viewer</p>
        </div>
        <span class={"badge #{if @paused, do: "badge-warning", else: "badge-success"}"}>
          {if @paused, do: "Paused", else: "Live"}
        </span>
      </div>

      <!-- Controls -->
      <div class="card bg-base-100 shadow">
        <div class="card-body py-3">
          <div class="flex flex-wrap gap-4 items-end">
            <!-- Level Filter -->
            <div class="flex items-center gap-2">
              <span class="label-text text-sm whitespace-nowrap">Log Level</span>
              <select
                class="select select-bordered select-sm"
                phx-change="set_level"
                name="level"
              >
                <option value="debug" selected={@filter_level == :debug}>Debug</option>
                <option value="info" selected={@filter_level == :info}>Info</option>
                <option value="warning" selected={@filter_level == :warning}>Warning</option>
                <option value="error" selected={@filter_level == :error}>Error</option>
              </select>
            </div>

            <!-- Search -->
            <div class="form-control flex-1 min-w-[200px]">
              <label class="label py-1">
                <span class="label-text text-xs">Search</span>
              </label>
              <input
                type="text"
                class="input input-bordered input-sm"
                placeholder="Filter logs..."
                value={@search_query}
                phx-change="search"
                phx-debounce="300"
                name="query"
              />
            </div>

            <!-- Actions -->
            <div class="flex gap-2 items-center">
              <button
                type="button"
                class={"btn btn-sm #{if @paused, do: "btn-success", else: "btn-warning"}"}
                phx-click="toggle_pause"
              >
                <%= if @paused do %>
                  <.icon name="hero-play" class="size-4" />
                  Resume
                <% else %>
                  <.icon name="hero-pause" class="size-4" />
                  Pause
                <% end %>
              </button>
              <button
                type="button"
                class="btn btn-sm btn-ghost"
                phx-click="clear_logs"
              >
                <.icon name="hero-trash" class="size-4" />
                Clear
              </button>
              <label class="label cursor-pointer gap-2">
                <span class="label-text text-sm">Auto-scroll</span>
                <input
                  type="checkbox"
                  class="toggle toggle-sm"
                  checked={@auto_scroll}
                  phx-click="toggle_auto_scroll"
                />
              </label>
            </div>
          </div>
        </div>
      </div>

      <!-- Log Output -->
      <div
        id="log-container"
        class="card bg-base-300 shadow"
        phx-hook="AutoScroll"
        data-auto-scroll={to_string(@auto_scroll)}
      >
        <div class="h-[600px] overflow-y-auto font-mono text-sm p-4">
          <%= if Enum.empty?(filtered_logs(@logs, @search_query)) do %>
            <p class="text-base-content/50 text-center py-8">
              No log entries yet. Logs will appear here in real-time.
            </p>
          <% else %>
            <div class="space-y-1">
              <div
                :for={log <- filtered_logs(@logs, @search_query) |> Enum.reverse()}
                class={"flex gap-2 py-0.5 #{log_row_class(log.level)}"}
              >
                <span class="text-base-content/50 shrink-0">{format_time(log.timestamp)}</span>
                <span class={"shrink-0 #{level_class(log.level)}"}>[{format_level(log.level)}]</span>
                <span class="text-base-content/70 shrink-0">{log.module}</span>
                <span class="break-all">{log.message}</span>
              </div>
            </div>
          <% end %>
        </div>
      </div>

      <!-- Legend -->
      <div class="flex gap-4 text-sm">
        <span class="flex items-center gap-1">
          <span class="w-3 h-3 rounded bg-base-content/30"></span>
          Debug
        </span>
        <span class="flex items-center gap-1">
          <span class="w-3 h-3 rounded bg-info"></span>
          Info
        </span>
        <span class="flex items-center gap-1">
          <span class="w-3 h-3 rounded bg-warning"></span>
          Warning
        </span>
        <span class="flex items-center gap-1">
          <span class="w-3 h-3 rounded bg-error"></span>
          Error
        </span>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("set_level", %{"level" => level}, socket) do
    level_atom = String.to_existing_atom(level)

    # Reload logs filtered by new level
    all_logs = LogBuffer.get_logs(@max_logs)
    filtered = Enum.filter(all_logs, fn log -> should_show?(log.level, level_atom) end)

    {:noreply, assign(socket, filter_level: level_atom, logs: filtered)}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    {:noreply, assign(socket, search_query: query)}
  end

  @impl true
  def handle_event("toggle_pause", _, socket) do
    {:noreply, assign(socket, paused: !socket.assigns.paused)}
  end

  @impl true
  def handle_event("toggle_auto_scroll", _, socket) do
    {:noreply, assign(socket, auto_scroll: !socket.assigns.auto_scroll)}
  end

  @impl true
  def handle_event("clear_logs", _, socket) do
    LogBuffer.clear()
    {:noreply, assign(socket, logs: [])}
  end

  defp filtered_logs(logs, "") do
    logs
  end

  defp filtered_logs(logs, query) do
    query_down = String.downcase(query)

    Enum.filter(logs, fn log ->
      String.contains?(String.downcase(log.message), query_down) ||
        String.contains?(String.downcase(to_string(log.module)), query_down)
    end)
  end

  defp format_time(timestamp) do
    Calendar.strftime(timestamp, "%H:%M:%S.%f")
    |> String.slice(0..11)
  end

  defp format_level(:debug), do: "DBG"
  defp format_level(:info), do: "INF"
  defp format_level(:warning), do: "WRN"
  defp format_level(:error), do: "ERR"
  defp format_level(level), do: level |> to_string() |> String.upcase() |> String.slice(0..2)

  defp level_class(:debug), do: "text-base-content/50"
  defp level_class(:info), do: "text-info"
  defp level_class(:warning), do: "text-warning"
  defp level_class(:error), do: "text-error"
  defp level_class(_), do: "text-base-content"

  defp log_row_class(:error), do: "bg-error/10"
  defp log_row_class(:warning), do: "bg-warning/5"
  defp log_row_class(_), do: ""
end
