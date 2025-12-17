defmodule BezgelorPortalWeb.CharactersLive do
  @moduledoc """
  LiveView for displaying a user's characters.

  Shows a grid or list view of characters with:
  - Character name and level
  - Race and class
  - Faction indicator
  - Last online time
  - Play time
  """
  use BezgelorPortalWeb, :live_view

  alias BezgelorDb.Characters
  alias BezgelorPortal.GameData

  @impl true
  def mount(_params, _session, socket) do
    account = socket.assigns.current_account
    characters = Characters.list_characters(account.id)

    {:ok,
     assign(socket,
       page_title: "My Characters",
       characters: characters,
       view_mode: :grid
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-6xl mx-auto">
      <nav class="breadcrumbs text-sm mb-4">
        <ul>
          <li><.link navigate={~p"/dashboard"}>Dashboard</.link></li>
          <li>Characters</li>
        </ul>
      </nav>

      <div class="flex items-center justify-between mb-6">
        <div>
          <h1 class="text-2xl font-bold">My Characters</h1>
          <p class="text-base-content/70">
            {length(@characters)} of {Characters.max_characters()} characters
          </p>
        </div>

        <div class="join">
          <button
            type="button"
            class={"btn btn-sm join-item #{if @view_mode == :grid, do: "btn-active"}"}
            phx-click="set_view_mode"
            phx-value-mode="grid"
          >
            <.icon name="hero-squares-2x2" class="size-4" />
          </button>
          <button
            type="button"
            class={"btn btn-sm join-item #{if @view_mode == :list, do: "btn-active"}"}
            phx-click="set_view_mode"
            phx-value-mode="list"
          >
            <.icon name="hero-bars-3" class="size-4" />
          </button>
        </div>
      </div>

      <%= if Enum.empty?(@characters) do %>
        <div class="card bg-base-100 shadow-xl">
          <div class="card-body text-center py-16">
            <.icon name="hero-user-circle" class="size-16 mx-auto text-base-content/30" />
            <h2 class="card-title justify-center mt-4">No Characters Yet</h2>
            <p class="text-base-content/70">
              Launch the game client to create your first character.
            </p>
          </div>
        </div>
      <% else %>
        <%= if @view_mode == :grid do %>
          <.character_grid characters={@characters} />
        <% else %>
          <.character_list characters={@characters} />
        <% end %>
      <% end %>
    </div>
    """
  end

  # Grid view component - compact layout for many characters
  defp character_grid(assigns) do
    ~H"""
    <div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-3">
      <.link
        :for={character <- @characters}
        navigate={~p"/characters/#{character.id}"}
        class="card bg-base-100 shadow hover:shadow-lg transition-shadow cursor-pointer"
      >
        <div class="card-body p-3">
          <div class="flex items-center gap-2">
            <.character_avatar character={character} size="sm" />
            <div class="flex-1 min-w-0">
              <div class="font-semibold text-sm truncate">{character.name}</div>
              <div class="text-xs text-base-content/70">
                Lv{character.level}
                <span style={"color: #{GameData.class_color(character.class)}"}>
                  {GameData.class_name(character.class)}
                </span>
              </div>
            </div>
            <.faction_badge race_id={character.race} size="xs" />
          </div>

          <div class="flex justify-between text-xs text-base-content/60 mt-2">
            <span>{GameData.race_name(character.race)}</span>
            <span>{GameData.path_name(character.active_path)}</span>
          </div>

          <progress
            class="progress progress-primary w-full h-1 mt-1"
            value={rem(character.total_xp, 1000)}
            max="1000"
          />
        </div>
      </.link>
    </div>
    """
  end

  # List view component
  defp character_list(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-xl overflow-hidden">
      <div class="overflow-x-auto">
        <table class="table">
          <thead>
            <tr>
              <th>Character</th>
              <th>Level</th>
              <th>Class</th>
              <th>Race</th>
              <th>Path</th>
              <th>Played</th>
              <th>Last Online</th>
            </tr>
          </thead>
          <tbody>
            <.link
              :for={character <- @characters}
              navigate={~p"/characters/#{character.id}"}
              class="contents"
            >
              <tr class="hover:bg-base-200 cursor-pointer">
                <td>
                  <div class="flex items-center gap-3">
                    <.character_avatar character={character} size="sm" />
                    <div>
                      <div class="font-bold">{character.name}</div>
                      <.faction_badge race_id={character.race} size="xs" />
                    </div>
                  </div>
                </td>
                <td class="font-bold">{character.level}</td>
                <td>
                  <span style={"color: #{GameData.class_color(character.class)}"}>
                    {GameData.class_name(character.class)}
                  </span>
                </td>
                <td>{GameData.race_name(character.race)}</td>
                <td>{GameData.path_name(character.active_path)}</td>
                <td>{GameData.format_play_time(character.time_played_total)}</td>
                <td class="text-base-content/70">
                  {GameData.format_relative_time(character.last_online)}
                </td>
              </tr>
            </.link>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  # Character avatar component with class icon fallback
  defp character_avatar(assigns) do
    assigns = assign_new(assigns, :size, fn -> "md" end)

    size_class =
      case assigns.size do
        "lg" -> "w-16 h-16"
        "sm" -> "w-10 h-10"
        _ -> "w-12 h-12"
      end

    assigns = assign(assigns, :size_class, size_class)

    ~H"""
    <div class="avatar placeholder">
      <div class={"#{@size_class} rounded-full bg-base-300 text-base-content relative overflow-hidden"}>
        <span class={if @size == "lg", do: "text-xl", else: "text-sm"}>
          {String.first(@character.name)}
        </span>
        <!-- Work in Progress Banner -->
        <div
          class="absolute text-black text-center font-bold"
          style="background-color: #f7941d; width: 60px; top: 8px; left: -16px; transform: rotate(-45deg); font-size: 6px; line-height: 1.4;"
        >
          WiP
        </div>
      </div>
    </div>
    """
  end

  # Faction badge component - derives faction from race for accuracy
  defp faction_badge(assigns) do
    assigns = assign_new(assigns, :size, fn -> "sm" end)
    # Use race to determine correct faction (CharacterCreation data has inverted mappings)
    faction_id = GameData.faction_id_for_race(assigns.race_id)
    faction = GameData.get_faction(faction_id)

    assigns = assign(assigns, :faction, faction)

    ~H"""
    <div class={"badge #{badge_class(@size)}"} style={"background-color: #{@faction.color}; color: white"}>
      {@faction.name}
    </div>
    """
  end

  defp badge_class("xs"), do: "badge-xs"
  defp badge_class(_), do: "badge-sm"

  @impl true
  def handle_event("set_view_mode", %{"mode" => mode}, socket) do
    view_mode = String.to_existing_atom(mode)
    {:noreply, assign(socket, view_mode: view_mode)}
  end
end
