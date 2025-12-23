defmodule BezgelorPortalWeb.Live.Components.ServerStatusLive do
  @moduledoc """
  Live component for displaying real-time server status.

  Subscribes to server status updates via PubSub and updates the display
  in real-time without requiring page reload.
  """

  use BezgelorPortalWeb, :live_view

  alias BezgelorWorld.Portal

  @refresh_interval 30_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to server status updates
      Phoenix.PubSub.subscribe(BezgelorPortal.PubSub, "server_status")
      # Also poll periodically in case PubSub events are missed
      :timer.send_interval(@refresh_interval, self(), :refresh_status)
    end

    online_players =
      try do
        Portal.online_player_count()
      rescue
        _ -> 0
      end

    {:ok,
     assign(socket,
       online_players: online_players,
       server_online: true
     )}
  end

  @impl true
  def handle_info(:refresh_status, socket) do
    online_players =
      try do
        Portal.online_player_count()
      rescue
        _ -> socket.assigns.online_players
      end

    {:noreply, assign(socket, online_players: online_players)}
  end

  @impl true
  def handle_info({:server_status_update, status}, socket) do
    {:noreply,
     assign(socket,
       online_players: status[:online_players] || socket.assigns.online_players
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex items-center justify-center gap-4 text-sm">
      <div class="flex items-center gap-2">
        <span class="w-3 h-3 rounded-full bg-[var(--gaming-green)] animate-pulse"></span>
        <span class="text-white/70">Server Online</span>
      </div>
      <span class="text-white/30">|</span>
      <span class="text-white/70">
        <span class="text-[var(--gaming-cyan)] font-bold">{@online_players}</span> Players Online
      </span>
    </div>
    """
  end
end
