defmodule BezgelorPortalWeb.Admin.MetricsDashboardLive do
  @moduledoc """
  Admin LiveView for metrics dashboard with Chart.js visualization.

  Features:
  - 4 tabs: Server, Auth, Gameplay, Combat
  - Time range selection (1h, 6h, 24h, 7d, 30d + custom)
  - Auto-refresh every 10 seconds using Process.send_after
  - Push chart data to MetricsChart hook via push_event
  - Safe tab mapping to prevent atom exhaustion
  - Only loads data for active tab
  """

  use BezgelorPortalWeb, :live_view

  alias BezgelorDb.Metrics

  # Module attributes
  @refresh_interval 10_000
  @time_ranges [{"1h", 1}, {"6h", 6}, {"24h", 24}, {"7d", 24 * 7}, {"30d", 24 * 30}]
  @tab_mapping %{"server" => :server, "auth" => :auth, "gameplay" => :gameplay, "combat" => :combat}
  @max_custom_range_days 90

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      schedule_refresh()
    end

    {:ok,
     socket
     |> assign(
       page_title: "Metrics Dashboard",
       active_tab: :server,
       time_range: "24h",
       time_range_hours: 24,
       custom_from: nil,
       custom_to: nil,
       last_refresh: DateTime.utc_now(),
       time_ranges: @time_ranges,
       tab_mapping: @tab_mapping
     )
     |> load_tab_data(), layout: {BezgelorPortalWeb.Layouts, :admin}}
  end

  @impl true
  def handle_event("change_tab", %{"tab" => tab_string}, socket) do
    # Safe tab mapping to prevent atom exhaustion attacks
    case Map.fetch(@tab_mapping, tab_string) do
      {:ok, tab} ->
        {:noreply,
         socket
         |> assign(active_tab: tab)
         |> load_tab_data()
         |> push_chart_updates()}

      :error ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("change_time_range", %{"range" => range}, socket) do
    case Enum.find(@time_ranges, fn {r, _} -> r == range end) do
      {_, hours} ->
        {:noreply,
         socket
         |> assign(time_range: range, time_range_hours: hours, custom_from: nil, custom_to: nil)
         |> load_tab_data()
         |> push_chart_updates()}

      nil ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("custom_range", %{"from" => from_str, "to" => to_str}, socket) do
    with {:ok, from_date} <- Date.from_iso8601(from_str),
         {:ok, to_date} <- Date.from_iso8601(to_str),
         true <- Date.compare(to_date, from_date) in [:gt, :eq],
         true <- Date.diff(to_date, from_date) <= @max_custom_range_days do
      from_dt = DateTime.new!(from_date, ~T[00:00:00], "Etc/UTC")
      to_dt = DateTime.new!(to_date, ~T[23:59:59], "Etc/UTC")

      {:noreply,
       socket
       |> assign(time_range: "custom", custom_from: from_dt, custom_to: to_dt)
       |> load_tab_data()
       |> push_chart_updates()}
    else
      _ ->
        {:noreply,
         socket
         |> put_flash(:error, "Invalid date range (max #{@max_custom_range_days} days)")}
    end
  end

  @impl true
  def handle_info(:refresh, socket) do
    schedule_refresh()

    {:noreply,
     socket
     |> assign(last_refresh: DateTime.utc_now())
     |> load_tab_data()
     |> push_chart_updates()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-bold">Metrics Dashboard</h1>
          <p class="text-base-content/70">Real-time server metrics visualization</p>
        </div>
        <div class="flex items-center gap-4">
          <div class="flex items-center gap-2 text-sm text-base-content/70">
            <span class="loading loading-ring loading-xs"></span>
            <span>Auto-refresh every 10s</span>
          </div>
          <span class="text-xs text-base-content/50">
            Last: {Calendar.strftime(@last_refresh, "%H:%M:%S")}
          </span>
        </div>
      </div>

      <!-- Time Range Selector -->
      <div class="flex flex-wrap gap-2 items-center">
        <button
          :for={{label, _hours} <- @time_ranges}
          type="button"
          class={["btn btn-sm", if(@time_range == label, do: "btn-primary", else: "btn-ghost")]}
          phx-click="change_time_range"
          phx-value-range={label}
        >
          {label}
        </button>

        <!-- Custom Range Form -->
        <form phx-change="custom_range" class="flex gap-2 items-center ml-4">
          <label class="text-sm">From:</label>
          <input
            type="date"
            name="from"
            value={format_date_input(@custom_from)}
            class="input input-sm input-bordered"
          />
          <label class="text-sm">To:</label>
          <input
            type="date"
            name="to"
            value={format_date_input(@custom_to)}
            class="input input-sm input-bordered"
          />
        </form>
      </div>

      <!-- Tabs -->
      <div role="tablist" class={["tabs tabs-boxed bg-base-100 p-1 w-fit"]}>
        <button
          :for={{tab_key, tab_atom} <- @tab_mapping}
          type="button"
          role="tab"
          class={["tab", if(@active_tab == tab_atom, do: "tab-active", else: "")]}
          phx-click="change_tab"
          phx-value-tab={tab_key}
        >
          {tab_label(tab_atom)}
        </button>
      </div>

      <!-- Tab Content -->
      <%= case @active_tab do %>
        <% :server -> %>
          <.server_tab
            players_online={@server_charts.players_online}
            creatures_spawned={@server_charts.creatures_spawned}
            active_zones={@server_charts.active_zones}
          />
        <% :auth -> %>
          <.auth_tab
            login_rate={@auth_charts.login_rate}
            login_results={@auth_charts.login_results}
            session_starts={@auth_charts.session_starts}
          />
        <% :gameplay -> %>
          <.gameplay_tab
            players_entering={@gameplay_charts.players_entering}
            quests_accepted={@gameplay_charts.quests_accepted}
            quests_completed={@gameplay_charts.quests_completed}
          />
        <% :combat -> %>
          <.combat_tab
            creatures_killed={@combat_charts.creatures_killed}
            xp_awarded={@combat_charts.xp_awarded}
            damage_dealt={@combat_charts.damage_dealt}
          />
      <% end %>
    </div>
    """
  end

  # Tab Components

  attr :players_online, :map, required: true
  attr :creatures_spawned, :map, required: true
  attr :active_zones, :map, required: true

  defp server_tab(assigns) do
    ~H"""
    <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
      <.chart_card title="Players Online" id="players-online" chart_data={@players_online} />
      <.chart_card
        title="Creatures Spawned"
        id="creatures-spawned"
        chart_data={@creatures_spawned}
      />
      <.chart_card title="Active Zones" id="active-zones" chart_data={@active_zones} />
    </div>
    """
  end

  attr :login_rate, :map, required: true
  attr :login_results, :map, required: true
  attr :session_starts, :map, required: true

  defp auth_tab(assigns) do
    ~H"""
    <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
      <.chart_card title="Login Rate" id="login-rate" chart_data={@login_rate} />
      <.chart_card
        title="Login Success/Failure"
        id="login-results"
        chart_data={@login_results}
        chart_type="bar"
      />
      <.chart_card title="Session Starts" id="session-starts" chart_data={@session_starts} />
    </div>
    """
  end

  attr :players_entering, :map, required: true
  attr :quests_accepted, :map, required: true
  attr :quests_completed, :map, required: true

  defp gameplay_tab(assigns) do
    ~H"""
    <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
      <.chart_card
        title="Players Entering World"
        id="players-entering"
        chart_data={@players_entering}
      />
      <.chart_card title="Quests Accepted" id="quests-accepted" chart_data={@quests_accepted} />
      <.chart_card
        title="Quests Completed"
        id="quests-completed"
        chart_data={@quests_completed}
      />
    </div>
    """
  end

  attr :creatures_killed, :map, required: true
  attr :xp_awarded, :map, required: true
  attr :damage_dealt, :map, required: true

  defp combat_tab(assigns) do
    ~H"""
    <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
      <.chart_card
        title="Creatures Killed"
        id="creatures-killed"
        chart_data={@creatures_killed}
      />
      <.chart_card title="XP Awarded" id="xp-awarded" chart_data={@xp_awarded} />
      <.chart_card title="Damage Dealt" id="damage-dealt" chart_data={@damage_dealt} />
    </div>
    """
  end

  # Chart Card Component

  attr :title, :string, required: true
  attr :id, :string, required: true
  attr :chart_data, :map, required: true
  attr :chart_type, :string, default: "line"

  defp chart_card(assigns) do
    has_data = length(assigns.chart_data[:labels] || []) > 0
    assigns = assign(assigns, :has_data, has_data)

    ~H"""
    <div class="card bg-base-100 shadow">
      <div class="card-body">
        <h3 class="card-title text-base">{@title}</h3>
        <div class="h-64 relative">
          <%!-- Always render canvas so hook can attach --%>
          <canvas
            id={@id}
            phx-hook="MetricsChart"
            phx-update="ignore"
            data-chart-type={@chart_type}
            data-chart-data={Jason.encode!(@chart_data)}
          />
          <%!-- Overlay message when no data --%>
          <%= unless @has_data do %>
            <div class="absolute inset-0 flex items-center justify-center bg-base-100/80">
              <div class="text-center text-base-content/50">
                <.icon name="hero-chart-bar" class="size-12 mx-auto mb-2 opacity-50" />
                <p>No data available for this time range</p>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # Helper Functions

  defp schedule_refresh do
    Process.send_after(self(), :refresh, @refresh_interval)
  end

  defp tab_label(:server), do: "Server"
  defp tab_label(:auth), do: "Auth"
  defp tab_label(:gameplay), do: "Gameplay"
  defp tab_label(:combat), do: "Combat"

  defp format_date_input(nil), do: ""

  defp format_date_input(%DateTime{} = dt) do
    Date.to_iso8601(DateTime.to_date(dt))
  end

  # Data Loading

  defp load_tab_data(socket) do
    {from, to, bucket_type} = get_time_range(socket)

    charts =
      case socket.assigns.active_tab do
        :server -> load_server_charts(from, to, bucket_type)
        :auth -> load_auth_charts(from, to, bucket_type)
        :gameplay -> load_gameplay_charts(from, to, bucket_type)
        :combat -> load_combat_charts(from, to, bucket_type)
      end

    assign(socket, :"#{socket.assigns.active_tab}_charts", charts)
  end

  defp get_time_range(socket) do
    case socket.assigns do
      %{custom_from: from, custom_to: to} when not is_nil(from) and not is_nil(to) ->
        bucket_type = if DateTime.diff(to, from, :hour) > 48, do: :hour, else: :minute
        {from, to, bucket_type}

      %{time_range_hours: hours} ->
        to = DateTime.utc_now()
        from = DateTime.add(to, -hours, :hour)
        bucket_type = if hours > 48, do: :hour, else: :minute
        {from, to, bucket_type}
    end
  end

  defp load_server_charts(from, to, bucket_type) do
    %{
      players_online: query_metric("bezgelor.world.players_online", "count", from, to, bucket_type, :line),
      creatures_spawned: query_metric("bezgelor.world.creatures_spawned", "count", from, to, bucket_type, :line),
      active_zones: query_metric("bezgelor.world.active_zones", "count", from, to, bucket_type, :line)
    }
  end

  defp load_auth_charts(from, to, bucket_type) do
    %{
      login_rate: query_metric("bezgelor.auth.login_complete", "count", from, to, bucket_type, :line),
      login_results: query_metric_by_metadata("bezgelor.auth.login_complete", "success", from, to, bucket_type),
      session_starts: query_metric("bezgelor.auth.session_start", "count", from, to, bucket_type, :line)
    }
  end

  defp load_gameplay_charts(from, to, bucket_type) do
    %{
      players_entering: query_metric("bezgelor.world.player_entered", "count", from, to, bucket_type, :line),
      quests_accepted: query_metric("bezgelor.quests.accepted", "count", from, to, bucket_type, :line),
      quests_completed: query_metric("bezgelor.quests.completed", "count", from, to, bucket_type, :line)
    }
  end

  defp load_combat_charts(from, to, bucket_type) do
    %{
      creatures_killed: query_metric("bezgelor.combat.creature_killed", "count", from, to, bucket_type, :line),
      xp_awarded: query_metric("bezgelor.xp.awarded", "xp", from, to, bucket_type, :line),
      damage_dealt: query_metric("bezgelor.combat.damage_dealt", "damage", from, to, bucket_type, :line)
    }
  end

  # Query metric sum_values from buckets
  defp query_metric(event_name, field, from, to, bucket_type, _chart_type) do
    buckets = Metrics.query_buckets(event_name, bucket_type, from, to)

    labels = Enum.map(buckets, fn b -> format_bucket_time(b.bucket_start) end)

    values =
      Enum.map(buckets, fn b ->
        get_in(b.sum_values, [field]) || 0
      end)

    %{
      labels: labels,
      datasets: [
        %{
          label: String.replace(event_name, "bezgelor.", ""),
          data: values,
          borderColor: "rgb(59, 130, 246)",
          backgroundColor: "rgba(59, 130, 246, 0.1)",
          tension: 0.3
        }
      ]
    }
  end

  # Query metric aggregating by metadata (for bar charts)
  defp query_metric_by_metadata(event_name, metadata_key, from, to, bucket_type) do
    buckets = Metrics.query_buckets(event_name, bucket_type, from, to)

    # Aggregate metadata counts across all buckets
    metadata_totals =
      Enum.reduce(buckets, %{}, fn bucket, acc ->
        metadata_counts = Map.get(bucket.metadata_counts, metadata_key, %{})

        Enum.reduce(metadata_counts, acc, fn {key, count}, acc2 ->
          Map.update(acc2, key, count, &(&1 + count))
        end)
      end)

    labels = Map.keys(metadata_totals)
    values = Map.values(metadata_totals)

    %{
      labels: labels,
      datasets: [
        %{
          label: String.replace(event_name, "bezgelor.", ""),
          data: values,
          backgroundColor: [
            "rgba(34, 197, 94, 0.5)",
            "rgba(239, 68, 68, 0.5)"
          ],
          borderColor: [
            "rgb(34, 197, 94)",
            "rgb(239, 68, 68)"
          ],
          borderWidth: 1
        }
      ]
    }
  end

  defp format_bucket_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%m/%d %H:%M")
  end

  # Push chart updates to hooks
  defp push_chart_updates(socket) do
    tab = socket.assigns.active_tab
    charts = Map.get(socket.assigns, :"#{tab}_charts", %{})

    Enum.reduce(charts, socket, fn {chart_key, chart_data}, acc ->
      chart_id = chart_key_to_id(chart_key)
      push_event(acc, "update-chart-#{chart_id}", chart_data)
    end)
  end

  defp chart_key_to_id(key) do
    key
    |> Atom.to_string()
    |> String.replace("_", "-")
  end
end
