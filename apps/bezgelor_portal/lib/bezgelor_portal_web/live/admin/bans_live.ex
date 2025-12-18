defmodule BezgelorPortalWeb.Admin.BansLive do
  @moduledoc """
  Admin LiveView for managing bans and suspensions.

  Features:
  - List all active and historical bans/suspensions
  - Search by account email
  - Quick unban action
  - Filter by active only
  """
  use BezgelorPortalWeb, :live_view

  alias BezgelorDb.{Accounts, Authorization}
  alias BezgelorDb.Schema.AccountSuspension

  @per_page 50

  @impl true
  def mount(_params, _session, socket) do
    admin = socket.assigns.current_account
    permissions = Authorization.get_account_permissions(admin)
    permission_keys = Enum.map(permissions, & &1.key)

    {:ok,
     assign(socket,
       page_title: "Bans & Suspensions",
       permissions: permission_keys,
       search_query: "",
       active_only: true,
       suspensions: [],
       page: 1,
       has_more: false,
       total_active: Accounts.count_suspensions(active_only: true)
     ),
     layout: {BezgelorPortalWeb.Layouts, :admin}}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    search_query = params["q"] || ""
    active_only = params["active"] != "false"
    page = String.to_integer(params["page"] || "1")

    socket =
      socket
      |> assign(search_query: search_query, active_only: active_only, page: page)
      |> load_suspensions()

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-bold">Bans & Suspensions</h1>
          <p class="text-base-content/70">Manage account bans and temporary suspensions</p>
        </div>
        <div class="stats shadow bg-base-100">
          <div class="stat py-2 px-4 place-items-center">
            <div class="stat-title text-xs">Active</div>
            <div class="stat-value text-lg text-error">{@total_active}</div>
          </div>
        </div>
      </div>

      <!-- Filters -->
      <div class="card bg-base-100 shadow">
        <div class="card-body">
          <form phx-submit="search" class="flex flex-wrap gap-4 items-end">
            <div class="form-control flex-1 min-w-[200px]">
              <label class="label">
                <span class="label-text">Search by Email</span>
              </label>
              <input
                type="text"
                name="q"
                value={@search_query}
                placeholder="Enter account email..."
                class="input input-bordered w-full"
                phx-debounce="300"
              />
            </div>

            <div class="form-control">
              <label class="label cursor-pointer gap-2">
                <span class="label-text">Active only</span>
                <input
                  type="checkbox"
                  name="active"
                  class="toggle toggle-primary"
                  checked={@active_only}
                  phx-click="toggle_active"
                />
              </label>
            </div>

            <button type="submit" class="btn btn-primary">
              <.icon name="hero-magnifying-glass" class="size-4" />
              Search
            </button>
          </form>
        </div>
      </div>

      <!-- Results -->
      <div class="card bg-base-100 shadow">
        <div class="overflow-x-auto">
          <table class="table">
            <thead>
              <tr>
                <th>Account</th>
                <th>Type</th>
                <th>Reason</th>
                <th>Started</th>
                <th>Expires</th>
                <th>Status</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              <%= if Enum.empty?(@suspensions) do %>
                <tr>
                  <td colspan="7" class="text-center py-8 text-base-content/50">
                    <%= if @active_only do %>
                      No active bans or suspensions
                    <% else %>
                      No bans or suspensions found
                    <% end %>
                  </td>
                </tr>
              <% else %>
                <tr :for={suspension <- @suspensions} class="hover">
                  <td>
                    <.link navigate={~p"/admin/users/#{suspension.account_id}"} class="link link-hover">
                      {suspension.account.email}
                    </.link>
                  </td>
                  <td>
                    <.type_badge suspension={suspension} />
                  </td>
                  <td class="max-w-xs truncate" title={suspension.reason}>
                    {suspension.reason || "No reason provided"}
                  </td>
                  <td class="text-sm">{format_datetime(suspension.start_time)}</td>
                  <td class="text-sm">
                    <%= if suspension.end_time do %>
                      {format_datetime(suspension.end_time)}
                    <% else %>
                      <span class="text-error font-medium">Never</span>
                    <% end %>
                  </td>
                  <td>
                    <.status_badge suspension={suspension} />
                  </td>
                  <td>
                    <button
                      :if={"users.unban" in @permissions && AccountSuspension.active?(suspension)}
                      type="button"
                      class="btn btn-success btn-sm"
                      phx-click="unban"
                      phx-value-id={suspension.id}
                      data-confirm="Remove this ban/suspension?"
                    >
                      <.icon name="hero-check-circle" class="size-4" />
                      Unban
                    </button>
                    <span :if={!AccountSuspension.active?(suspension)} class="text-base-content/50 text-sm">
                      Expired
                    </span>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>

        <!-- Pagination -->
        <div :if={@page > 1 or @has_more} class="card-body pt-0">
          <div class="flex justify-center gap-2">
            <.link
              :if={@page > 1}
              patch={~p"/admin/users/bans?#{pagination_params(@search_query, @active_only, @page - 1)}"}
              class="btn btn-sm"
            >
              Previous
            </.link>
            <span class="btn btn-sm btn-ghost">Page {@page}</span>
            <.link
              :if={@has_more}
              patch={~p"/admin/users/bans?#{pagination_params(@search_query, @active_only, @page + 1)}"}
              class="btn btn-sm"
            >
              Next
            </.link>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :suspension, :map, required: true

  defp type_badge(assigns) do
    ~H"""
    <%= if AccountSuspension.permanent?(@suspension) do %>
      <span class="badge badge-error">Permanent Ban</span>
    <% else %>
      <span class="badge badge-warning">Suspension</span>
    <% end %>
    """
  end

  attr :suspension, :map, required: true

  defp status_badge(assigns) do
    ~H"""
    <%= if AccountSuspension.active?(@suspension) do %>
      <span class="badge badge-error badge-sm">Active</span>
    <% else %>
      <span class="badge badge-ghost badge-sm">Expired</span>
    <% end %>
    """
  end

  @impl true
  def handle_event("search", %{"q" => query}, socket) do
    active = if socket.assigns.active_only, do: "true", else: "false"
    {:noreply, push_patch(socket, to: ~p"/admin/users/bans?#{%{q: query, active: active}}")}
  end

  @impl true
  def handle_event("toggle_active", _, socket) do
    new_active = !socket.assigns.active_only
    active = if new_active, do: "true", else: "false"
    {:noreply, push_patch(socket, to: ~p"/admin/users/bans?#{%{q: socket.assigns.search_query, active: active}}")}
  end

  @impl true
  def handle_event("unban", %{"id" => id_str}, socket) do
    admin = socket.assigns.current_account
    id = String.to_integer(id_str)

    suspension = Enum.find(socket.assigns.suspensions, &(&1.id == id))

    if suspension do
      case Accounts.remove_suspension(suspension) do
        {:ok, _} ->
          Authorization.log_action(admin, "user.unban", "account", suspension.account_id, %{
            original_reason: suspension.reason
          })

          {:noreply,
           socket
           |> put_flash(:info, "Ban/suspension removed for #{suspension.account.email}")
           |> load_suspensions()
           |> assign(total_active: Accounts.count_suspensions(active_only: true))}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to remove ban/suspension")}
      end
    else
      {:noreply, put_flash(socket, :error, "Suspension not found")}
    end
  end

  defp load_suspensions(socket) do
    %{search_query: search, active_only: active_only, page: page} = socket.assigns
    offset = (page - 1) * @per_page

    suspensions = Accounts.list_suspensions(
      active_only: active_only,
      search: search,
      limit: @per_page + 1,
      offset: offset
    )

    {suspensions, has_more} =
      if length(suspensions) > @per_page do
        {Enum.take(suspensions, @per_page), true}
      else
        {suspensions, false}
      end

    assign(socket, suspensions: suspensions, has_more: has_more)
  end

  defp format_datetime(nil), do: "-"
  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M")
  end

  defp pagination_params(query, active_only, page) do
    params = %{q: query, active: if(active_only, do: "true", else: "false")}
    if page > 1, do: Map.put(params, :page, page), else: params
  end
end
