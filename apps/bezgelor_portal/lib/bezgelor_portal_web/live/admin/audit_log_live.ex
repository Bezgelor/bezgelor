defmodule BezgelorPortalWeb.Admin.AuditLogLive do
  @moduledoc """
  Admin LiveView for viewing audit log history.

  Features:
  - Filterable by admin, action type, target, date range
  - Paginated results
  - Detail expansion for JSON details
  - Export to CSV/JSON
  """
  use BezgelorPortalWeb, :live_view

  alias BezgelorDb.Authorization

  @per_page 50

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Audit Log",
       entries: [],
       page: 1,
       has_more: false,
       # Filters
       admin_id: nil,
       action_filter: "",
       target_type: nil,
       date_from: nil,
       date_to: nil,
       # UI state
       expanded_entry: nil
     ),
     layout: {BezgelorPortalWeb.Layouts, :admin}}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    admin_id = parse_int(params["admin_id"])
    action_filter = params["action"] || ""
    target_type = if params["target_type"] && params["target_type"] != "", do: params["target_type"], else: nil
    date_from = parse_date(params["from"])
    date_to = parse_date(params["to"])
    page = String.to_integer(params["page"] || "1")

    socket =
      socket
      |> assign(
        admin_id: admin_id,
        action_filter: action_filter,
        target_type: target_type,
        date_from: date_from,
        date_to: date_to,
        page: page
      )
      |> load_entries()

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-bold">Audit Log</h1>
          <p class="text-base-content/70">View admin action history</p>
        </div>
        <div class="flex gap-2">
          <button type="button" class="btn btn-outline btn-sm" phx-click="export_csv">
            <.icon name="hero-document-arrow-down" class="size-4" />
            Export CSV
          </button>
          <button type="button" class="btn btn-outline btn-sm" phx-click="export_json">
            <.icon name="hero-code-bracket" class="size-4" />
            Export JSON
          </button>
        </div>
      </div>

      <!-- Filters -->
      <div class="card bg-base-100 shadow">
        <div class="card-body">
          <form phx-submit="filter" class="flex flex-wrap gap-4 items-end">
            <div class="form-control min-w-[200px]">
              <label class="label">
                <span class="label-text">Admin</span>
              </label>
              <input
                type="text"
                name="admin_id"
                value={@admin_id || ""}
                placeholder="Admin ID"
                class="input input-bordered input-sm"
              />
            </div>

            <div class="form-control min-w-[200px]">
              <label class="label">
                <span class="label-text">Action</span>
              </label>
              <input
                type="text"
                name="action"
                value={@action_filter}
                placeholder="e.g., user.*, character.set_level"
                class="input input-bordered input-sm"
              />
            </div>

            <div class="form-control min-w-[150px]">
              <label class="label">
                <span class="label-text">Target Type</span>
              </label>
              <select name="target_type" class="select select-bordered select-sm">
                <option value="">All</option>
                <option value="account" selected={@target_type == "account"}>Account</option>
                <option value="character" selected={@target_type == "character"}>Character</option>
                <option value="guild" selected={@target_type == "guild"}>Guild</option>
                <option value="system" selected={@target_type == "system"}>System</option>
              </select>
            </div>

            <div class="form-control">
              <label class="label">
                <span class="label-text">From</span>
              </label>
              <input
                type="date"
                name="from"
                value={format_date(@date_from)}
                class="input input-bordered input-sm"
              />
            </div>

            <div class="form-control">
              <label class="label">
                <span class="label-text">To</span>
              </label>
              <input
                type="date"
                name="to"
                value={format_date(@date_to)}
                class="input input-bordered input-sm"
              />
            </div>

            <button type="submit" class="btn btn-primary btn-sm">
              <.icon name="hero-funnel" class="size-4" />
              Filter
            </button>

            <.link
              :if={has_filters?(assigns)}
              patch={~p"/admin/audit-log"}
              class="btn btn-ghost btn-sm"
            >
              Clear
            </.link>
          </form>
        </div>
      </div>

      <!-- Results -->
      <div class="card bg-base-100 shadow">
        <div class="overflow-x-auto">
          <table class="table">
            <thead>
              <tr>
                <th class="w-8"></th>
                <th>Timestamp</th>
                <th>Admin</th>
                <th>Action</th>
                <th>Target</th>
                <th>IP Address</th>
              </tr>
            </thead>
            <tbody>
              <%= if Enum.empty?(@entries) do %>
                <tr>
                  <td colspan="6" class="text-center py-8 text-base-content/50">
                    No audit log entries found
                  </td>
                </tr>
              <% else %>
                <%= for entry <- @entries do %>
                  <tr class="hover cursor-pointer" phx-click="toggle_expand" phx-value-id={entry.id}>
                    <td>
                      <.icon
                        name={if @expanded_entry == entry.id, do: "hero-chevron-down", else: "hero-chevron-right"}
                        class="size-4"
                      />
                    </td>
                    <td class="text-sm whitespace-nowrap">
                      {format_datetime(entry.inserted_at)}
                    </td>
                    <td>
                      <.link
                        navigate={~p"/admin/users/#{entry.admin_account_id}"}
                        class="link link-primary"
                                             >
                        {entry.admin_account.email}
                      </.link>
                    </td>
                    <td>
                      <span class="badge badge-ghost">{entry.action}</span>
                    </td>
                    <td>
                      <%= if entry.target_type && entry.target_id do %>
                        <.target_link type={entry.target_type} id={entry.target_id} />
                      <% else %>
                        <span class="text-base-content/50">-</span>
                      <% end %>
                    </td>
                    <td class="font-mono text-sm text-base-content/70">
                      {entry.ip_address || "-"}
                    </td>
                  </tr>
                  <!-- Expanded details row -->
                  <tr :if={@expanded_entry == entry.id} class="bg-base-200">
                    <td colspan="6" class="p-4">
                      <div class="text-sm">
                        <h4 class="font-semibold mb-2">Details</h4>
                        <%= if entry.details && map_size(entry.details) > 0 do %>
                          <pre class="bg-base-300 p-3 rounded-lg overflow-x-auto text-xs"><code>{Jason.encode!(entry.details, pretty: true)}</code></pre>
                        <% else %>
                          <p class="text-base-content/50">No additional details</p>
                        <% end %>
                      </div>
                    </td>
                  </tr>
                <% end %>
              <% end %>
            </tbody>
          </table>
        </div>

        <!-- Pagination -->
        <div :if={@page > 1 or @has_more} class="card-body pt-0">
          <div class="flex justify-center gap-2">
            <.link
              :if={@page > 1}
              patch={pagination_path(assigns, @page - 1)}
              class="btn btn-sm"
            >
              Previous
            </.link>
            <span class="btn btn-sm btn-ghost">Page {@page}</span>
            <.link
              :if={@has_more}
              patch={pagination_path(assigns, @page + 1)}
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

  attr :type, :string, required: true
  attr :id, :integer, required: true

  defp target_link(%{type: "account"} = assigns) do
    ~H"""
    <.link navigate={~p"/admin/users/#{@id}"} class="link link-primary">
      Account #{@id}
    </.link>
    """
  end

  defp target_link(%{type: "character"} = assigns) do
    ~H"""
    <.link navigate={~p"/admin/characters/#{@id}"} class="link link-primary">
      Character #{@id}
    </.link>
    """
  end

  defp target_link(assigns) do
    ~H"""
    <span>{String.capitalize(@type)} #{@id}</span>
    """
  end

  # Event handlers

  @impl true
  def handle_event("filter", params, socket) do
    path = build_filter_path(params)
    {:noreply, push_patch(socket, to: path)}
  end

  @impl true
  def handle_event("toggle_expand", %{"id" => id_str}, socket) do
    id = String.to_integer(id_str)
    new_expanded = if socket.assigns.expanded_entry == id, do: nil, else: id
    {:noreply, assign(socket, expanded_entry: new_expanded)}
  end

  @impl true
  def handle_event("export_csv", _, socket) do
    entries = get_all_filtered_entries(socket.assigns)
    csv = entries_to_csv(entries)

    {:noreply,
     socket
     |> push_event("download", %{
       filename: "audit_log_#{Date.utc_today()}.csv",
       content: csv,
       content_type: "text/csv"
     })}
  end

  @impl true
  def handle_event("export_json", _, socket) do
    entries = get_all_filtered_entries(socket.assigns)
    json = Jason.encode!(Enum.map(entries, &entry_to_map/1), pretty: true)

    {:noreply,
     socket
     |> push_event("download", %{
       filename: "audit_log_#{Date.utc_today()}.json",
       content: json,
       content_type: "application/json"
     })}
  end

  # Helpers

  defp load_entries(socket) do
    %{
      admin_id: admin_id,
      action_filter: action_filter,
      target_type: target_type,
      date_from: date_from,
      date_to: date_to,
      page: page
    } = socket.assigns

    opts =
      [limit: @per_page + 1, offset: (page - 1) * @per_page]
      |> maybe_add_opt(:admin_id, admin_id)
      |> maybe_add_opt(:action, non_empty(action_filter))
      |> maybe_add_opt(:target_type, target_type)
      |> maybe_add_opt(:from, date_to_datetime(date_from, :start))
      |> maybe_add_opt(:to, date_to_datetime(date_to, :end))

    entries = Authorization.list_audit_log(opts)
    {entries, has_more} = maybe_pop_extra(entries, @per_page)

    assign(socket, entries: entries, has_more: has_more)
  end

  defp get_all_filtered_entries(assigns) do
    opts =
      [limit: 10_000]
      |> maybe_add_opt(:admin_id, assigns.admin_id)
      |> maybe_add_opt(:action, non_empty(assigns.action_filter))
      |> maybe_add_opt(:target_type, assigns.target_type)
      |> maybe_add_opt(:from, date_to_datetime(assigns.date_from, :start))
      |> maybe_add_opt(:to, date_to_datetime(assigns.date_to, :end))

    Authorization.list_audit_log(opts)
  end

  defp maybe_add_opt(opts, _key, nil), do: opts
  defp maybe_add_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp non_empty(""), do: nil
  defp non_empty(str), do: str

  defp date_to_datetime(nil, _), do: nil
  defp date_to_datetime(date, :start), do: DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
  defp date_to_datetime(date, :end), do: DateTime.new!(date, ~T[23:59:59], "Etc/UTC")

  defp maybe_pop_extra(list, limit) when length(list) > limit do
    {Enum.take(list, limit), true}
  end

  defp maybe_pop_extra(list, _limit), do: {list, false}

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil
  defp parse_int(str) do
    case Integer.parse(str) do
      {i, ""} -> i
      _ -> nil
    end
  end

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil
  defp parse_date(str) do
    case Date.from_iso8601(str) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp format_date(nil), do: ""
  defp format_date(date), do: Date.to_iso8601(date)

  defp format_datetime(nil), do: "-"
  defp format_datetime(datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")

  defp has_filters?(assigns) do
    assigns.admin_id || assigns.action_filter != "" ||
      assigns.target_type || assigns.date_from || assigns.date_to
  end

  defp build_filter_path(params) do
    query =
      %{}
      |> maybe_put("admin_id", params["admin_id"])
      |> maybe_put("action", params["action"])
      |> maybe_put("target_type", params["target_type"])
      |> maybe_put("from", params["from"])
      |> maybe_put("to", params["to"])

    if map_size(query) == 0 do
      ~p"/admin/audit-log"
    else
      ~p"/admin/audit-log?#{query}"
    end
  end

  defp pagination_path(assigns, page) do
    query =
      %{}
      |> maybe_put("admin_id", assigns.admin_id)
      |> maybe_put("action", assigns.action_filter)
      |> maybe_put("target_type", assigns.target_type)
      |> maybe_put("from", format_date(assigns.date_from))
      |> maybe_put("to", format_date(assigns.date_to))
      |> Map.put("page", page)

    ~p"/admin/audit-log?#{query}"
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp entries_to_csv(entries) do
    header = "Timestamp,Admin ID,Admin Email,Action,Target Type,Target ID,IP Address,Details\n"

    rows =
      Enum.map(entries, fn entry ->
        [
          format_datetime(entry.inserted_at),
          entry.admin_account_id,
          entry.admin_account.email,
          entry.action,
          entry.target_type || "",
          entry.target_id || "",
          entry.ip_address || "",
          if(entry.details, do: Jason.encode!(entry.details), else: "")
        ]
        |> Enum.map(&csv_escape/1)
        |> Enum.join(",")
      end)
      |> Enum.join("\n")

    header <> rows
  end

  defp csv_escape(nil), do: ""
  defp csv_escape(value) when is_integer(value), do: Integer.to_string(value)
  defp csv_escape(value) when is_binary(value) do
    if String.contains?(value, [",", "\"", "\n"]) do
      "\"#{String.replace(value, "\"", "\"\"")}\""
    else
      value
    end
  end

  defp entry_to_map(entry) do
    %{
      id: entry.id,
      timestamp: DateTime.to_iso8601(entry.inserted_at),
      admin_id: entry.admin_account_id,
      admin_email: entry.admin_account.email,
      action: entry.action,
      target_type: entry.target_type,
      target_id: entry.target_id,
      ip_address: entry.ip_address,
      details: entry.details
    }
  end
end
