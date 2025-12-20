defmodule BezgelorPortalWeb.Admin.ServerLive do
  @dialyzer :no_match

  @moduledoc """
  Admin LiveView for server operations.

  Features:
  - Server status and uptime
  - Maintenance mode toggle
  - MOTD editor
  - Broadcast messages
  - Connected players view
  - Zone management
  """
  use BezgelorPortalWeb, :live_view

  alias BezgelorDb.Authorization
  alias BezgelorWorld.Portal

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Refresh every 10 seconds
      :timer.send_interval(10_000, self(), :refresh)
    end

    {:ok,
     socket
     |> assign(
       page_title: "Server Operations",
       active_tab: :status,
       # Server state from world server
       maintenance_mode: Portal.get_maintenance_mode(),
       motd: Portal.get_motd(),
       motd_editing: false,
       motd_draft: "",
       # Broadcast form
       broadcast_form: %{"message" => "", "target" => "all"},
       # Stats
       server_start_time: get_server_start_time(),
       connected_players: load_online_players(),
       zone_instances: Portal.zone_player_counts()
     ), layout: {BezgelorPortalWeb.Layouts, :admin}}
  end

  @impl true
  def handle_info(:refresh, socket) do
    {:noreply,
     assign(socket,
       connected_players: load_online_players(),
       zone_instances: Portal.zone_player_counts(),
       maintenance_mode: Portal.get_maintenance_mode()
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-bold">Server Operations</h1>
          <p class="text-base-content/70">Manage server settings and connected players</p>
        </div>
        <div class="flex items-center gap-2">
          <span class={"badge badge-lg #{if @maintenance_mode, do: "badge-warning", else: "badge-success"}"}>
            {if @maintenance_mode, do: "Maintenance Mode", else: "Online"}
          </span>
        </div>
      </div>
      
    <!-- Tabs -->
      <div role="tablist" class="tabs tabs-boxed bg-base-100 p-1 w-fit">
        <button
          :for={tab <- [:status, :broadcast, :players, :zones]}
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
        <% :status -> %>
          <.status_tab
            maintenance_mode={@maintenance_mode}
            motd={@motd}
            motd_editing={@motd_editing}
            motd_draft={@motd_draft}
            server_start_time={@server_start_time}
            player_count={length(@connected_players)}
          />
        <% :broadcast -> %>
          <.broadcast_tab form={@broadcast_form} />
        <% :players -> %>
          <.players_tab players={@connected_players} />
        <% :zones -> %>
          <.zones_tab zones={@zone_instances} />
      <% end %>
    </div>
    """
  end

  # Tab components

  attr :maintenance_mode, :boolean, required: true
  attr :motd, :string, required: true
  attr :motd_editing, :boolean, required: true
  attr :motd_draft, :string, required: true
  attr :server_start_time, :any, required: true
  attr :player_count, :integer, required: true

  defp status_tab(assigns) do
    ~H"""
    <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
      <!-- Server Stats -->
      <div class="card bg-base-100 shadow">
        <div class="card-body">
          <h2 class="card-title">Server Status</h2>
          <div class="space-y-4">
            <div class="flex justify-between items-center">
              <span class="text-base-content/70">Uptime</span>
              <span class="font-mono">{format_uptime(@server_start_time)}</span>
            </div>
            <div class="flex justify-between items-center">
              <span class="text-base-content/70">Connected Players</span>
              <span class="font-bold">{@player_count}</span>
            </div>
            <div class="flex justify-between items-center">
              <span class="text-base-content/70">Server Time</span>
              <span class="font-mono">
                {Calendar.strftime(DateTime.utc_now(), "%Y-%m-%d %H:%M:%S UTC")}
              </span>
            </div>
          </div>
        </div>
      </div>
      
    <!-- Maintenance Mode -->
      <div class="card bg-base-100 shadow">
        <div class="card-body">
          <h2 class="card-title">Maintenance Mode</h2>
          <p class="text-sm text-base-content/70">
            When enabled, new connections are blocked and a maintenance message is shown.
          </p>
          <div class="mt-4">
            <div class="form-control">
              <label class="label cursor-pointer justify-start gap-4">
                <input
                  type="checkbox"
                  class="toggle toggle-warning"
                  checked={@maintenance_mode}
                  phx-click="toggle_maintenance"
                />
                <span class="label-text">
                  {if @maintenance_mode, do: "Maintenance mode is ON", else: "Maintenance mode is OFF"}
                </span>
              </label>
            </div>
          </div>
          <div :if={@maintenance_mode} class="alert alert-warning mt-4">
            <.icon name="hero-exclamation-triangle" class="size-5" />
            <span>Server is in maintenance mode. New players cannot connect.</span>
          </div>
        </div>
      </div>
      
    <!-- MOTD -->
      <div class="card bg-base-100 shadow lg:col-span-2">
        <div class="card-body">
          <div class="flex items-center justify-between">
            <h2 class="card-title">Message of the Day</h2>
            <button
              :if={!@motd_editing}
              type="button"
              class="btn btn-ghost btn-sm"
              phx-click="edit_motd"
            >
              <.icon name="hero-pencil" class="size-4" /> Edit
            </button>
          </div>

          <%= if @motd_editing do %>
            <form phx-submit="save_motd" class="mt-4">
              <textarea
                name="motd"
                class="textarea textarea-bordered w-full"
                rows="4"
                placeholder="Enter the message of the day..."
              >{@motd_draft}</textarea>
              <div class="flex gap-2 mt-2">
                <button type="submit" class="btn btn-primary btn-sm">Save</button>
                <button type="button" class="btn btn-ghost btn-sm" phx-click="cancel_motd">
                  Cancel
                </button>
              </div>
            </form>
          <% else %>
            <div class="mt-4 p-4 bg-base-200 rounded-lg">
              <p class="whitespace-pre-wrap">{@motd}</p>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  attr :form, :map, required: true

  defp broadcast_tab(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow max-w-2xl">
      <div class="card-body">
        <h2 class="card-title">Broadcast Message</h2>
        <p class="text-sm text-base-content/70">
          Send a message to all connected players.
        </p>

        <form phx-submit="send_broadcast" class="mt-4 space-y-4">
          <div class="form-control">
            <label class="label">
              <span class="label-text">Target</span>
            </label>
            <select name="target" class="select select-bordered">
              <option value="all" selected={@form["target"] == "all"}>All Players</option>
              <option value="exile" selected={@form["target"] == "exile"}>Exile Only</option>
              <option value="dominion" selected={@form["target"] == "dominion"}>Dominion Only</option>
            </select>
          </div>

          <div class="form-control">
            <label class="label">
              <span class="label-text">Message</span>
            </label>
            <textarea
              name="message"
              class="textarea textarea-bordered"
              rows="3"
              placeholder="Enter your message..."
              required
            >{@form["message"]}</textarea>
          </div>

          <div class="alert alert-info">
            <.icon name="hero-information-circle" class="size-5" />
            <span>Messages will appear as system announcements in-game.</span>
          </div>

          <button type="submit" class="btn btn-primary">
            <.icon name="hero-megaphone" class="size-4" /> Send Broadcast
          </button>
        </form>
      </div>
    </div>
    """
  end

  attr :players, :list, required: true

  defp players_tab(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow">
      <div class="card-body">
        <div class="flex items-center justify-between">
          <h2 class="card-title">Connected Players ({length(@players)})</h2>
          <button
            type="button"
            class="btn btn-error btn-sm"
            phx-click="kick_all"
            data-confirm="Kick all connected players?"
          >
            <.icon name="hero-x-mark" class="size-4" /> Kick All
          </button>
        </div>

        <%= if Enum.empty?(@players) do %>
          <p class="text-base-content/50 mt-4">No players connected</p>
        <% else %>
          <div class="overflow-x-auto mt-4">
            <table class="table">
              <thead>
                <tr>
                  <th>Character</th>
                  <th>Account</th>
                  <th>Zone</th>
                  <th>Level</th>
                  <th>Connected</th>
                  <th>Actions</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={player <- @players} class="hover">
                  <td class="font-semibold">{player.character_name}</td>
                  <td class="text-sm text-base-content/70">{player.account_email}</td>
                  <td>{player.zone_name}</td>
                  <td>{player.level}</td>
                  <td class="text-sm">{format_duration(player.connected_at)}</td>
                  <td>
                    <button
                      type="button"
                      class="btn btn-ghost btn-xs text-error"
                      phx-click="kick_player"
                      phx-value-id={player.id}
                      data-confirm={"Kick #{player.character_name}?"}
                    >
                      Kick
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  attr :zones, :list, required: true

  defp zones_tab(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow">
      <div class="card-body">
        <h2 class="card-title">Active Zone Instances</h2>

        <%= if Enum.empty?(@zones) do %>
          <p class="text-base-content/50 mt-4">No active zones</p>
        <% else %>
          <div class="overflow-x-auto mt-4">
            <table class="table">
              <thead>
                <tr>
                  <th>Zone</th>
                  <th>Instance</th>
                  <th>Players</th>
                  <th>Status</th>
                  <th>Actions</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={zone <- @zones} class="hover">
                  <td>
                    <div>
                      <div class="font-semibold">{zone.name}</div>
                      <div class="text-xs text-base-content/50">ID: {zone.zone_id}</div>
                    </div>
                  </td>
                  <td>{zone.instance_id}</td>
                  <td>{zone.player_count}</td>
                  <td>
                    <span class={"badge #{if zone.status == :active, do: "badge-success", else: "badge-ghost"}"}>
                      {zone.status}
                    </span>
                  </td>
                  <td>
                    <button
                      type="button"
                      class="btn btn-ghost btn-xs"
                      phx-click="restart_zone"
                      phx-value-zone={zone.zone_id}
                      phx-value-instance={zone.instance_id}
                      data-confirm={"Restart zone #{zone.name}? All players will be disconnected."}
                    >
                      Restart
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Event handlers

  @impl true
  def handle_event("change_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, active_tab: String.to_existing_atom(tab))}
  end

  @impl true
  def handle_event("toggle_maintenance", _, socket) do
    admin = socket.assigns.current_account
    new_mode = !socket.assigns.maintenance_mode

    Portal.set_maintenance_mode(new_mode)
    Authorization.log_action(admin, "server.maintenance", "system", nil, %{enabled: new_mode})

    {:noreply,
     socket
     |> put_flash(
       :info,
       if(new_mode, do: "Maintenance mode enabled", else: "Maintenance mode disabled")
     )
     |> assign(maintenance_mode: new_mode)}
  end

  @impl true
  def handle_event("edit_motd", _, socket) do
    {:noreply, assign(socket, motd_editing: true, motd_draft: socket.assigns.motd)}
  end

  @impl true
  def handle_event("cancel_motd", _, socket) do
    {:noreply, assign(socket, motd_editing: false, motd_draft: "")}
  end

  @impl true
  def handle_event("save_motd", %{"motd" => new_motd}, socket) do
    admin = socket.assigns.current_account

    Portal.set_motd(new_motd)

    Authorization.log_action(admin, "server.motd_update", "system", nil, %{
      old_motd: socket.assigns.motd,
      new_motd: new_motd
    })

    {:noreply,
     socket
     |> put_flash(:info, "MOTD updated")
     |> assign(motd: new_motd, motd_editing: false, motd_draft: "")}
  end

  @impl true
  def handle_event("send_broadcast", %{"message" => message, "target" => target}, socket) do
    admin = socket.assigns.current_account

    case target do
      "all" ->
        Portal.broadcast_system_message(message)

      zone_id when is_binary(zone_id) ->
        case Integer.parse(zone_id) do
          {id, ""} -> Portal.broadcast_to_zone(id, message)
          _ -> Portal.broadcast_system_message(message)
        end

      _ ->
        Portal.broadcast_system_message(message)
    end

    Authorization.log_action(admin, "server.broadcast", "system", nil, %{
      message: message,
      target: target
    })

    {:noreply, put_flash(socket, :info, "Broadcast sent to #{target} players")}
  end

  @impl true
  def handle_event("kick_player", %{"id" => id_str}, socket) do
    admin = socket.assigns.current_account

    case Integer.parse(id_str) do
      {account_id, ""} ->
        case Portal.kick_player(account_id, "Kicked by administrator") do
          :ok ->
            Authorization.log_action(admin, "server.kick_player", "account", account_id, %{})

            {:noreply,
             socket
             |> put_flash(:info, "Player kicked")
             |> assign(connected_players: load_online_players())}

          {:error, :not_online} ->
            {:noreply, put_flash(socket, :error, "Player is not online")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Invalid player ID")}
    end
  end

  @impl true
  def handle_event("kick_all", _, socket) do
    admin = socket.assigns.current_account
    players = socket.assigns.connected_players

    Enum.each(players, fn player ->
      Portal.kick_player(player.account_id, "Server-wide kick by administrator")
    end)

    Authorization.log_action(admin, "server.kick_all", "system", nil, %{
      player_count: length(players)
    })

    {:noreply,
     socket
     |> put_flash(:info, "All players kicked (#{length(players)})")
     |> assign(connected_players: [])}
  end

  @impl true
  def handle_event("restart_zone", %{"zone" => zone_id_str, "instance" => _instance_id}, socket) do
    admin = socket.assigns.current_account

    case Integer.parse(zone_id_str) do
      {zone_id, ""} ->
        case Portal.restart_zone(zone_id) do
          :ok ->
            Authorization.log_action(admin, "server.restart_zone", "zone", zone_id, %{})

            {:noreply,
             socket
             |> put_flash(:info, "Zone restart initiated")
             |> assign(zone_instances: Portal.zone_player_counts())}

          {:error, :zone_not_found} ->
            {:noreply, put_flash(socket, :error, "Zone not found or has no players")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Invalid zone ID")}
    end
  end

  # Helpers

  defp tab_label(:status), do: "Server Status"
  defp tab_label(:broadcast), do: "Broadcast"
  defp tab_label(:players), do: "Players"
  defp tab_label(:zones), do: "Zones"

  defp format_uptime(start_time) do
    diff = DateTime.diff(DateTime.utc_now(), start_time, :second)
    days = div(diff, 86400)
    hours = div(rem(diff, 86400), 3600)
    minutes = div(rem(diff, 3600), 60)
    seconds = rem(diff, 60)

    cond do
      days > 0 -> "#{days}d #{hours}h #{minutes}m"
      hours > 0 -> "#{hours}h #{minutes}m #{seconds}s"
      true -> "#{minutes}m #{seconds}s"
    end
  end

  defp format_duration(datetime) do
    diff = DateTime.diff(DateTime.utc_now(), datetime, :second)
    hours = div(diff, 3600)
    minutes = div(rem(diff, 3600), 60)

    cond do
      hours > 0 -> "#{hours}h #{minutes}m"
      true -> "#{minutes}m"
    end
  end

  # Load online players from world server
  defp load_online_players do
    Portal.list_online_players()
    |> Enum.map(fn player ->
      # Enrich with character data if available
      character = get_character_info(player.character_id)
      account = get_account_info(player.account_id)

      %{
        id: player.account_id,
        account_id: player.account_id,
        character_name: player.character_name,
        account_email: account[:email] || "Unknown",
        zone_name: get_zone_name(player.zone_id),
        level: character[:level] || 1,
        connected_at: DateTime.utc_now() |> DateTime.add(-300, :second)
      }
    end)
  end

  defp get_character_info(nil), do: %{}

  defp get_character_info(character_id) do
    case BezgelorDb.Characters.get_character(character_id) do
      {:ok, char} -> %{level: char.level, name: char.name}
      _ -> %{}
    end
  end

  defp get_account_info(nil), do: %{}

  defp get_account_info(account_id) do
    case BezgelorDb.Accounts.get_by_id(account_id) do
      %{email: email} -> %{email: email}
      _ -> %{}
    end
  end

  defp get_zone_name(nil), do: "Unknown"

  defp get_zone_name(zone_id) do
    try do
      case BezgelorData.Store.get(:world_location, zone_id) do
        :error -> "Zone #{zone_id}"
        {:ok, data} -> Map.get(data, :name) || Map.get(data, "name") || "Zone #{zone_id}"
      end
    rescue
      ArgumentError -> "Zone #{zone_id}"
    end
  end

  defp get_server_start_time do
    # Get actual uptime from BEAM VM
    case :erlang.statistics(:wall_clock) do
      {total_ms, _since_last} ->
        DateTime.utc_now() |> DateTime.add(-div(total_ms, 1000), :second)
    end
  end
end
