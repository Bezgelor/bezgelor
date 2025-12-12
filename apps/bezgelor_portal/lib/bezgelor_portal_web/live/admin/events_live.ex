defmodule BezgelorPortalWeb.Admin.EventsLive do
  @moduledoc """
  Admin LiveView for event and world boss management.

  Features:
  - Active/scheduled events list
  - Event controls (start, stop, cancel)
  - World boss status and controls
  - Event schedule management
  """
  use BezgelorPortalWeb, :live_view

  alias BezgelorDb.{PublicEvents, Authorization}
  alias BezgelorWorld.Portal

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Refresh every 30 seconds
      :timer.send_interval(30_000, self(), :refresh)
    end

    {:ok,
     socket
     |> assign(
       page_title: "Event Management",
       active_tab: :events,
       show_schedule_modal: false,
       schedule_form: %{"event_id" => "", "zone_id" => "", "trigger_type" => "interval", "interval_hours" => "4"}
     )
     |> load_data(),
     layout: {BezgelorPortalWeb.Layouts, :admin}}
  end

  @impl true
  def handle_info(:refresh, socket) do
    {:noreply, load_data(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-bold">Event Management</h1>
          <p class="text-base-content/70">Manage public events and world bosses</p>
        </div>
        <div class="text-sm text-base-content/70">
          Auto-refreshes every 30s
        </div>
      </div>

      <!-- Tabs -->
      <div role="tablist" class="tabs tabs-boxed bg-base-100 p-1 w-fit">
        <button
          :for={tab <- [:events, :world_bosses, :schedules]}
          type="button"
          role="tab"
          class={"tab #{if @active_tab == tab, do: "tab-active"}"}
          phx-click="change_tab"
          phx-value-tab={tab}
        >
          {tab_label(tab)}
        </button>
      </div>

      <!-- Tab Content -->
      <%= case @active_tab do %>
        <% :events -> %>
          <.events_tab events={@active_events} permissions={@permissions} />
        <% :world_bosses -> %>
          <.world_bosses_tab bosses={@world_bosses} permissions={@permissions} />
        <% :schedules -> %>
          <.schedules_tab
            schedules={@schedules}
            show_modal={@show_schedule_modal}
            form={@schedule_form}
            permissions={@permissions}
          />
      <% end %>
    </div>
    """
  end

  # Tab components

  attr :events, :list, required: true
  attr :permissions, :list, required: true

  defp events_tab(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="card bg-base-100 shadow">
        <div class="card-body">
          <h2 class="card-title">Active Events</h2>
          <%= if Enum.empty?(@events) do %>
            <p class="text-base-content/50">No active events</p>
          <% else %>
            <div class="overflow-x-auto">
              <table class="table">
                <thead>
                  <tr>
                    <th>Event ID</th>
                    <th>Zone</th>
                    <th>Status</th>
                    <th>Phase</th>
                    <th>Progress</th>
                    <th>Participants</th>
                    <th>Started</th>
                    <th>Actions</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={event <- @events} class="hover">
                    <td class="font-mono">{event.event_id}</td>
                    <td>{event.zone_id}</td>
                    <td>
                      <.event_status_badge status={event.status} />
                    </td>
                    <td>{event.current_phase}/{event.max_phases || "?"}</td>
                    <td>
                      <div class="flex items-center gap-2">
                        <progress
                          class="progress progress-primary w-20"
                          value={event.progress}
                          max="100"
                        />
                        <span class="text-sm">{event.progress}%</span>
                      </div>
                    </td>
                    <td>{event.participant_count}</td>
                    <td class="text-sm">{format_datetime(event.started_at)}</td>
                    <td>
                      <div class="flex gap-1">
                        <button
                          :if={"events.control" in @permissions && event.status == :active}
                          type="button"
                          class="btn btn-ghost btn-xs text-success"
                          phx-click="complete_event"
                          phx-value-id={event.id}
                          data-confirm="Complete this event successfully?"
                        >
                          Complete
                        </button>
                        <button
                          :if={"events.control" in @permissions && event.status == :active}
                          type="button"
                          class="btn btn-ghost btn-xs text-error"
                          phx-click="cancel_event"
                          phx-value-id={event.id}
                          data-confirm="Cancel this event?"
                        >
                          Cancel
                        </button>
                      </div>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  attr :bosses, :list, required: true
  attr :permissions, :list, required: true

  defp world_bosses_tab(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="card bg-base-100 shadow">
        <div class="card-body">
          <h2 class="card-title">World Bosses</h2>
          <%= if Enum.empty?(@bosses) do %>
            <p class="text-base-content/50">No world boss spawns configured</p>
          <% else %>
            <div class="overflow-x-auto">
              <table class="table">
                <thead>
                  <tr>
                    <th>Boss ID</th>
                    <th>Zone</th>
                    <th>Status</th>
                    <th>Spawn Window</th>
                    <th>Last Killed</th>
                    <th>Actions</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={boss <- @bosses} class="hover">
                    <td class="font-mono">{boss.boss_id}</td>
                    <td>{boss.zone_id}</td>
                    <td>
                      <.boss_status_badge status={boss.status} />
                    </td>
                    <td>
                      <%= if boss.window_start && boss.window_end do %>
                        {format_datetime(boss.window_start)} - {format_datetime(boss.window_end)}
                      <% else %>
                        <span class="text-base-content/50">Not set</span>
                      <% end %>
                    </td>
                    <td class="text-sm">
                      {format_datetime(boss.killed_at) || "-"}
                    </td>
                    <td>
                      <div class="flex gap-1">
                        <button
                          :if={"events.control" in @permissions && boss.status == :waiting}
                          type="button"
                          class="btn btn-primary btn-xs"
                          phx-click="spawn_boss"
                          phx-value-id={boss.boss_id}
                          data-confirm="Force spawn this world boss?"
                        >
                          Spawn
                        </button>
                        <button
                          :if={"events.control" in @permissions && boss.status in [:spawned, :engaged]}
                          type="button"
                          class="btn btn-error btn-xs"
                          phx-click="kill_boss"
                          phx-value-id={boss.boss_id}
                          data-confirm="Force kill this world boss?"
                        >
                          Kill
                        </button>
                      </div>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  attr :schedules, :list, required: true
  attr :show_modal, :boolean, required: true
  attr :form, :map, required: true
  attr :permissions, :list, required: true

  defp schedules_tab(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="card bg-base-100 shadow">
        <div class="card-body">
          <div class="flex items-center justify-between">
            <h2 class="card-title">Event Schedules</h2>
            <button
              :if={"events.control" in @permissions}
              type="button"
              class="btn btn-primary btn-sm"
              phx-click="show_schedule_modal"
            >
              <.icon name="hero-plus" class="size-4" />
              Add Schedule
            </button>
          </div>

          <%= if Enum.empty?(@schedules) do %>
            <p class="text-base-content/50">No event schedules configured</p>
          <% else %>
            <div class="overflow-x-auto">
              <table class="table">
                <thead>
                  <tr>
                    <th>Event ID</th>
                    <th>Zone</th>
                    <th>Trigger Type</th>
                    <th>Next Trigger</th>
                    <th>Enabled</th>
                    <th>Actions</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={schedule <- @schedules} class="hover">
                    <td class="font-mono">{schedule.event_id}</td>
                    <td>{schedule.zone_id}</td>
                    <td>{schedule.trigger_type}</td>
                    <td class="text-sm">{format_datetime(schedule.next_trigger_at)}</td>
                    <td>
                      <%= if schedule.enabled do %>
                        <span class="badge badge-success">Enabled</span>
                      <% else %>
                        <span class="badge badge-ghost">Disabled</span>
                      <% end %>
                    </td>
                    <td>
                      <div class="flex gap-1">
                        <button
                          :if={"events.control" in @permissions}
                          type="button"
                          class={"btn btn-ghost btn-xs #{if schedule.enabled, do: "text-warning", else: "text-success"}"}
                          phx-click="toggle_schedule"
                          phx-value-id={schedule.id}
                        >
                          {if schedule.enabled, do: "Disable", else: "Enable"}
                        </button>
                      </div>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          <% end %>
        </div>
      </div>

      <!-- Schedule Modal -->
      <.modal :if={@show_modal} id="schedule-modal" show on_cancel={JS.push("hide_schedule_modal")}>
        <:title>Create Event Schedule</:title>
        <form phx-submit="create_schedule" class="space-y-4">
          <div class="form-control">
            <label class="label"><span class="label-text">Event ID</span></label>
            <input type="number" name="event_id" value={@form["event_id"]} class="input input-bordered" required />
          </div>
          <div class="form-control">
            <label class="label"><span class="label-text">Zone ID</span></label>
            <input type="number" name="zone_id" value={@form["zone_id"]} class="input input-bordered" required />
          </div>
          <div class="form-control">
            <label class="label"><span class="label-text">Trigger Type</span></label>
            <select name="trigger_type" class="select select-bordered">
              <option value="interval" selected={@form["trigger_type"] == "interval"}>Interval</option>
              <option value="time_of_day" selected={@form["trigger_type"] == "time_of_day"}>Time of Day</option>
              <option value="manual" selected={@form["trigger_type"] == "manual"}>Manual Only</option>
            </select>
          </div>
          <div class="form-control">
            <label class="label"><span class="label-text">Interval (hours)</span></label>
            <input type="number" name="interval_hours" value={@form["interval_hours"]} class="input input-bordered" min="1" />
          </div>
          <div class="modal-action">
            <button type="button" class="btn" phx-click="hide_schedule_modal">Cancel</button>
            <button type="submit" class="btn btn-primary">Create Schedule</button>
          </div>
        </form>
      </.modal>
    </div>
    """
  end

  attr :status, :atom, required: true

  defp event_status_badge(%{status: :pending} = assigns), do: ~H|<span class="badge badge-ghost">Pending</span>|
  defp event_status_badge(%{status: :active} = assigns), do: ~H|<span class="badge badge-success">Active</span>|
  defp event_status_badge(%{status: :completed} = assigns), do: ~H|<span class="badge badge-info">Completed</span>|
  defp event_status_badge(%{status: :failed} = assigns), do: ~H|<span class="badge badge-error">Failed</span>|
  defp event_status_badge(%{status: :cancelled} = assigns), do: ~H|<span class="badge badge-warning">Cancelled</span>|
  defp event_status_badge(assigns), do: ~H|<span class="badge">{@status}</span>|

  attr :status, :atom, required: true

  defp boss_status_badge(%{status: :waiting} = assigns), do: ~H|<span class="badge badge-ghost">Waiting</span>|
  defp boss_status_badge(%{status: :spawned} = assigns), do: ~H|<span class="badge badge-success">Spawned</span>|
  defp boss_status_badge(%{status: :engaged} = assigns), do: ~H|<span class="badge badge-warning">Engaged</span>|
  defp boss_status_badge(%{status: :dead} = assigns), do: ~H|<span class="badge badge-error">Dead</span>|
  defp boss_status_badge(assigns), do: ~H|<span class="badge">{@status}</span>|

  # Event handlers

  @impl true
  def handle_event("change_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, active_tab: String.to_existing_atom(tab))}
  end

  @impl true
  def handle_event("show_schedule_modal", _, socket) do
    {:noreply, assign(socket, show_schedule_modal: true)}
  end

  @impl true
  def handle_event("hide_schedule_modal", _, socket) do
    {:noreply, assign(socket, show_schedule_modal: false)}
  end

  @impl true
  def handle_event("complete_event", %{"id" => id_str}, socket) do
    admin = socket.assigns.current_account
    id = String.to_integer(id_str)

    case PublicEvents.complete_event(id) do
      {:ok, _} ->
        Authorization.log_action(admin, "event.complete", "event", id, %{})
        {:noreply, socket |> put_flash(:info, "Event completed") |> load_data()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to complete event")}
    end
  end

  @impl true
  def handle_event("cancel_event", %{"id" => id_str}, socket) do
    admin = socket.assigns.current_account
    id = String.to_integer(id_str)

    case PublicEvents.cancel_event(id) do
      {:ok, _} ->
        Authorization.log_action(admin, "event.cancel", "event", id, %{})
        {:noreply, socket |> put_flash(:info, "Event cancelled") |> load_data()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to cancel event")}
    end
  end

  @impl true
  def handle_event("spawn_boss", %{"id" => id_str}, socket) do
    admin = socket.assigns.current_account
    boss_id = String.to_integer(id_str)

    # Spawn via Portal (world server) and update database
    Portal.spawn_world_boss(boss_id)

    case PublicEvents.spawn_boss(boss_id) do
      {:ok, _} ->
        Authorization.log_action(admin, "boss.spawn", "boss", boss_id, %{})
        {:noreply, socket |> put_flash(:info, "Boss spawned") |> load_data()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to spawn boss")}
    end
  end

  @impl true
  def handle_event("kill_boss", %{"id" => id_str}, socket) do
    admin = socket.assigns.current_account
    boss_id = String.to_integer(id_str)

    # Despawn via Portal (world server) and update database
    Portal.despawn_world_boss(boss_id)

    case PublicEvents.kill_boss(boss_id, 24) do
      {:ok, _} ->
        Authorization.log_action(admin, "boss.kill", "boss", boss_id, %{})
        {:noreply, socket |> put_flash(:info, "Boss killed") |> load_data()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to kill boss")}
    end
  end

  @impl true
  def handle_event("toggle_schedule", %{"id" => id_str}, socket) do
    admin = socket.assigns.current_account
    id = String.to_integer(id_str)

    schedule = Enum.find(socket.assigns.schedules, &(&1.id == id))

    result =
      if schedule.enabled do
        PublicEvents.disable_schedule(id)
      else
        PublicEvents.enable_schedule(id)
      end

    case result do
      {:ok, _} ->
        action = if schedule.enabled, do: "schedule.disable", else: "schedule.enable"
        Authorization.log_action(admin, action, "schedule", id, %{})
        {:noreply, load_data(socket)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to toggle schedule")}
    end
  end

  @impl true
  def handle_event("create_schedule", params, socket) do
    admin = socket.assigns.current_account

    with {event_id, ""} <- Integer.parse(params["event_id"] || ""),
         {zone_id, ""} <- Integer.parse(params["zone_id"] || "") do
      trigger_type = String.to_existing_atom(params["trigger_type"])
      interval_hours = String.to_integer(params["interval_hours"] || "4")

      config = %{
        interval_ms: interval_hours * 60 * 60 * 1000
      }

      case PublicEvents.create_schedule(event_id, zone_id, trigger_type, config) do
        {:ok, schedule} ->
          Authorization.log_action(admin, "schedule.create", "schedule", schedule.id, %{
            event_id: event_id,
            zone_id: zone_id,
            trigger_type: trigger_type
          })

          {:noreply,
           socket
           |> put_flash(:info, "Schedule created")
           |> assign(show_schedule_modal: false)
           |> load_data()}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to create schedule")}
      end
    else
      _ -> {:noreply, put_flash(socket, :error, "Invalid input")}
    end
  end

  # Helpers

  defp load_data(socket) do
    admin = socket.assigns.current_account
    permissions = Authorization.get_account_permissions(admin) |> Enum.map(& &1.key)

    # Get active events from world server via Portal
    active_events = Portal.list_active_events()
    |> Enum.map(fn event ->
      %{
        id: event[:id] || event[:event_instance_id],
        event_id: event[:event_id],
        zone_id: event[:zone_id],
        status: event[:status] || :active,
        current_phase: event[:current_phase] || 1,
        max_phases: event[:max_phases],
        progress: event[:progress] || 0,
        participant_count: event[:participant_count] || 0,
        started_at: event[:started_at]
      }
    end)

    # Get world boss spawns from database and Portal
    world_bosses = (PublicEvents.get_waiting_bosses() ++ get_spawned_bosses())
    |> Enum.concat(Portal.list_world_bosses())
    |> Enum.uniq_by(& &1.boss_id)

    # Get schedules
    schedules = get_all_schedules()

    assign(socket,
      permissions: permissions,
      active_events: active_events,
      world_bosses: world_bosses,
      schedules: schedules
    )
  end

  defp get_spawned_bosses do
    # Query for spawned/engaged bosses
    import Ecto.Query
    alias BezgelorDb.Schema.WorldBossSpawn
    alias BezgelorDb.Repo

    WorldBossSpawn
    |> where([b], b.status in [:spawned, :engaged])
    |> Repo.all()
  end

  defp get_all_schedules do
    import Ecto.Query
    alias BezgelorDb.Schema.EventSchedule
    alias BezgelorDb.Repo

    EventSchedule
    |> order_by([s], [s.zone_id, s.event_id])
    |> Repo.all()
  end

  defp tab_label(:events), do: "Active Events"
  defp tab_label(:world_bosses), do: "World Bosses"
  defp tab_label(:schedules), do: "Schedules"

  defp format_datetime(nil), do: nil
  defp format_datetime(datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M")
end
