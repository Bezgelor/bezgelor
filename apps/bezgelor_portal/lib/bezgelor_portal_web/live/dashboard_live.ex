defmodule BezgelorPortalWeb.DashboardLive do
  @moduledoc """
  Dashboard LiveView - main landing page after login.

  Shows account overview and quick links to common actions.
  """
  use BezgelorPortalWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Dashboard")}
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-6xl mx-auto">
      <div class="flex items-center justify-between mb-6">
        <div>
          <h1 class="text-2xl font-bold">Dashboard</h1>
          <p class="text-base-content/70">Welcome, {@current_account.email}</p>
        </div>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        <.dashboard_card
          title="Characters"
          description="View and manage your characters"
          href="/characters"
          icon="hero-user-group"
        />

        <.dashboard_card
          title="Account Settings"
          description="Update your profile and security settings"
          href="/settings"
          icon="hero-cog-6-tooth"
        />

        <.dashboard_card
          :if={@has_admin_access}
          title="Admin Panel"
          description="Access administrative tools"
          href="/admin"
          icon="hero-shield-check"
          accent
        />
      </div>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :description, :string, required: true
  attr :href, :string, required: true
  attr :icon, :string, required: true
  attr :accent, :boolean, default: false

  defp dashboard_card(assigns) do
    ~H"""
    <.link href={@href} class="card bg-base-100 shadow-md hover:shadow-lg transition-shadow">
      <div class="card-body">
        <div class="flex items-center gap-4">
          <div class={[
            "p-3 rounded-lg",
            @accent && "bg-primary/10 text-primary",
            !@accent && "bg-base-200"
          ]}>
            <.icon name={@icon} class="size-6" />
          </div>
          <div>
            <h3 class="card-title text-lg">{@title}</h3>
            <p class="text-sm text-base-content/70">{@description}</p>
          </div>
        </div>
      </div>
    </.link>
    """
  end
end
