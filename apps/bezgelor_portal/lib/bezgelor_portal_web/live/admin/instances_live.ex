defmodule BezgelorPortalWeb.Admin.InstancesLive do
  @dialyzer :no_match

  @moduledoc """
  Admin LiveView for managing dungeon and raid instances.

  Features:
  - List all active instances
  - View instance details with players and boss status
  - Force close instances
  - Manage player lockouts
  """
  use BezgelorPortalWeb, :live_view

  alias BezgelorDb.{Characters, Lockouts, Authorization}
  alias BezgelorWorld.Portal

  @refresh_interval 10_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      :timer.send_interval(@refresh_interval, self(), :refresh)
    end

    {:ok,
     assign(socket,
       page_title: "Instance Management",
       active_tab: :instances,
       instances: load_instances(),
       selected_instance: nil,
       lockout_search: "",
       lockout_results: [],
       show_close_modal: false,
       show_lockout_reset_modal: false,
       selected_lockout: nil
     ), layout: {BezgelorPortalWeb.Layouts, :admin}}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Header -->
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold">Instance Management</h1>
        <div class="flex items-center gap-2 text-sm text-base-content/70">
          <span class="loading loading-spinner loading-xs"></span> Auto-refresh every 10s
        </div>
      </div>
      
    <!-- Tabs -->
      <div class="tabs tabs-boxed">
        <button
          class={"tab #{if @active_tab == :instances, do: "tab-active"}"}
          phx-click="switch_tab"
          phx-value-tab="instances"
        >
          <.icon name="hero-building-office-2" class="size-4 mr-2" /> Active Instances
        </button>
        <button
          class={"tab #{if @active_tab == :lockouts, do: "tab-active"}"}
          phx-click="switch_tab"
          phx-value-tab="lockouts"
        >
          <.icon name="hero-clock" class="size-4 mr-2" /> Lockout Management
        </button>
      </div>
      
    <!-- Active Instances Tab -->
      <div :if={@active_tab == :instances} class="space-y-4">
        <!-- Instance Stats -->
        <div class="stats shadow w-full">
          <div class="stat">
            <div class="stat-title">Total Instances</div>
            <div class="stat-value">{length(@instances)}</div>
            <div class="stat-desc">Active dungeon/raid instances</div>
          </div>
          <div class="stat">
            <div class="stat-title">Dungeon Instances</div>
            <div class="stat-value">
              {Enum.count(@instances, &(&1.type == :dungeon))}
            </div>
          </div>
          <div class="stat">
            <div class="stat-title">Raid Instances</div>
            <div class="stat-value">
              {Enum.count(@instances, &(&1.type == :raid))}
            </div>
          </div>
          <div class="stat">
            <div class="stat-title">Total Players</div>
            <div class="stat-value">
              {Enum.sum(Enum.map(@instances, &length(&1.players)))}
            </div>
          </div>
        </div>
        
    <!-- Instances Table -->
        <div class="card bg-base-100 shadow">
          <div class="card-body">
            <h2 class="card-title">Active Instances</h2>

            <div :if={@instances == []} class="text-center py-8 text-base-content/60">
              <.icon name="hero-building-office-2" class="size-12 mx-auto mb-2 opacity-50" />
              <p>No active instances</p>
            </div>

            <div :if={@instances != []} class="overflow-x-auto">
              <table class="table">
                <thead>
                  <tr>
                    <th>Instance</th>
                    <th>Type</th>
                    <th>Players</th>
                    <th>Boss Progress</th>
                    <th>Duration</th>
                    <th>Actions</th>
                  </tr>
                </thead>
                <tbody>
                  <%= for instance <- @instances do %>
                    <tr class="hover">
                      <td>
                        <div class="font-medium">{instance.name}</div>
                        <div class="text-xs text-base-content/60">ID: {instance.id}</div>
                      </td>
                      <td>
                        <span class={"badge #{instance_type_badge(instance.type)}"}>
                          {instance.type |> to_string() |> String.capitalize()}
                        </span>
                      </td>
                      <td>
                        <div class="flex items-center gap-1">
                          <.icon name="hero-users" class="size-4" />
                          {length(instance.players)}/{instance.max_players}
                        </div>
                      </td>
                      <td>
                        <div class="flex items-center gap-2">
                          <progress
                            class="progress progress-primary w-20"
                            value={instance.bosses_killed}
                            max={instance.total_bosses}
                          >
                          </progress>
                          <span class="text-sm">
                            {instance.bosses_killed}/{instance.total_bosses}
                          </span>
                        </div>
                      </td>
                      <td>
                        <span class="text-sm">{format_duration(instance.started_at)}</span>
                      </td>
                      <td>
                        <div class="flex gap-1">
                          <button
                            class="btn btn-ghost btn-xs"
                            phx-click="view_instance"
                            phx-value-id={instance.id}
                          >
                            <.icon name="hero-eye" class="size-4" />
                          </button>
                          <button
                            class="btn btn-ghost btn-xs text-error"
                            phx-click="confirm_close"
                            phx-value-id={instance.id}
                          >
                            <.icon name="hero-x-circle" class="size-4" />
                          </button>
                        </div>
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          </div>
        </div>
        
    <!-- Instance Detail -->
        <div :if={@selected_instance} class="card bg-base-100 shadow">
          <div class="card-body">
            <div class="flex items-center justify-between">
              <h2 class="card-title">{@selected_instance.name}</h2>
              <button class="btn btn-ghost btn-sm" phx-click="close_detail">
                <.icon name="hero-x-mark" class="size-4" />
              </button>
            </div>

            <div class="grid grid-cols-1 md:grid-cols-2 gap-6 mt-4">
              <!-- Instance Info -->
              <div>
                <h3 class="font-semibold mb-2">Instance Information</h3>
                <dl class="space-y-2 text-sm">
                  <div class="flex justify-between">
                    <dt class="text-base-content/70">Instance ID:</dt>
                    <dd class="font-mono">{@selected_instance.id}</dd>
                  </div>
                  <div class="flex justify-between">
                    <dt class="text-base-content/70">Type:</dt>
                    <dd>{@selected_instance.type |> to_string() |> String.capitalize()}</dd>
                  </div>
                  <div class="flex justify-between">
                    <dt class="text-base-content/70">Difficulty:</dt>
                    <dd>{@selected_instance.difficulty || "Normal"}</dd>
                  </div>
                  <div class="flex justify-between">
                    <dt class="text-base-content/70">Started:</dt>
                    <dd>{format_datetime(@selected_instance.started_at)}</dd>
                  </div>
                  <div class="flex justify-between">
                    <dt class="text-base-content/70">Duration:</dt>
                    <dd>{format_duration(@selected_instance.started_at)}</dd>
                  </div>
                </dl>
              </div>
              
    <!-- Boss Status -->
              <div>
                <h3 class="font-semibold mb-2">Boss Status</h3>
                <div class="space-y-2">
                  <%= for boss <- @selected_instance.boss_status do %>
                    <div class="flex items-center justify-between p-2 bg-base-200 rounded">
                      <span class="text-sm">{boss.name}</span>
                      <span class={"badge #{if boss.killed, do: "badge-success", else: "badge-warning"}"}>
                        {if boss.killed, do: "Defeated", else: "Alive"}
                      </span>
                    </div>
                  <% end %>
                </div>
              </div>
            </div>
            
    <!-- Players -->
            <div class="mt-6">
              <h3 class="font-semibold mb-2">Players ({length(@selected_instance.players)})</h3>
              <div class="overflow-x-auto">
                <table class="table table-sm">
                  <thead>
                    <tr>
                      <th>Character</th>
                      <th>Class</th>
                      <th>Level</th>
                      <th>Role</th>
                      <th>Actions</th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= for player <- @selected_instance.players do %>
                      <tr>
                        <td>{player.name}</td>
                        <td>{player.class}</td>
                        <td>{player.level}</td>
                        <td>
                          <span class={"badge badge-sm #{role_badge(player.role)}"}>
                            {player.role}
                          </span>
                        </td>
                        <td>
                          <button
                            class="btn btn-ghost btn-xs"
                            phx-click="teleport_out"
                            phx-value-character={player.id}
                            phx-value-instance={@selected_instance.id}
                          >
                            <.icon name="hero-arrow-right-on-rectangle" class="size-4" /> Teleport Out
                          </button>
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            </div>
            
    <!-- Actions -->
            <div class="mt-6 flex gap-2">
              <button
                class="btn btn-error"
                phx-click="confirm_close"
                phx-value-id={@selected_instance.id}
              >
                <.icon name="hero-x-circle" class="size-4" /> Force Close Instance
              </button>
              <button
                class="btn btn-warning"
                phx-click="teleport_all_out"
                phx-value-id={@selected_instance.id}
              >
                <.icon name="hero-arrow-right-on-rectangle" class="size-4" /> Teleport All Out
              </button>
            </div>
          </div>
        </div>
      </div>
      
    <!-- Lockouts Tab -->
      <div :if={@active_tab == :lockouts} class="space-y-4">
        <!-- Search -->
        <div class="card bg-base-100 shadow">
          <div class="card-body">
            <h2 class="card-title">Search Lockouts</h2>
            <form phx-submit="search_lockouts" class="flex gap-2">
              <input
                type="text"
                name="search"
                value={@lockout_search}
                placeholder="Character name or account email..."
                class="input input-bordered flex-1"
              />
              <button type="submit" class="btn btn-primary">
                <.icon name="hero-magnifying-glass" class="size-4" /> Search
              </button>
            </form>
          </div>
        </div>
        
    <!-- Results -->
        <div :if={@lockout_results != []} class="card bg-base-100 shadow">
          <div class="card-body">
            <div class="flex items-center justify-between mb-4">
              <h2 class="card-title">Lockout Results</h2>
              <button
                class="btn btn-warning btn-sm"
                phx-click="reset_all_lockouts"
                phx-value-character={List.first(@lockout_results).character_id}
              >
                <.icon name="hero-arrow-path" class="size-4" /> Reset All
              </button>
            </div>

            <div class="overflow-x-auto">
              <table class="table">
                <thead>
                  <tr>
                    <th>Instance</th>
                    <th>Type</th>
                    <th>Difficulty</th>
                    <th>Progress</th>
                    <th>Expires</th>
                    <th>Actions</th>
                  </tr>
                </thead>
                <tbody>
                  <%= for lockout <- @lockout_results do %>
                    <tr class="hover">
                      <td>
                        <div class="font-medium">{lockout.instance_name}</div>
                        <div class="text-xs text-base-content/60">
                          {lockout.character_name}
                        </div>
                      </td>
                      <td>
                        <span class={"badge #{instance_type_badge(lockout.type)}"}>
                          {lockout.type |> to_string() |> String.capitalize()}
                        </span>
                      </td>
                      <td>{lockout.difficulty || "Normal"}</td>
                      <td>
                        <div class="flex items-center gap-2">
                          <progress
                            class="progress progress-primary w-20"
                            value={lockout.bosses_killed}
                            max={lockout.total_bosses}
                          >
                          </progress>
                          <span class="text-sm">{lockout.bosses_killed}/{lockout.total_bosses}</span>
                        </div>
                      </td>
                      <td>
                        <span class={if lockout_expired?(lockout), do: "text-error", else: ""}>
                          {format_datetime(lockout.expires_at)}
                        </span>
                      </td>
                      <td>
                        <button
                          class="btn btn-ghost btn-xs text-warning"
                          phx-click="confirm_reset_lockout"
                          phx-value-id={lockout.id}
                        >
                          <.icon name="hero-arrow-path" class="size-4" /> Reset
                        </button>
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          </div>
        </div>

        <div :if={@lockout_search != "" && @lockout_results == []} class="alert">
          <.icon name="hero-information-circle" class="size-5" />
          <span>No lockouts found for "{@lockout_search}"</span>
        </div>
      </div>
      
    <!-- Close Instance Modal -->
      <dialog :if={@show_close_modal} class="modal modal-open">
        <div class="modal-box">
          <h3 class="text-lg font-bold">Force Close Instance</h3>
          <p class="py-4">
            Are you sure you want to force close this instance? All players will be teleported out
            and any unsaved progress may be lost.
          </p>
          <div class="modal-action">
            <button class="btn" phx-click="cancel_close">Cancel</button>
            <button class="btn btn-error" phx-click="close_instance">
              <.icon name="hero-x-circle" class="size-4" /> Force Close
            </button>
          </div>
        </div>
        <form method="dialog" class="modal-backdrop">
          <button phx-click="cancel_close">close</button>
        </form>
      </dialog>
      
    <!-- Reset Lockout Modal -->
      <dialog :if={@show_lockout_reset_modal} class="modal modal-open">
        <div class="modal-box">
          <h3 class="text-lg font-bold">Reset Lockout</h3>
          <p class="py-4">
            Are you sure you want to reset this lockout? The player will be able to enter the
            instance again this week.
          </p>
          <div class="modal-action">
            <button class="btn" phx-click="cancel_reset">Cancel</button>
            <button class="btn btn-warning" phx-click="reset_lockout">
              <.icon name="hero-arrow-path" class="size-4" /> Reset Lockout
            </button>
          </div>
        </div>
        <form method="dialog" class="modal-backdrop">
          <button phx-click="cancel_reset">close</button>
        </form>
      </dialog>
    </div>
    """
  end

  # Event handlers

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, active_tab: String.to_existing_atom(tab))}
  end

  @impl true
  def handle_event("view_instance", %{"id" => id}, socket) do
    instance = Enum.find(socket.assigns.instances, &(&1.id == id))
    {:noreply, assign(socket, selected_instance: instance)}
  end

  @impl true
  def handle_event("close_detail", _, socket) do
    {:noreply, assign(socket, selected_instance: nil)}
  end

  @impl true
  def handle_event("confirm_close", %{"id" => id}, socket) do
    instance = Enum.find(socket.assigns.instances, &(&1.id == id))
    {:noreply, assign(socket, show_close_modal: true, selected_instance: instance)}
  end

  @impl true
  def handle_event("cancel_close", _, socket) do
    {:noreply, assign(socket, show_close_modal: false)}
  end

  @impl true
  def handle_event("close_instance", _, socket) do
    instance = socket.assigns.selected_instance

    case Portal.close_instance(instance.id) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "Instance #{instance.name} closed")
         |> assign(
           show_close_modal: false,
           selected_instance: nil,
           instances: load_instances()
         )}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> put_flash(:error, "Instance not found or already closed")
         |> assign(show_close_modal: false)}
    end
  end

  @impl true
  def handle_event(
        "teleport_out",
        %{"character" => char_id_str, "instance" => _instance_id},
        socket
      ) do
    admin = socket.assigns.current_account

    case Integer.parse(char_id_str) do
      {character_id, ""} ->
        case Portal.teleport_player_out(character_id) do
          :ok ->
            Authorization.log_action(
              admin,
              "instance.teleport_player",
              "character",
              character_id,
              %{}
            )

            {:noreply,
             socket
             |> put_flash(:info, "Player teleported out of instance")
             |> assign(instances: load_instances())}

          {:error, :not_online} ->
            {:noreply, put_flash(socket, :error, "Player is not online")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Invalid character ID")}
    end
  end

  @impl true
  def handle_event("teleport_all_out", %{"id" => instance_id}, socket) do
    admin = socket.assigns.current_account

    case Portal.teleport_all_from_instance(instance_id) do
      {:ok, count} ->
        Authorization.log_action(admin, "instance.teleport_all", "instance", nil, %{
          instance_id: instance_id,
          player_count: count
        })

        {:noreply,
         socket
         |> put_flash(:info, "Teleported #{count} players out of instance")
         |> assign(instances: load_instances())}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Instance not found or has no players")}
    end
  end

  @impl true
  def handle_event("search_lockouts", %{"search" => search}, socket) do
    results = search_lockouts(search)
    {:noreply, assign(socket, lockout_search: search, lockout_results: results)}
  end

  @impl true
  def handle_event("confirm_reset_lockout", %{"id" => id}, socket) do
    lockout = Enum.find(socket.assigns.lockout_results, &(&1.id == id))
    {:noreply, assign(socket, show_lockout_reset_modal: true, selected_lockout: lockout)}
  end

  @impl true
  def handle_event("cancel_reset", _, socket) do
    {:noreply, assign(socket, show_lockout_reset_modal: false, selected_lockout: nil)}
  end

  @impl true
  def handle_event("reset_lockout", _, socket) do
    admin = socket.assigns.current_account
    lockout = socket.assigns.selected_lockout

    case Integer.parse(lockout.id |> to_string() |> String.replace("lock-", "")) do
      {lockout_id, ""} ->
        case Lockouts.reset_lockout(lockout_id) do
          {:ok, _} ->
            Authorization.log_action(admin, "lockout.reset", "lockout", lockout_id, %{
              character_id: lockout.character_id,
              instance_name: lockout.instance_name
            })

            {:noreply,
             socket
             |> put_flash(:info, "Lockout reset for #{lockout.instance_name}")
             |> assign(
               show_lockout_reset_modal: false,
               selected_lockout: nil,
               lockout_results: search_lockouts(socket.assigns.lockout_search)
             )}

          {:error, :not_found} ->
            {:noreply,
             socket
             |> put_flash(:error, "Lockout not found")
             |> assign(show_lockout_reset_modal: false)}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Invalid lockout ID")}
    end
  end

  @impl true
  def handle_event("reset_all_lockouts", %{"character" => char_id_str}, socket) do
    admin = socket.assigns.current_account

    case Integer.parse(char_id_str) do
      {character_id, ""} ->
        {count, _} = Lockouts.reset_character_lockouts(character_id)

        Authorization.log_action(admin, "lockout.reset_all", "character", character_id, %{
          lockouts_cleared: count
        })

        {:noreply,
         socket
         |> put_flash(:info, "Reset #{count} lockouts for character")
         |> assign(lockout_results: search_lockouts(socket.assigns.lockout_search))}

      _ ->
        {:noreply, put_flash(socket, :error, "Invalid character ID")}
    end
  end

  @impl true
  def handle_info(:refresh, socket) do
    {:noreply, assign(socket, instances: load_instances())}
  end

  # Helpers

  defp load_instances do
    # Query actual instances from BezgelorWorld via Portal
    portal_instances = Portal.list_instances()
    zone_instances = Portal.list_zone_instances()

    # Convert Portal data to display format
    instances =
      portal_instances
      |> Enum.map(fn inst ->
        %{
          id: inst[:instance_id] || inst[:id] || "unknown",
          name: inst[:name] || get_instance_name(inst[:zone_id]),
          type: inst[:type] || :dungeon,
          difficulty: inst[:difficulty] || "Normal",
          max_players: inst[:max_players] || 5,
          players: inst[:players] || [],
          bosses_killed: inst[:bosses_killed] || 0,
          total_bosses: inst[:total_bosses] || 1,
          boss_status: inst[:boss_status] || [],
          started_at: inst[:started_at] || DateTime.utc_now()
        }
      end)

    # Add zone instances if they're dungeon/raid type
    zone_dungeon_instances =
      zone_instances
      |> Enum.filter(fn z -> z[:creature_count] > 0 end)
      |> Enum.map(fn z ->
        %{
          id: "zone-#{z.zone_id}-#{z.instance_id}",
          name: get_instance_name(z.zone_id),
          type: :zone,
          difficulty: "Normal",
          max_players: 50,
          players: [],
          bosses_killed: 0,
          total_bosses: 0,
          boss_status: [],
          started_at: z[:started_at] || DateTime.utc_now()
        }
      end)

    instances ++ zone_dungeon_instances
  end

  defp get_instance_name(nil), do: "Unknown Instance"

  defp get_instance_name(zone_id) do
    case BezgelorData.Store.get(:world_location, zone_id) do
      :error -> "Instance #{zone_id}"
      {:ok, data} -> Map.get(data, :name) || Map.get(data, "name") || "Instance #{zone_id}"
    end
  end

  defp search_lockouts(search) when byte_size(search) < 2, do: []

  defp search_lockouts(search) do
    # Search by character name
    case Characters.search_characters(search: search, limit: 1) do
      [character | _] ->
        # Get real lockouts from database
        Lockouts.get_character_lockouts(character.id)
        |> Enum.map(fn lockout ->
          %{
            id: lockout.id,
            character_id: character.id,
            character_name: character.name,
            instance_name: get_instance_name(lockout.instance_definition_id),
            type: String.to_atom(lockout.instance_type),
            difficulty: lockout.difficulty,
            bosses_killed: length(lockout.boss_kills || []),
            total_bosses: get_instance_boss_count(lockout.instance_definition_id),
            expires_at: lockout.expires_at
          }
        end)

      [] ->
        []
    end
  end

  defp get_instance_boss_count(_instance_id) do
    # Would look up from game data
    6
  end

  defp instance_type_badge(:dungeon), do: "badge-info"
  defp instance_type_badge(:raid), do: "badge-secondary"
  defp instance_type_badge(_), do: "badge-ghost"

  defp role_badge("Tank"), do: "badge-primary"
  defp role_badge("Healer"), do: "badge-success"
  defp role_badge("DPS"), do: "badge-warning"
  defp role_badge(_), do: "badge-ghost"

  defp format_duration(started_at) do
    seconds = DateTime.diff(DateTime.utc_now(), started_at, :second)
    hours = div(seconds, 3600)
    minutes = div(rem(seconds, 3600), 60)

    cond do
      hours > 0 -> "#{hours}h #{minutes}m"
      true -> "#{minutes}m"
    end
  end

  defp format_datetime(nil), do: "N/A"

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M")
  end

  defp lockout_expired?(lockout) do
    DateTime.compare(lockout.expires_at, DateTime.utc_now()) == :lt
  end
end
