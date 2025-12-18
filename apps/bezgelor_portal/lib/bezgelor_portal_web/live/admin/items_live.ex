defmodule BezgelorPortalWeb.Admin.ItemsLive do
  @moduledoc """
  Admin page for searching and viewing item data.

  Provides:
  - Search by item ID or name
  - Item detail modal with all properties
  - Quality-colored item names
  """
  use BezgelorPortalWeb, :live_view

  alias BezgelorData.Store

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Item Database",
       search_query: "",
       search_results: [],
       selected_item: nil
     ),
     layout: {BezgelorPortalWeb.Layouts, :admin}}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    query = params["q"] || ""

    socket =
      if query != "" do
        results = Store.search_items(query)
        assign(socket, search_query: query, search_results: results)
      else
        assign(socket, search_query: query, search_results: [])
      end

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-bold">Item Database</h1>
          <p class="text-base-content/70">Search and view game item data</p>
        </div>
      </div>

      <!-- Search -->
      <div class="card bg-base-100 shadow">
        <div class="card-body">
          <form phx-submit="search" phx-change="search_change">
            <div class="join w-full">
              <input
                type="text"
                name="query"
                value={@search_query}
                placeholder="Search by item ID or name..."
                class="input input-bordered join-item flex-1"
                phx-debounce="300"
              />
              <button type="submit" class="btn btn-primary join-item">
                <.icon name="hero-magnifying-glass" class="size-5" />
                Search
              </button>
            </div>
          </form>
        </div>
      </div>

      <!-- Results -->
      <div class="card bg-base-100 shadow">
        <div class="card-body">
          <h2 class="card-title">Results ({length(@search_results)})</h2>

          <%= if Enum.empty?(@search_results) do %>
            <p class="text-base-content/50 py-4">
              <%= if @search_query == "" do %>
                Enter a search term to find items.
              <% else %>
                No items found matching "<%= @search_query %>".
              <% end %>
            </p>
          <% else %>
            <div class="overflow-x-auto mt-4">
              <table class="table table-sm">
                <thead>
                  <tr>
                    <th>ID</th>
                    <th>Name</th>
                    <th>Type</th>
                    <th>Level</th>
                    <th>Quality</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={item <- @search_results} class="hover cursor-pointer" phx-click="view_item" phx-value-id={item[:ID]}>
                    <td class="font-mono">{item[:ID]}</td>
                    <td class={item_quality_class(item)}>{item.name}</td>
                    <td>{item_family_name(item)}</td>
                    <td>{Map.get(item, :powerLevel, "-")}</td>
                    <td>
                      <span class={"badge badge-sm #{quality_badge_class(item)}"}>
                        {quality_name(item)}
                      </span>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          <% end %>
        </div>
      </div>

      <!-- Item Detail Modal -->
      <.item_detail_modal :if={@selected_item} item={@selected_item} />
    </div>
    """
  end

  defp item_detail_modal(assigns) do
    ~H"""
    <div class="modal modal-open">
      <div class="modal-box max-w-2xl max-h-[80vh] overflow-y-auto">
        <button
          type="button"
          class="btn btn-sm btn-circle btn-ghost absolute right-2 top-2"
          phx-click="close_item"
        >
          <.icon name="hero-x-mark" class="size-4" />
        </button>

        <div class="flex items-center gap-4 mb-4">
          <div class={"relative p-3 rounded-lg bg-base-200 overflow-hidden #{item_quality_bg(@item)}"}>
            <.icon name={item_family_icon(@item)} class={"size-12 #{item_quality_class(@item)}"} />
            <div
              class="absolute text-black text-center font-bold uppercase tracking-wide"
              style="background-color: #f7941d; width: 80px; top: 12px; left: -20px; transform: rotate(-45deg); font-size: 10px; line-height: 1.6; box-shadow: 0 2px 4px rgba(0,0,0,0.3);"
            >
              WiP
            </div>
          </div>
          <div>
            <h3 class={"font-bold text-lg #{item_quality_class(@item)}"}>{@item.name}</h3>
            <p class="text-sm text-base-content/50">{item_family_name(@item)} • ID: {@item[:ID]}</p>
          </div>
        </div>

        <div class="grid grid-cols-2 gap-4 text-sm">
          <div>
            <span class="text-base-content/50">Item ID:</span>
            <span class="font-mono ml-2">{@item[:ID]}</span>
          </div>
          <div>
            <span class="text-base-content/50">Family:</span>
            <span class="ml-2">{item_family_name(@item)}</span>
          </div>
          <div>
            <span class="text-base-content/50">Category:</span>
            <span class="ml-2">{Map.get(@item, :item2CategoryId, 0)}</span>
          </div>
          <div>
            <span class="text-base-content/50">Type:</span>
            <span class="ml-2">{Map.get(@item, :item2TypeId, 0)}</span>
          </div>
          <div>
            <span class="text-base-content/50">Power Level:</span>
            <span class="ml-2">{Map.get(@item, :powerLevel, 0)}</span>
          </div>
          <div>
            <span class="text-base-content/50">Required Level:</span>
            <span class="ml-2">{Map.get(@item, :requiredLevel, 0)}</span>
          </div>
          <div>
            <span class="text-base-content/50">Quality:</span>
            <span class={"ml-2 #{item_quality_class(@item)}"}>{quality_name(@item)}</span>
          </div>
          <div>
            <span class="text-base-content/50">Max Stack:</span>
            <span class="ml-2">{Map.get(@item, :maxStackCount, 1)}</span>
          </div>
          <div>
            <span class="text-base-content/50">Bind Flags:</span>
            <span class="ml-2">{bind_type_name(@item)}</span>
          </div>
          <div>
            <span class="text-base-content/50">Display ID:</span>
            <span class="font-mono ml-2">{Map.get(@item, :itemDisplayId, 0)}</span>
          </div>
        </div>

        <div class="divider"></div>

        <div class="text-sm">
          <h4 class="font-semibold mb-2">Raw Data</h4>
          <pre class="bg-base-200 p-3 rounded-lg overflow-auto max-h-60 text-xs"><%= @item |> Map.drop([:name]) |> inspect(pretty: true, limit: :infinity) %></pre>
        </div>

        <div class="modal-action">
          <button type="button" class="btn" phx-click="close_item">Close</button>
        </div>
      </div>
      <div class="modal-backdrop" phx-click="close_item"></div>
    </div>
    """
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    {:noreply, push_patch(socket, to: ~p"/admin/items?q=#{query}")}
  end

  def handle_event("search_change", %{"query" => query}, socket) do
    if String.length(query) >= 2 do
      results = Store.search_items(query)
      {:noreply, assign(socket, search_query: query, search_results: results)}
    else
      {:noreply, assign(socket, search_query: query, search_results: [])}
    end
  end

  def handle_event("view_item", %{"id" => id_str}, socket) do
    {id, ""} = Integer.parse(id_str)

    case Store.get(:items, id) do
      {:ok, item} ->
        # Add the name
        name = Store.get_text(Map.get(item, :name_text_id, 0)) || "Item ##{id}"
        item = Map.put(item, :name, name)
        {:noreply, assign(socket, selected_item: item)}

      :error ->
        {:noreply, put_flash(socket, :error, "Item not found")}
    end
  end

  def handle_event("close_item", _, socket) do
    {:noreply, assign(socket, selected_item: nil)}
  end

  # Quality ID to text color class
  defp item_quality_class(item) do
    case Map.get(item, :itemQualityId, 2) do
      1 -> "text-gray-400"
      2 -> ""
      3 -> "text-green-500"
      4 -> "text-blue-500"
      5 -> "text-purple-500"
      6 -> "text-orange-500"
      7 -> "text-pink-500"
      _ -> ""
    end
  end

  # Quality ID to badge class
  defp quality_badge_class(item) do
    case Map.get(item, :itemQualityId, 2) do
      1 -> "badge-ghost"
      2 -> ""
      3 -> "badge-success"
      4 -> "badge-info"
      5 -> "badge-secondary"
      6 -> "badge-warning"
      7 -> "badge-accent"
      _ -> ""
    end
  end

  # Quality ID to name
  defp quality_name(item) do
    case Map.get(item, :itemQualityId, 2) do
      1 -> "Poor"
      2 -> "Common"
      3 -> "Uncommon"
      4 -> "Rare"
      5 -> "Epic"
      6 -> "Legendary"
      7 -> "Artifact"
      _ -> "Unknown"
    end
  end

  # Item family ID to icon
  defp item_family_icon(item) do
    case Map.get(item, :item2FamilyId, 0) do
      1 -> "hero-shield-check"      # Armor
      2 -> "hero-bolt"              # Weapon
      3 -> "hero-archive-box"       # Bag
      4 -> "hero-beaker"            # Consumable
      5 -> "hero-currency-dollar"   # Currency
      6 -> "hero-clipboard-document" # Quest
      7 -> "hero-home"              # Housing
      8 -> "hero-sparkles"          # Costume
      9 -> "hero-puzzle-piece"      # Schematic
      10 -> "hero-cog-6-tooth"      # Tool
      11 -> "hero-book-open"        # Amp
      12 -> "hero-book-open"        # Amp
      13 -> "hero-cube"             # Rune
      14 -> "hero-swatch"           # Dye
      15 -> "hero-photo"            # Decor
      16 -> "hero-wrench-screwdriver" # FABkit
      _ -> "hero-cube-transparent"  # Other
    end
  end

  # Quality ID to background class
  defp item_quality_bg(item) do
    case Map.get(item, :itemQualityId, 2) do
      1 -> "bg-gray-500/20"
      2 -> ""
      3 -> "bg-green-500/20"
      4 -> "bg-blue-500/20"
      5 -> "bg-purple-500/20"
      6 -> "bg-orange-500/20"
      7 -> "bg-pink-500/20"
      _ -> ""
    end
  end

  # Item family ID to name
  defp item_family_name(item) do
    case Map.get(item, :item2FamilyId, 0) do
      1 -> "Armor"
      2 -> "Weapon"
      3 -> "Bag"
      4 -> "Consumable"
      5 -> "Currency"
      6 -> "Quest"
      7 -> "Housing"
      8 -> "Costume"
      9 -> "Mount"
      10 -> "Pet"
      11 -> "Schematic"
      12 -> "Amp"
      13 -> "Rune"
      14 -> "Dye"
      15 -> "Decor"
      16 -> "FABkit"
      _ -> "Other (#{Map.get(item, :item2FamilyId, 0)})"
    end
  end

  # Bind flags to name
  defp bind_type_name(item) do
    case Map.get(item, :bindFlags, 0) do
      0 -> "None"
      1 -> "Bind on Equip"
      2 -> "Bind on Pickup"
      8 -> "Bind on Use"
      _ -> "Other (#{Map.get(item, :bindFlags, 0)})"
    end
  end
end
