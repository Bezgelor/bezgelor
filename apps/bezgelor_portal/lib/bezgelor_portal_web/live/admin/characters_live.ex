defmodule BezgelorPortalWeb.Admin.CharactersLive do
  @moduledoc """
  Admin LiveView for character management.

  Provides search and listing of characters with links to detail views.
  """
  use BezgelorPortalWeb, :live_view

  alias BezgelorDb.Characters
  alias BezgelorPortal.GameData

  @per_page 50

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Character Management",
       search_query: "",
       include_deleted: false,
       characters: [],
       page: 1,
       has_more: false
     ),
     layout: {BezgelorPortalWeb.Layouts, :admin}}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    search_query = params["q"] || ""
    include_deleted = params["deleted"] == "true"
    page = String.to_integer(params["page"] || "1")

    socket =
      socket
      |> assign(search_query: search_query, include_deleted: include_deleted, page: page)
      |> perform_search()

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-bold">Character Management</h1>
          <p class="text-base-content/70">Search and manage characters</p>
        </div>
      </div>

      <!-- Search Form -->
      <div class="card bg-base-100 shadow">
        <div class="card-body">
          <form phx-submit="search" class="flex flex-wrap gap-4 items-end">
            <div class="form-control flex-1 min-w-[200px]">
              <label class="label">
                <span class="label-text">Character Name</span>
              </label>
              <input
                type="text"
                name="q"
                value={@search_query}
                placeholder="Enter character name..."
                class="input input-bordered w-full"
                phx-debounce="300"
              />
            </div>

            <div class="form-control">
              <label class="label cursor-pointer gap-2">
                <input
                  type="checkbox"
                  name="deleted"
                  class="checkbox"
                  checked={@include_deleted}
                />
                <span class="label-text">Include deleted</span>
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
                <th>Name</th>
                <th>Level</th>
                <th>Class</th>
                <th>Race</th>
                <th>Owner</th>
                <th>Last Online</th>
                <th>Status</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <%= if Enum.empty?(@characters) do %>
                <tr>
                  <td colspan="8" class="text-center py-8 text-base-content/50">
                    No characters found
                  </td>
                </tr>
              <% else %>
                <tr :for={char <- @characters} class="hover">
                  <td
                    class="font-semibold cursor-pointer"
                    phx-click="view_character"
                    phx-value-id={char.id}
                  >
                    {char.name}
                  </td>
                  <td class="cursor-pointer" phx-click="view_character" phx-value-id={char.id}>
                    {char.level}
                  </td>
                  <td class="cursor-pointer" phx-click="view_character" phx-value-id={char.id}>
                    <span style={"color: #{GameData.class_color(char.class)}"}>
                      {GameData.class_name(char.class)}
                    </span>
                  </td>
                  <td class="cursor-pointer" phx-click="view_character" phx-value-id={char.id}>
                    {GameData.race_name(char.race)}
                  </td>
                  <td>
                    <.link navigate={~p"/admin/users/#{char.account_id}"} class="link link-primary">
                      {char.account_email}
                    </.link>
                  </td>
                  <td
                    class="text-sm text-base-content/70 cursor-pointer"
                    phx-click="view_character"
                    phx-value-id={char.id}
                  >
                    {format_relative_time(char.last_online)}
                  </td>
                  <td class="cursor-pointer" phx-click="view_character" phx-value-id={char.id}>
                    <%= if char.deleted_at do %>
                      <span class="badge badge-error">Deleted</span>
                    <% else %>
                      <span class="badge badge-success">Active</span>
                    <% end %>
                  </td>
                  <td>
                    <.icon name="hero-chevron-right" class="size-4 text-base-content/50" />
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
              patch={~p"/admin/characters?#{pagination_params(@search_query, @include_deleted, @page - 1)}"}
              class="btn btn-sm"
            >
              Previous
            </.link>
            <span class="btn btn-sm btn-ghost">Page {@page}</span>
            <.link
              :if={@has_more}
              patch={~p"/admin/characters?#{pagination_params(@search_query, @include_deleted, @page + 1)}"}
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

  @impl true
  def handle_event("search", %{"q" => query} = params, socket) do
    include_deleted = params["deleted"] == "on"
    {:noreply, push_patch(socket, to: ~p"/admin/characters?#{pagination_params(query, include_deleted, 1)}")}
  end

  @impl true
  def handle_event("view_character", %{"id" => id}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/admin/characters/#{id}")}
  end

  defp perform_search(socket) do
    %{search_query: query, include_deleted: include_deleted, page: page} = socket.assigns
    offset = (page - 1) * @per_page

    opts = [
      include_deleted: include_deleted,
      limit: @per_page + 1,
      offset: offset
    ]

    opts = if query != "", do: Keyword.put(opts, :search, query), else: opts

    characters = Characters.search_characters(opts)
    {characters, has_more} = maybe_pop_extra(characters, @per_page)
    assign(socket, characters: characters, has_more: has_more)
  end

  defp maybe_pop_extra(list, limit) when length(list) > limit do
    {Enum.take(list, limit), true}
  end

  defp maybe_pop_extra(list, _limit), do: {list, false}

  defp format_relative_time(nil), do: "Never"
  defp format_relative_time(datetime), do: GameData.format_relative_time(datetime)

  defp pagination_params(query, include_deleted, page) do
    params = %{q: query}
    params = if include_deleted, do: Map.put(params, :deleted, "true"), else: params
    if page > 1, do: Map.put(params, :page, page), else: params
  end
end
