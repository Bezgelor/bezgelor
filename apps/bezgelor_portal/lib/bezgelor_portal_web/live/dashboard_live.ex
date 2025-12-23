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

      <!-- Get Started Banner -->
      <div class="mt-8 card bg-gradient-to-r from-primary/10 via-secondary/10 to-accent/10 shadow-lg border border-primary/20">
        <div class="card-body">
          <div class="flex items-center gap-3 mb-4">
            <.icon name="hero-arrow-down-tray" class="size-8 text-primary" />
            <h2 class="card-title text-2xl">Ready to Play?</h2>
          </div>

          <p class="text-base-content/80 mb-6">
            Get WildStar running on Bezgelor in just a few steps.
          </p>

          <div class="grid grid-cols-1 md:grid-cols-3 gap-6 mb-6">
            <div class="flex gap-3">
              <div class="badge badge-primary badge-lg">1</div>
              <div>
                <h3 class="font-semibold">Download WildStar</h3>
                <p class="text-sm text-base-content/70">
                  Get the client (~30GB)
                </p>
              </div>
            </div>

            <div class="flex gap-3">
              <div class="badge badge-secondary badge-lg">2</div>
              <div>
                <h3 class="font-semibold">Get the Launcher</h3>
                <p class="text-sm text-base-content/70">
                  Connects to Bezgelor
                </p>
              </div>
            </div>

            <div class="flex gap-3">
              <div class="badge badge-accent badge-lg">3</div>
              <div>
                <h3 class="font-semibold">Play!</h3>
                <p class="text-sm text-base-content/70">
                  Log in with this account
                </p>
              </div>
            </div>
          </div>

          <.link href="/download" class="btn btn-primary w-fit">
            <.icon name="hero-rocket-launch" class="size-5" />
            Let's Go!
          </.link>
        </div>
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
