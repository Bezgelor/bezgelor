defmodule BezgelorPortalWeb.Admin.BroadcastLive do
  @moduledoc """
  Admin LiveView for sending server-wide broadcast messages.

  Features:
  - Send messages to all online players
  - Message type selection (info, warning, alert)
  - Recent broadcast history
  """
  use BezgelorPortalWeb, :live_view

  alias BezgelorDb.Authorization
  alias BezgelorWorld.Portal

  # Valid message types - using a whitelist to prevent atom table exhaustion
  @valid_message_types %{
    "info" => :info,
    "warning" => :warning,
    "alert" => :alert
  }

  @impl true
  def mount(_params, _session, socket) do
    admin = socket.assigns.current_account
    permissions = Authorization.get_account_permissions(admin)
    permission_keys = Enum.map(permissions, & &1.key)

    {:ok,
     assign(socket,
       page_title: "Broadcast Message",
       permissions: permission_keys,
       message: "",
       message_type: "info",
       recent_broadcasts: [],
       sending: false
     ), layout: {BezgelorPortalWeb.Layouts, :admin}}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-bold">Broadcast Message</h1>
          <p class="text-base-content/70">Send announcements to all online players</p>
        </div>
      </div>
      
    <!-- Broadcast Form -->
      <div class="card bg-base-100 shadow">
        <div class="card-body">
          <h2 class="card-title">New Broadcast</h2>
          <form phx-submit="send_broadcast" class="space-y-4">
            <div class="form-control">
              <label class="label">
                <span class="label-text">Message Type</span>
              </label>
              <div class="flex gap-4">
                <label class="label cursor-pointer gap-2">
                  <input
                    type="radio"
                    name="type"
                    value="info"
                    class="radio radio-info"
                    checked={@message_type == "info"}
                    phx-click="set_type"
                    phx-value-type="info"
                  />
                  <span class="label-text">Info</span>
                </label>
                <label class="label cursor-pointer gap-2">
                  <input
                    type="radio"
                    name="type"
                    value="warning"
                    class="radio radio-warning"
                    checked={@message_type == "warning"}
                    phx-click="set_type"
                    phx-value-type="warning"
                  />
                  <span class="label-text">Warning</span>
                </label>
                <label class="label cursor-pointer gap-2">
                  <input
                    type="radio"
                    name="type"
                    value="alert"
                    class="radio radio-error"
                    checked={@message_type == "alert"}
                    phx-click="set_type"
                    phx-value-type="alert"
                  />
                  <span class="label-text">Alert</span>
                </label>
              </div>
            </div>

            <div class="form-control">
              <label class="label">
                <span class="label-text">Message</span>
                <span class="label-text-alt">{String.length(@message)}/500</span>
              </label>
              <textarea
                name="message"
                class="textarea textarea-bordered h-24"
                placeholder="Enter your broadcast message..."
                maxlength="500"
                phx-change="update_message"
                required
              >{@message}</textarea>
            </div>
            
    <!-- Preview -->
            <div class="form-control">
              <label class="label">
                <span class="label-text">Preview</span>
              </label>
              <div class={"alert #{type_alert_class(@message_type)}"}>
                <.icon name={type_icon(@message_type)} class="size-5" />
                <span>
                  {if @message == "", do: "Your message will appear here...", else: @message}
                </span>
              </div>
            </div>

            <div class="card-actions justify-end">
              <button
                type="submit"
                class="btn btn-primary"
                disabled={@sending || String.length(@message) == 0}
              >
                <%= if @sending do %>
                  <span class="loading loading-spinner loading-sm"></span> Sending...
                <% else %>
                  <.icon name="hero-megaphone" class="size-4" /> Send Broadcast
                <% end %>
              </button>
            </div>
          </form>
        </div>
      </div>
      
    <!-- Recent Broadcasts -->
      <div class="card bg-base-100 shadow">
        <div class="card-body">
          <h2 class="card-title">Recent Broadcasts</h2>
          <%= if Enum.empty?(@recent_broadcasts) do %>
            <p class="text-base-content/50 py-4">No broadcasts sent yet this session</p>
          <% else %>
            <div class="space-y-3 mt-2">
              <div
                :for={broadcast <- @recent_broadcasts}
                class={"alert #{type_alert_class(broadcast.type)} py-2"}
              >
                <.icon name={type_icon(broadcast.type)} class="size-4" />
                <div class="flex-1">
                  <p>{broadcast.message}</p>
                  <p class="text-xs opacity-70">{broadcast.sent_at}</p>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("set_type", %{"type" => type}, socket) do
    {:noreply, assign(socket, message_type: type)}
  end

  @impl true
  def handle_event("update_message", %{"message" => message}, socket) do
    {:noreply, assign(socket, message: message)}
  end

  @impl true
  def handle_event("send_broadcast", %{"message" => message}, socket) do
    admin = socket.assigns.current_account
    type = socket.assigns.message_type

    socket = assign(socket, sending: true)

    # Send via Portal to world server - use whitelist to prevent atom exhaustion
    type_atom = Map.get(@valid_message_types, type, :info)
    :ok = Portal.broadcast_message(message, type_atom)

    Authorization.log_action(admin, "broadcast.send", "system", nil, %{
      message: message,
      type: type
    })

    broadcast = %{
      message: message,
      type: type,
      sent_at: Calendar.strftime(DateTime.utc_now(), "%H:%M:%S")
    }

    {:noreply,
     socket
     |> put_flash(:info, "Broadcast sent successfully")
     |> assign(
       message: "",
       sending: false,
       recent_broadcasts: [broadcast | Enum.take(socket.assigns.recent_broadcasts, 9)]
     )}
  end

  defp type_alert_class("info"), do: "alert-info"
  defp type_alert_class("warning"), do: "alert-warning"
  defp type_alert_class("alert"), do: "alert-error"
  defp type_alert_class(_), do: "alert-info"

  defp type_icon("info"), do: "hero-information-circle"
  defp type_icon("warning"), do: "hero-exclamation-triangle"
  defp type_icon("alert"), do: "hero-exclamation-circle"
  defp type_icon(_), do: "hero-information-circle"
end
