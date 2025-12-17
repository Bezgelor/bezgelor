defmodule BezgelorPortalWeb.CharacterDetailLive do
  @moduledoc """
  LiveView for displaying detailed character information.

  Tabs:
  - Overview: Basic info, location, play time statistics
  - Inventory: Equipped items, bags, bank contents
  - Currencies: Gold and other in-game currencies
  - Guild: Guild membership and rank
  - Tradeskills: Profession levels and progress
  """
  use BezgelorPortalWeb, :live_view

  alias BezgelorDb.{Characters, Guilds, Inventory, Tradeskills}
  alias BezgelorPortal.GameData

  @tabs ~w(overview inventory bank currencies guild tradeskills)a

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    account = socket.assigns.current_account
    character_id = String.to_integer(id)

    case Characters.get_character(account.id, character_id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Character not found.")
         |> push_navigate(to: ~p"/characters")}

      character ->
        {:ok,
         socket
         |> assign(
           page_title: character.name,
           character: character,
           active_tab: :overview,
           tabs: @tabs,
           guild: nil,
           guild_membership: nil,
           inventory_items: [],
           equipped_items: [],
           bank_items: [],
           tradeskills: [],
           show_delete_modal: false
         )
         |> load_tab_data(:overview)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-6xl mx-auto">
      <!-- Breadcrumb -->
      <nav class="breadcrumbs text-sm mb-4">
        <ul>
          <li><.link navigate={~p"/dashboard"}>Dashboard</.link></li>
          <li><.link navigate={~p"/characters"}>Characters</.link></li>
          <li>{@character.name}</li>
        </ul>
      </nav>

      <!-- Header -->
      <div class="flex items-center gap-4 mb-6">
        <.character_avatar character={@character} size="lg" />
        <div class="flex-1">
          <h1 class="text-2xl font-bold flex items-center gap-2">
            {@character.name}
            <.faction_badge faction_id={@character.faction_id} />
          </h1>
          <p class="text-base-content/70">
            Level <span class="font-bold">{@character.level}</span>
            <span style={"color: #{GameData.class_color(@character.class)}"}>
              {GameData.class_name(@character.class)}
            </span>
            &bull; {GameData.race_name(@character.race)}
          </p>
        </div>

        <button type="button" class="btn btn-error btn-outline btn-sm" phx-click="show_delete_modal">
          <.icon name="hero-trash" class="size-4" />
          Delete
        </button>
      </div>

      <!-- Tabs -->
      <div class="tabs tabs-boxed mb-6">
        <button
          :for={tab <- @tabs}
          type="button"
          class={"tab #{if @active_tab == tab, do: "tab-active"}"}
          phx-click="switch_tab"
          phx-value-tab={tab}
        >
          {tab_label(tab)}
        </button>
      </div>

      <!-- Tab Content -->
      <div class="space-y-6">
        {render_tab_content(assigns)}
      </div>

      <!-- Delete Confirmation Modal -->
      <.delete_modal
        :if={@show_delete_modal}
        character={@character}
      />
    </div>
    """
  end

  # Tab labels
  defp tab_label(:overview), do: "Overview"
  defp tab_label(:inventory), do: "Inventory"
  defp tab_label(:bank), do: "Bank"
  defp tab_label(:currencies), do: "Currencies"
  defp tab_label(:guild), do: "Guild"
  defp tab_label(:tradeskills), do: "Tradeskills"

  # Render tab content based on active tab
  defp render_tab_content(%{active_tab: :overview} = assigns), do: render_overview(assigns)
  defp render_tab_content(%{active_tab: :inventory} = assigns), do: render_inventory(assigns)
  defp render_tab_content(%{active_tab: :bank} = assigns), do: render_bank(assigns)
  defp render_tab_content(%{active_tab: :currencies} = assigns), do: render_currencies(assigns)
  defp render_tab_content(%{active_tab: :guild} = assigns), do: render_guild(assigns)
  defp render_tab_content(%{active_tab: :tradeskills} = assigns), do: render_tradeskills(assigns)

  # Overview Tab
  defp render_overview(assigns) do

    ~H"""
    <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
      <!-- Basic Info Card -->
      <div class="card bg-base-100 shadow-xl">
        <div class="card-body">
          <h2 class="card-title">
            <.icon name="hero-user" class="size-5" />
            Basic Info
          </h2>
          <div class="grid grid-cols-2 gap-4 mt-4">
            <.info_row label="Name" value={@character.name} />
            <.info_row label="Level" value={@character.level} />
            <.info_row label="Class" value={GameData.class_name(@character.class)} />
            <.info_row label="Race" value={GameData.race_name(@character.race)} />
            <.info_row label="Faction" value={GameData.faction_name(@character.faction_id)} />
            <.info_row label="Path" value={GameData.path_name(@character.active_path)} />
            <.info_row label="Title" value={title_display(@character.title)} />
            <.info_row label="Active Spec" value={"Spec #{@character.active_spec + 1}"} />
          </div>
        </div>
      </div>

      <!-- Play Time Card -->
      <div class="card bg-base-100 shadow-xl">
        <div class="card-body">
          <h2 class="card-title">
            <.icon name="hero-clock" class="size-5" />
            Play Time
          </h2>
          <div class="grid grid-cols-2 gap-4 mt-4">
            <.info_row label="Total Time" value={GameData.format_play_time(@character.time_played_total)} />
            <.info_row label="This Level" value={GameData.format_play_time(@character.time_played_level)} />
            <.info_row label="Last Online" value={GameData.format_relative_time(@character.last_online)} />
            <.info_row label="Created" value={format_date(@character.inserted_at)} />
          </div>
        </div>
      </div>

      <!-- Location Card -->
      <div class="card bg-base-100 shadow-xl">
        <div class="card-body">
          <h2 class="card-title">
            <.icon name="hero-map-pin" class="size-5" />
            Location
          </h2>
          <div class="grid grid-cols-2 gap-4 mt-4">
            <.info_row label="World" value={GameData.world_name(@character.world_id)} />
            <.info_row label="Position" value={format_position(@character)} />
          </div>
        </div>
      </div>

      <!-- Experience Card -->
      <div class="card bg-base-100 shadow-xl">
        <div class="card-body">
          <h2 class="card-title">
            <.icon name="hero-chart-bar" class="size-5" />
            Experience
          </h2>
          <div class="grid grid-cols-2 gap-4 mt-4">
            <.info_row label="Total XP" value={format_number(@character.total_xp)} />
            <.info_row label="Rest Bonus" value={format_number(@character.rest_bonus_xp)} />
          </div>
          <.xp_progress character={@character} />
        </div>
      </div>
    </div>
    """
  end

  # Inventory Tab
  defp render_inventory(assigns) do

    ~H"""
    <div class="space-y-6">
      <!-- Equipped Items -->
      <div class="card bg-base-100 shadow-xl">
        <div class="card-body">
          <h2 class="card-title">
            <.icon name="hero-shield-check" class="size-5" />
            Equipped Items
          </h2>
          <%= if Enum.empty?(@equipped_items) do %>
            <div class="text-center py-8 text-base-content/50">
              <.icon name="hero-inbox" class="size-12 mx-auto mb-2" />
              <p>No items equipped</p>
            </div>
          <% else %>
            <div class="grid grid-cols-2 md:grid-cols-4 gap-2 mt-4">
              <.item_slot :for={item <- @equipped_items} item={item} />
            </div>
          <% end %>
        </div>
      </div>

      <!-- Bag Contents -->
      <div class="card bg-base-100 shadow-xl">
        <div class="card-body">
          <h2 class="card-title">
            <.icon name="hero-archive-box" class="size-5" />
            Inventory
          </h2>
          <%= if Enum.empty?(@inventory_items) do %>
            <div class="text-center py-8 text-base-content/50">
              <.icon name="hero-inbox" class="size-12 mx-auto mb-2" />
              <p>Inventory is empty</p>
            </div>
          <% else %>
            <div class="overflow-x-auto mt-4">
              <table class="table table-sm">
                <thead>
                  <tr>
                    <th>Item ID</th>
                    <th>Location</th>
                    <th>Qty</th>
                    <th>Durability</th>
                    <th>Bound</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={item <- @inventory_items}>
                    <td class="font-mono">{item.item_id}</td>
                    <td>Bag {item.bag_index}, Slot {item.slot}</td>
                    <td>{item.quantity}/{item.max_stack}</td>
                    <td>
                      <.durability_bar current={item.durability} max={item.max_durability} />
                    </td>
                    <td>
                      <span class={if item.bound, do: "badge badge-warning badge-sm", else: "text-base-content/50"}>
                        {if item.bound, do: "Yes", else: "No"}
                      </span>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
            <p class="text-sm text-base-content/50 mt-2">
              {length(@inventory_items)} items in inventory
            </p>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # Bank Tab
  defp render_bank(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-xl">
      <div class="card-body">
        <h2 class="card-title">
          <.icon name="hero-building-library" class="size-5" />
          Bank Storage
        </h2>
        <%= if Enum.empty?(@bank_items) do %>
          <div class="text-center py-8 text-base-content/50">
            <.icon name="hero-building-library" class="size-12 mx-auto mb-2" />
            <p>Bank is empty</p>
          </div>
        <% else %>
          <div class="overflow-x-auto mt-4">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>Item ID</th>
                  <th>Location</th>
                  <th>Qty</th>
                  <th>Durability</th>
                  <th>Bound</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={item <- @bank_items}>
                  <td class="font-mono">{item.item_id}</td>
                  <td>Bank Bag {item.bag_index}, Slot {item.slot}</td>
                  <td>{item.quantity}/{item.max_stack}</td>
                  <td>
                    <.durability_bar current={item.durability} max={item.max_durability} />
                  </td>
                  <td>
                    <span class={if item.bound, do: "badge badge-warning badge-sm", else: "text-base-content/50"}>
                      {if item.bound, do: "Yes", else: "No"}
                    </span>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <p class="text-sm text-base-content/50 mt-2">
            {length(@bank_items)} items in bank
          </p>
        <% end %>
      </div>
    </div>
    """
  end

  # Currencies Tab
  defp render_currencies(assigns) do

    ~H"""
    <div class="card bg-base-100 shadow-xl">
      <div class="card-body">
        <h2 class="card-title">
          <.icon name="hero-currency-dollar" class="size-5" />
          Currencies
        </h2>
        <div class="grid grid-cols-2 md:grid-cols-4 gap-4 mt-4">
          <.currency_card name="Gold" value={0} icon="hero-banknotes" color="warning" />
          <.currency_card name="Elder Gems" value={0} icon="hero-sparkles" color="secondary" />
          <.currency_card name="Renown" value={0} icon="hero-star" color="primary" />
          <.currency_card name="Prestige" value={0} icon="hero-trophy" color="accent" />
        </div>
        <p class="text-sm text-base-content/50 mt-4">
          Currency tracking coming soon. Data will be available when character logs in.
        </p>
      </div>
    </div>
    """
  end

  # Guild Tab
  defp render_guild(assigns) do

    ~H"""
    <div class="card bg-base-100 shadow-xl">
      <div class="card-body">
        <h2 class="card-title">
          <.icon name="hero-user-group" class="size-5" />
          Guild
        </h2>
        <%= if @guild do %>
          <div class="grid grid-cols-2 gap-4 mt-4">
            <.info_row label="Guild Name" value={@guild.name} />
            <.info_row label="Guild Tag" value={"<#{@guild.tag}>"} />
            <.info_row label="Rank" value={rank_name(@guild_membership)} />
            <.info_row label="Joined" value={format_date(@guild_membership.inserted_at)} />
          </div>
        <% else %>
          <div class="text-center py-8 text-base-content/50">
            <.icon name="hero-user-group" class="size-12 mx-auto mb-2" />
            <p>Not in a guild</p>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Tradeskills Tab
  defp render_tradeskills(assigns) do

    ~H"""
    <div class="card bg-base-100 shadow-xl">
      <div class="card-body">
        <h2 class="card-title">
          <.icon name="hero-wrench-screwdriver" class="size-5" />
          Tradeskills
        </h2>
        <%= if Enum.empty?(@tradeskills) do %>
          <div class="text-center py-8 text-base-content/50">
            <.icon name="hero-wrench-screwdriver" class="size-12 mx-auto mb-2" />
            <p>No tradeskills learned</p>
          </div>
        <% else %>
          <div class="space-y-4 mt-4">
            <div :for={tradeskill <- @tradeskills} class="flex items-center gap-4">
              <div class="flex-1">
                <div class="flex justify-between mb-1">
                  <span class="font-medium">Profession {tradeskill.profession_id}</span>
                  <span class="text-sm text-base-content/70">
                    Level {tradeskill.level}/{tradeskill.max_level}
                  </span>
                </div>
                <progress
                  class="progress progress-primary w-full"
                  value={tradeskill.xp}
                  max={tradeskill.xp_to_level}
                >
                </progress>
              </div>
              <span class={"badge #{if tradeskill.is_active, do: "badge-success", else: "badge-ghost"}"}>
                {if tradeskill.is_active, do: "Active", else: "Inactive"}
              </span>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Delete confirmation modal
  defp delete_modal(assigns) do
    ~H"""
    <div class="modal modal-open">
      <div class="modal-box">
        <h3 class="font-bold text-lg text-error">Delete Character</h3>
        <p class="py-4">
          Are you sure you want to delete <strong>{@character.name}</strong>?
          This action cannot be undone.
        </p>
        <p class="text-sm text-base-content/70 mb-4">
          Type the character name to confirm:
        </p>
        <form phx-submit="delete_character">
          <input
            type="text"
            name="confirm_name"
            class="input input-bordered w-full"
            placeholder={@character.name}
            autocomplete="off"
          />
          <div class="modal-action">
            <button type="button" class="btn" phx-click="hide_delete_modal">
              Cancel
            </button>
            <button type="submit" class="btn btn-error">
              Delete Forever
            </button>
          </div>
        </form>
      </div>
      <div class="modal-backdrop" phx-click="hide_delete_modal"></div>
    </div>
    """
  end

  # Character avatar component
  defp character_avatar(assigns) do
    size_class =
      case assigns[:size] do
        "lg" -> "w-16 h-16"
        _ -> "w-12 h-12"
      end

    assigns = assign(assigns, :size_class, size_class)

    ~H"""
    <div class="avatar placeholder">
      <div class={"#{@size_class} rounded-full bg-base-300 text-base-content"}>
        <span class="text-xl">{String.first(@character.name)}</span>
      </div>
    </div>
    """
  end

  # Faction badge
  defp faction_badge(assigns) do
    faction = GameData.get_faction(assigns.faction_id)
    assigns = assign(assigns, :faction, faction)

    ~H"""
    <span class="badge badge-sm" style={"background-color: #{@faction.color}; color: white"}>
      {@faction.name}
    </span>
    """
  end

  # Info row for key-value display
  defp info_row(assigns) do
    ~H"""
    <div>
      <div class="text-sm text-base-content/50">{@label}</div>
      <div class="font-medium">{@value}</div>
    </div>
    """
  end

  # Item slot component
  defp item_slot(assigns) do
    ~H"""
    <div class="bg-base-200 rounded p-2 text-center">
      <div class="font-mono text-sm">{@item.item_id}</div>
      <div class="text-xs text-base-content/50">Slot {@item.slot}</div>
    </div>
    """
  end

  # Durability progress bar
  defp durability_bar(assigns) do
    pct = if assigns.max > 0, do: round(assigns.current / assigns.max * 100), else: 0

    color =
      cond do
        pct >= 75 -> "progress-success"
        pct >= 25 -> "progress-warning"
        true -> "progress-error"
      end

    assigns = assign(assigns, :pct, pct)
    assigns = assign(assigns, :color, color)

    ~H"""
    <div class="flex items-center gap-2">
      <progress class={"progress #{@color} w-16 h-2"} value={@pct} max="100"></progress>
      <span class="text-xs">{@current}/{@max}</span>
    </div>
    """
  end

  # Currency card component
  defp currency_card(assigns) do
    ~H"""
    <div class="bg-base-200 rounded-lg p-4 text-center">
      <.icon name={@icon} class={"size-8 mx-auto text-#{@color}"} />
      <div class="font-bold text-lg mt-2">{format_number(@value)}</div>
      <div class="text-sm text-base-content/50">{@name}</div>
    </div>
    """
  end

  # XP progress bar
  defp xp_progress(assigns) do
    # Simple XP to next level calculation (would need real data)
    current = rem(assigns.character.total_xp, 1000)
    total = 1000

    assigns = assign(assigns, :current, current)
    assigns = assign(assigns, :total, total)

    ~H"""
    <div class="mt-4">
      <div class="flex justify-between text-sm mb-1">
        <span>XP Progress</span>
        <span>{format_number(@current)}/{format_number(@total)}</span>
      </div>
      <progress class="progress progress-info w-full" value={@current} max={@total}></progress>
    </div>
    """
  end

  # Helper functions
  defp title_display(0), do: "None"
  defp title_display(title_id), do: "Title ##{title_id}"

  defp format_position(character) do
    x = Float.round(character.location_x, 1)
    y = Float.round(character.location_y, 1)
    z = Float.round(character.location_z, 1)
    "(#{x}, #{y}, #{z})"
  end

  defp format_date(nil), do: "Unknown"

  defp format_date(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y")
  end

  defp format_number(nil), do: "0"

  defp format_number(n) when is_integer(n) do
    n
    |> Integer.to_string()
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.join(",")
    |> String.reverse()
  end

  defp format_number(n), do: to_string(n)

  defp rank_name(nil), do: "Unknown"
  defp rank_name(membership), do: "Rank #{membership.rank_index}"

  # Load data for the active tab
  defp load_tab_data(socket, :overview), do: socket

  defp load_tab_data(socket, :inventory) do
    character_id = socket.assigns.character.id
    all_items = Inventory.get_items(character_id)
    equipped = Enum.filter(all_items, &(&1.container_type == :equipped))
    bag_items = Enum.filter(all_items, &(&1.container_type == :bag))

    assign(socket, equipped_items: equipped, inventory_items: bag_items)
  end

  defp load_tab_data(socket, :bank) do
    character_id = socket.assigns.character.id
    all_items = Inventory.get_items(character_id)
    bank_items = Enum.filter(all_items, &(&1.container_type == :bank))

    assign(socket, bank_items: bank_items)
  end

  defp load_tab_data(socket, :currencies), do: socket

  defp load_tab_data(socket, :guild) do
    character_id = socket.assigns.character.id
    membership = Guilds.get_membership(character_id)

    if membership do
      guild = Guilds.get_guild(membership.guild_id)
      assign(socket, guild: guild, guild_membership: membership)
    else
      socket
    end
  end

  defp load_tab_data(socket, :tradeskills) do
    character_id = socket.assigns.character.id
    tradeskills = Tradeskills.get_professions(character_id)
    assign(socket, tradeskills: tradeskills)
  end

  # Event handlers
  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    tab = String.to_existing_atom(tab)

    socket =
      socket
      |> assign(active_tab: tab)
      |> load_tab_data(tab)

    {:noreply, socket}
  end

  def handle_event("show_delete_modal", _, socket) do
    {:noreply, assign(socket, show_delete_modal: true)}
  end

  def handle_event("hide_delete_modal", _, socket) do
    {:noreply, assign(socket, show_delete_modal: false)}
  end

  def handle_event("delete_character", %{"confirm_name" => name}, socket) do
    character = socket.assigns.character

    if String.downcase(name) == String.downcase(character.name) do
      account_id = socket.assigns.current_account.id

      case Characters.delete_character(account_id, character.id) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, "Character #{character.name} has been deleted.")
           |> push_navigate(to: ~p"/characters")}

        {:error, _} ->
          {:noreply,
           socket
           |> put_flash(:error, "Failed to delete character.")
           |> assign(show_delete_modal: false)}
      end
    else
      {:noreply,
       socket
       |> put_flash(:error, "Character name doesn't match.")
       |> assign(show_delete_modal: false)}
    end
  end
end
