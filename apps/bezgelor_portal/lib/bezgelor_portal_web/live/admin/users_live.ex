defmodule BezgelorPortalWeb.Admin.UsersLive do
  @moduledoc """
  Admin LiveView for user management.

  Provides search and listing of user accounts with quick actions.
  """
  use BezgelorPortalWeb, :live_view

  alias BezgelorDb.Accounts
  alias BezgelorPortal.GameData

  @per_page 25

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "User Management",
       search_type: "email",
       search_query: "",
       users: [],
       character_results: [],
       page: 1,
       has_more: false
     ),
     layout: {BezgelorPortalWeb.Layouts, :admin}}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    search_type = params["type"] || "email"
    search_query = params["q"] || ""
    page = String.to_integer(params["page"] || "1")

    socket =
      socket
      |> assign(search_type: search_type, search_query: search_query, page: page)
      |> perform_search()

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-bold">User Management</h1>
          <p class="text-base-content/70">Search and manage user accounts</p>
        </div>
      </div>

      <!-- Search Form -->
      <div class="card bg-base-100 shadow">
        <div class="card-body">
          <form phx-submit="search" class="flex flex-wrap gap-4 items-end">
            <div class="form-control">
              <label class="label">
                <span class="label-text">Search By</span>
              </label>
              <select name="type" class="select select-bordered" value={@search_type}>
                <option value="email" selected={@search_type == "email"}>Email</option>
                <option value="character" selected={@search_type == "character"}>Character Name</option>
                <option value="id" selected={@search_type == "id"}>Account ID</option>
              </select>
            </div>

            <div class="form-control flex-1 min-w-[200px]">
              <label class="label">
                <span class="label-text">Search Query</span>
              </label>
              <input
                type="text"
                name="q"
                value={@search_query}
                placeholder={search_placeholder(@search_type)}
                class="input input-bordered w-full"
                phx-debounce="300"
              />
            </div>

            <button type="submit" class="btn btn-primary">
              <.icon name="hero-magnifying-glass" class="size-4" />
              Search
            </button>
          </form>
        </div>
      </div>

      <!-- Results -->
      <%= if @search_type == "character" and length(@character_results) > 0 do %>
        <.character_results_table results={@character_results} />
      <% else %>
        <.users_table users={@users} has_more={@has_more} page={@page} search_type={@search_type} search_query={@search_query} />
      <% end %>
    </div>
    """
  end

  attr :users, :list, required: true
  attr :has_more, :boolean, required: true
  attr :page, :integer, required: true
  attr :search_type, :string, required: true
  attr :search_query, :string, required: true

  defp users_table(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow">
      <div class="overflow-x-auto">
        <table class="table">
          <thead>
            <tr>
              <th>ID</th>
              <th>Email</th>
              <th>Characters</th>
              <th>Status</th>
              <th>Registered</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            <%= if Enum.empty?(@users) do %>
              <tr>
                <td colspan="6" class="text-center py-8 text-base-content/50">
                  <%= if @search_query == "" do %>
                    Enter a search query to find users
                  <% else %>
                    No users found matching your search
                  <% end %>
                </td>
              </tr>
            <% else %>
              <tr :for={user <- @users} class="hover">
                <td class="font-mono text-sm">{user.id}</td>
                <td>
                  <div class="flex items-center gap-2">
                    <span>{user.email}</span>
                    <span :if={user.email_verified_at} class="badge badge-success badge-xs" title="Email verified">
                      <.icon name="hero-check-micro" class="size-3" />
                    </span>
                    <span :if={user.totp_enabled_at} class="badge badge-info badge-xs" title="2FA enabled">
                      <.icon name="hero-shield-check-micro" class="size-3" />
                    </span>
                    <span :if={user.discord_id} class="badge badge-primary badge-xs" title={"Discord: #{user.discord_username}"}>
                      Discord
                    </span>
                  </div>
                </td>
                <td>{user.character_count}</td>
                <td>
                  <.status_badge deleted_at={user.deleted_at} />
                </td>
                <td class="text-sm text-base-content/70">
                  {format_date(user.inserted_at)}
                </td>
                <td>
                  <.link navigate={~p"/admin/users/#{user.id}"} class="btn btn-ghost btn-sm">
                    <.icon name="hero-eye" class="size-4" />
                    View
                  </.link>
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
            patch={~p"/admin/users?#{pagination_params(@search_type, @search_query, @page - 1)}"}
            class="btn btn-sm"
          >
            Previous
          </.link>
          <span class="btn btn-sm btn-ghost">Page {@page}</span>
          <.link
            :if={@has_more}
            patch={~p"/admin/users?#{pagination_params(@search_type, @search_query, @page + 1)}"}
            class="btn btn-sm"
          >
            Next
          </.link>
        </div>
      </div>
    </div>
    """
  end

  attr :results, :list, required: true

  defp character_results_table(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow">
      <div class="overflow-x-auto">
        <table class="table">
          <thead>
            <tr>
              <th>Character</th>
              <th>Level</th>
              <th>Class</th>
              <th>Account Email</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={result <- @results} class="hover">
              <td class="font-semibold">{result.character_name}</td>
              <td>{result.character_level}</td>
              <td>
                <span style={"color: #{GameData.class_color(result.character_class)}"}>
                  {GameData.class_name(result.character_class)}
                </span>
              </td>
              <td>{result.account_email}</td>
              <td>
                <div class="flex gap-2">
                  <.link navigate={~p"/admin/users/#{result.account_id}"} class="btn btn-ghost btn-sm">
                    <.icon name="hero-user" class="size-4" />
                    Account
                  </.link>
                  <.link navigate={~p"/admin/characters/#{result.character_id}"} class="btn btn-ghost btn-sm">
                    <.icon name="hero-user-group" class="size-4" />
                    Character
                  </.link>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  attr :deleted_at, :any, required: true

  defp status_badge(assigns) do
    ~H"""
    <%= if @deleted_at do %>
      <span class="badge badge-error">Deleted</span>
    <% else %>
      <span class="badge badge-success">Active</span>
    <% end %>
    """
  end

  @impl true
  def handle_event("search", %{"type" => type, "q" => query}, socket) do
    {:noreply, push_patch(socket, to: ~p"/admin/users?#{pagination_params(type, query, 1)}")}
  end

  defp perform_search(socket) do
    %{search_type: type, search_query: query, page: page} = socket.assigns
    offset = (page - 1) * @per_page

    case {type, query} do
      {_, ""} ->
        assign(socket, users: [], character_results: [], has_more: false)

      {"id", id_string} ->
        case Integer.parse(id_string) do
          {id, ""} ->
            users =
              case Accounts.get_by_id(id) do
                nil -> []
                account ->
                  # Convert to map format matching list_accounts_with_character_counts
                  [%{
                    id: account.id,
                    email: account.email,
                    email_verified_at: account.email_verified_at,
                    totp_enabled_at: account.totp_enabled_at,
                    discord_id: account.discord_id,
                    discord_username: account.discord_username,
                    deleted_at: account.deleted_at,
                    inserted_at: account.inserted_at,
                    character_count: 0  # Will be populated if needed
                  }]
              end
            assign(socket, users: users, character_results: [], has_more: false)

          _ ->
            assign(socket, users: [], character_results: [], has_more: false)
        end

      {"email", search} ->
        users = Accounts.list_accounts_with_character_counts(
          search: search,
          limit: @per_page + 1,
          offset: offset
        )

        {users, has_more} = maybe_pop_extra(users, @per_page)
        assign(socket, users: users, character_results: [], has_more: has_more)

      {"character", search} ->
        results = Accounts.search_accounts_by_character(search, limit: @per_page + 1, offset: offset)
        {results, has_more} = maybe_pop_extra(results, @per_page)
        assign(socket, users: [], character_results: results, has_more: has_more)
    end
  end

  defp maybe_pop_extra(list, limit) when length(list) > limit do
    {Enum.take(list, limit), true}
  end

  defp maybe_pop_extra(list, _limit), do: {list, false}

  defp search_placeholder("email"), do: "Enter email address..."
  defp search_placeholder("character"), do: "Enter character name..."
  defp search_placeholder("id"), do: "Enter account ID..."

  defp format_date(nil), do: "-"
  defp format_date(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d")
  end

  defp pagination_params(type, query, page) do
    params = %{type: type, q: query}
    if page > 1, do: Map.put(params, :page, page), else: params
  end
end
