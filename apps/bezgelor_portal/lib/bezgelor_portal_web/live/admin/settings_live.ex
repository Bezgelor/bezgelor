defmodule BezgelorPortalWeb.Admin.SettingsLive do
  @moduledoc """
  Admin LiveView for server configuration settings.

  Features:
  - Tabbed interface for config sections (Gameplay, Tradeskills, etc.)
  - Inline editing with validation
  - Impact warnings for each setting
  - World server restart with configurable countdown
  """
  use BezgelorPortalWeb, :live_view

  alias BezgelorDb.Authorization
  alias BezgelorWorld.Portal

  @impl true
  def mount(_params, _session, socket) do
    sections = Portal.get_all_settings()
    first_section = sections |> Map.keys() |> List.first() || :gameplay

    {:ok,
     socket
     |> assign(
       page_title: "Server Settings",
       sections: sections,
       active_section: first_section,
       editing: nil,
       edit_value: nil,
       show_restart_modal: false,
       restart_delay: 5,
       player_count: Portal.online_player_count(),
       server_running: Portal.world_server_running?()
     ),
     layout: {BezgelorPortalWeb.Layouts, :admin}}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-bold">Server Settings</h1>
          <p class="text-base-content/70">Configure gameplay and server behavior</p>
        </div>
        <div class="flex items-center gap-2">
          <span class={"badge badge-lg #{if @server_running, do: "badge-success", else: "badge-error"}"}>
            {if @server_running, do: "World Server Online", else: "World Server Offline"}
          </span>
        </div>
      </div>

      <!-- Section Tabs -->
      <div role="tablist" class="tabs tabs-boxed bg-base-100 p-1 w-fit">
        <button
          :for={{section_key, section} <- @sections}
          type="button"
          role="tab"
          class={"tab #{if @active_section == section_key, do: "tab-active"}"}
          phx-click="change_section"
          phx-value-section={section_key}
        >
          {section.label}
        </button>
      </div>

      <!-- Settings Card -->
      <div class="card bg-base-100 shadow">
        <div class="card-body">
          <h2 class="card-title">{@sections[@active_section].label} Settings</h2>

          <div class="overflow-x-auto">
            <table class="table">
              <thead>
                <tr>
                  <th>Setting</th>
                  <th>Value</th>
                  <th>Impact</th>
                  <th class="w-24"></th>
                </tr>
              </thead>
              <tbody>
                <%= for {key, setting} <- @sections[@active_section].settings do %>
                  <tr>
                    <td>
                      <div class="font-medium">{humanize_key(key)}</div>
                      <div class="text-sm text-base-content/60">{setting.description}</div>
                    </td>
                    <td>
                      <%= if @editing == key do %>
                        <.edit_input type={setting.type} value={@edit_value} constraints={Map.get(setting, :constraints, %{})} />
                      <% else %>
                        <.value_display value={setting.value} type={setting.type} />
                      <% end %>
                    </td>
                    <td>
                      <.impact_badge impact={setting.impact} />
                    </td>
                    <td>
                      <%= if @editing == key do %>
                        <div class="flex gap-1">
                          <button type="button" class="btn btn-sm btn-success" phx-click="save_setting">
                            Save
                          </button>
                          <button type="button" class="btn btn-sm btn-ghost" phx-click="cancel_edit">
                            Cancel
                          </button>
                        </div>
                      <% else %>
                        <button
                          type="button"
                          class="btn btn-sm btn-ghost"
                          phx-click="start_edit"
                          phx-value-key={key}
                          phx-value-value={setting.value}
                          phx-value-type={setting.type}
                        >
                          Edit
                        </button>
                      <% end %>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>
      </div>

      <!-- Restart Section -->
      <div class="card bg-base-100 shadow">
        <div class="card-body">
          <h2 class="card-title">Restart World Server</h2>

          <div class="alert alert-warning">
            <svg xmlns="http://www.w3.org/2000/svg" class="stroke-current shrink-0 h-6 w-6" fill="none" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
            </svg>
            <div>
              <h3 class="font-bold">Warning</h3>
              <div class="text-sm">
                Restarting the world server will disconnect all online players.
                They will need to reconnect after the restart completes.
              </div>
            </div>
          </div>

          <div class="flex items-center gap-4 mt-4">
            <div class="form-control">
              <label class="label">
                <span class="label-text">Countdown Delay</span>
              </label>
              <select class="select select-bordered w-32" phx-change="set_restart_delay">
                <option value="5" selected={@restart_delay == 5}>5 seconds</option>
                <option value="10" selected={@restart_delay == 10}>10 seconds</option>
                <option value="30" selected={@restart_delay == 30}>30 seconds</option>
                <option value="60" selected={@restart_delay == 60}>60 seconds</option>
              </select>
            </div>

            <div class="flex-1">
              <div class="text-sm text-base-content/70">
                Currently online: <span class="font-bold">{@player_count}</span> players
              </div>
            </div>

            <button
              type="button"
              class="btn btn-error"
              phx-click="open_restart_modal"
              disabled={not @server_running}
            >
              Restart World Server
            </button>
          </div>
        </div>
      </div>

      <!-- Restart Confirmation Modal -->
      <%= if @show_restart_modal do %>
        <div class="modal modal-open">
          <div class="modal-box">
            <h3 class="font-bold text-lg">Confirm World Server Restart</h3>
            <div class="py-4 space-y-4">
              <div class="alert alert-error">
                <svg xmlns="http://www.w3.org/2000/svg" class="stroke-current shrink-0 h-6 w-6" fill="none" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z" />
                </svg>
                <span>This will disconnect <strong>{@player_count}</strong> online players!</span>
              </div>

              <div class="text-sm">
                <p>Players will see:</p>
                <ol class="list-decimal list-inside mt-2 space-y-1 text-base-content/70">
                  <li>"Server restarting in {@restart_delay} seconds..."</li>
                  <li>"Server restarting now. Please reconnect shortly."</li>
                </ol>
              </div>

              <div class="text-sm text-base-content/70">
                The server will restart after the {@restart_delay} second countdown.
                Estimated downtime: ~30 seconds.
              </div>
            </div>
            <div class="modal-action">
              <button type="button" class="btn btn-ghost" phx-click="close_restart_modal">
                Cancel
              </button>
              <button type="button" class="btn btn-error" phx-click="confirm_restart">
                Restart Now
              </button>
            </div>
          </div>
          <div class="modal-backdrop bg-black/50" phx-click="close_restart_modal"></div>
        </div>
      <% end %>
    </div>
    """
  end

  # Components

  attr :type, :atom, required: true
  attr :value, :any, required: true
  attr :constraints, :map, default: %{}

  defp edit_input(%{type: :boolean} = assigns) do
    ~H"""
    <input
      type="checkbox"
      class="toggle toggle-primary"
      checked={@value}
      phx-click="toggle_boolean"
    />
    """
  end

  defp edit_input(%{type: :integer} = assigns) do
    ~H"""
    <input
      type="number"
      class="input input-bordered input-sm w-24"
      value={@value}
      min={Map.get(@constraints, :min)}
      max={Map.get(@constraints, :max)}
      phx-blur="update_edit_value"
      phx-keyup="update_edit_value"
    />
    """
  end

  defp edit_input(assigns) do
    ~H"""
    <input
      type="text"
      class="input input-bordered input-sm"
      value={@value}
      phx-blur="update_edit_value"
    />
    """
  end

  attr :value, :any, required: true
  attr :type, :atom, required: true

  defp value_display(%{type: :boolean} = assigns) do
    ~H"""
    <span class={"badge #{if @value, do: "badge-success", else: "badge-neutral"}"}>
      {if @value, do: "Enabled", else: "Disabled"}
    </span>
    """
  end

  defp value_display(assigns) do
    ~H"""
    <span class="font-mono">{inspect(@value)}</span>
    """
  end

  attr :impact, :atom, required: true

  defp impact_badge(%{impact: :new_characters_only} = assigns) do
    ~H"""
    <span class="badge badge-warning badge-outline">New Characters Only</span>
    """
  end

  defp impact_badge(%{impact: :requires_restart} = assigns) do
    ~H"""
    <span class="badge badge-error badge-outline">Requires Restart</span>
    """
  end

  defp impact_badge(%{impact: :immediate} = assigns) do
    ~H"""
    <span class="badge badge-success badge-outline">Immediate</span>
    """
  end

  defp impact_badge(assigns) do
    ~H"""
    <span class="badge badge-ghost badge-outline">Unknown</span>
    """
  end

  # Event Handlers

  @impl true
  def handle_event("change_section", %{"section" => section}, socket) do
    {:noreply, assign(socket, active_section: String.to_existing_atom(section), editing: nil)}
  end

  def handle_event("start_edit", %{"key" => key, "value" => value, "type" => type}, socket) do
    parsed_value = parse_value(value, type)
    {:noreply, assign(socket, editing: String.to_existing_atom(key), edit_value: parsed_value)}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, editing: nil, edit_value: nil)}
  end

  def handle_event("toggle_boolean", _params, socket) do
    {:noreply, assign(socket, edit_value: not socket.assigns.edit_value)}
  end

  def handle_event("update_edit_value", %{"value" => value}, socket) do
    {:noreply, assign(socket, edit_value: value)}
  end

  def handle_event("save_setting", _params, socket) do
    section = socket.assigns.active_section
    key = socket.assigns.editing
    value = socket.assigns.edit_value
    admin = socket.assigns.current_account

    case Portal.update_setting(section, key, value) do
      {:ok, old_value} ->
        # Log the change
        Authorization.log_action(
          admin,
          "server.setting_changed",
          "config",
          nil,
          %{section: section, key: key, old_value: old_value, new_value: value}
        )

        # Reload sections
        sections = Portal.get_all_settings()

        {:noreply,
         socket
         |> assign(sections: sections, editing: nil, edit_value: nil)
         |> put_flash(:info, "Setting updated successfully")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to update setting: #{inspect(reason)}")}
    end
  end

  def handle_event("set_restart_delay", %{"value" => delay}, socket) do
    {:noreply, assign(socket, restart_delay: String.to_integer(delay))}
  end

  def handle_event("open_restart_modal", _params, socket) do
    player_count = Portal.online_player_count()
    {:noreply, assign(socket, show_restart_modal: true, player_count: player_count)}
  end

  def handle_event("close_restart_modal", _params, socket) do
    {:noreply, assign(socket, show_restart_modal: false)}
  end

  def handle_event("confirm_restart", _params, socket) do
    admin = socket.assigns.current_account
    delay = socket.assigns.restart_delay
    player_count = socket.assigns.player_count

    case Portal.restart_world_server(delay) do
      {:ok, result} ->
        # Log the restart
        Authorization.log_action(
          admin,
          "server.restart",
          "system",
          nil,
          %{player_count: result.players_affected, delay_seconds: result.delay}
        )

        {:noreply,
         socket
         |> assign(show_restart_modal: false)
         |> put_flash(:info, "World server restart initiated. #{player_count} players will be disconnected in #{delay} seconds.")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(show_restart_modal: false)
         |> put_flash(:error, "Failed to restart server: #{inspect(reason)}")}
    end
  end

  # Helpers

  defp humanize_key(key) do
    key
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp parse_value(value, "boolean") when value in ["true", "false"] do
    value == "true"
  end

  defp parse_value(value, "boolean") when is_boolean(value), do: value

  defp parse_value(value, "integer") when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> value
    end
  end

  defp parse_value(value, "integer") when is_integer(value), do: value
  defp parse_value(value, _type), do: value
end
