defmodule BezgelorPortalWeb.Components.CharacterViewer do
  @moduledoc """
  3D character viewer component using Three.js.

  Renders a WebGL canvas with the character model, supporting:
  - Race/gender-specific base models
  - Equipment overlay (future)
  - Animation playback

  Falls back to "preview not available" if model fails to load.

  ## Usage

      <.character_viewer
        character={@character}
        equipment={@equipped_items}
        class="h-[400px]"
      />

  ## Data Attributes

  The component sets these data attributes on the container div:
  - `data-race`: Race key for model loading (e.g., "human", "aurin")
  - `data-gender`: Gender key ("male" or "female")
  - `data-equipment`: JSON array of equipped item data
  """
  use Phoenix.Component

  @doc """
  Renders a 3D character viewer.

  ## Attributes

    * `:character` (required) - Character map with at least `id`, `race`, and `sex` fields
    * `:equipment` - List of equipped items (default: [])
    * `:class` - Additional CSS classes for the container
    * `:show_loading` - Whether to show loading spinner initially (default: true)
  """
  attr :character, :map, required: true
  attr :equipment, :list, default: []
  attr :class, :string, default: ""
  attr :show_loading, :boolean, default: true

  def character_viewer(assigns) do
    ~H"""
    <div
      id={"character-viewer-#{@character.id}"}
      class={"relative bg-base-300 rounded-lg overflow-hidden #{@class}"}
      phx-hook="CharacterViewer"
      data-race={race_key(@character.race)}
      data-gender={gender_key(@character.sex)}
      data-equipment={Jason.encode!(equipment_data(@equipment))}
    >
      <div :if={@show_loading} class="absolute inset-0 flex items-center justify-center text-base-content/30">
        <span class="loading loading-spinner loading-lg"></span>
      </div>
      <!-- Work in Progress Banner -->
      <div class="absolute inset-0 pointer-events-none overflow-hidden">
        <div
          class="absolute text-black text-xs font-bold text-center py-1 shadow-lg"
          style="background-color: #f7941d; width: 200px; top: 38px; left: -52px; transform: rotate(-45deg);"
        >
          Work in Progress
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a placeholder for when 3D viewer is not available.
  """
  attr :class, :string, default: ""
  attr :message, :string, default: "Character preview not available"

  def character_viewer_placeholder(assigns) do
    ~H"""
    <div class={"relative bg-base-300 rounded-lg overflow-hidden flex items-center justify-center #{@class}"}>
      <div class="text-center py-12 text-base-content/50">
        <svg
          xmlns="http://www.w3.org/2000/svg"
          class="h-12 w-12 mx-auto mb-2 opacity-50"
          fill="none"
          viewBox="0 0 24 24"
          stroke="currentColor"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M5.121 17.804A13.937 13.937 0 0112 16c2.5 0 4.847.655 6.879 1.804M15 10a3 3 0 11-6 0 3 3 0 016 0zm6 2a9 9 0 11-18 0 9 9 0 0118 0z"
          />
        </svg>
        <p>{@message}</p>
      </div>
    </div>
    """
  end

  # Race ID to key mapping based on WildStar race IDs (from NexusForever.Game.Static.Entity.Race)
  defp race_key(1), do: "human"
  defp race_key(2), do: "cassian"
  defp race_key(3), do: "granok"
  defp race_key(4), do: "aurin"
  defp race_key(5), do: "draken"
  defp race_key(12), do: "mechari"
  defp race_key(13), do: "chua"
  defp race_key(16), do: "mordesh"
  defp race_key(_), do: "human"

  # Gender/sex ID to key mapping
  defp gender_key(0), do: "male"
  defp gender_key(1), do: "female"
  defp gender_key(_), do: "male"

  # Extract equipment data for the viewer
  defp equipment_data(items) when is_list(items) do
    Enum.map(items, fn item ->
      %{
        slot: Map.get(item, :slot, 0),
        item_id: Map.get(item, :item_id, 0)
      }
    end)
  end

  defp equipment_data(_), do: []
end
