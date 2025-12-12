defmodule BezgelorPortalWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use BezgelorPortalWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders the main app layout for authenticated users.

  ## Examples

      <Layouts.app flash={@flash} current_account={@current_account}>
        <h1>Dashboard</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :current_account, :map, default: nil, doc: "the currently logged-in account"
  attr :has_admin_access, :boolean, default: false, doc: "whether user has any admin permissions"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="min-h-screen flex flex-col">
      <.navbar current_account={@current_account} has_admin_access={@has_admin_access} />

      <main class="flex-1 px-4 py-8 sm:px-6 lg:px-8">
        <div class="mx-auto max-w-7xl">
          {render_slot(@inner_block)}
        </div>
      </main>

      <footer class="footer footer-center p-4 bg-base-100 text-base-content">
        <aside>
          <p>Bezgelor WildStar Server Emulator</p>
        </aside>
      </footer>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Renders the admin layout with sidebar navigation.
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :current_account, :map, default: nil, doc: "the currently logged-in account"
  attr :permissions, :list, default: [], doc: "list of permission keys the user has"
  attr :page_title, :string, default: nil, doc: "the current page title for breadcrumb"

  slot :inner_block, required: true

  def admin(assigns) do
    ~H"""
    <div class="min-h-screen flex flex-col">
      <.navbar current_account={@current_account} has_admin_access={true} />

      <div class="flex-1 flex">
        <.admin_sidebar permissions={@permissions} />

        <main class="flex-1 px-4 py-8 sm:px-6 lg:px-8 bg-base-200/50">
          <div class="mx-auto max-w-7xl">
            <nav :if={@page_title} class="breadcrumbs text-sm mb-4">
              <ul>
                <li><a href="/admin">Admin</a></li>
                <li>{@page_title}</li>
              </ul>
            </nav>
            {render_slot(@inner_block)}
          </div>
        </main>
      </div>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Renders the main navigation bar.
  """
  attr :current_account, :map, default: nil
  attr :has_admin_access, :boolean, default: false

  def navbar(assigns) do
    ~H"""
    <header class="navbar bg-base-100 shadow-sm px-4 sm:px-6 lg:px-8">
      <div class="flex-1">
        <a href="/" class="flex items-center gap-2">
          <span class="text-xl font-bold text-primary">Bezgelor</span>
        </a>
      </div>
      <div class="flex-none">
        <ul class="flex items-center space-x-2">
          <li>
            <a href="/dashboard" class="btn btn-ghost btn-sm">Dashboard</a>
          </li>
          <li>
            <a href="/characters" class="btn btn-ghost btn-sm">Characters</a>
          </li>
          <li :if={@has_admin_access}>
            <a href="/admin" class="btn btn-ghost btn-sm">
              <.icon name="hero-shield-check-micro" class="size-4" />
              <span class="hidden sm:inline">Admin</span>
            </a>
          </li>
          <%= if @current_account do %>
            <li class="dropdown dropdown-end">
              <div tabindex="0" role="button" class="btn btn-ghost btn-sm">
                <span class="hidden sm:inline">{@current_account.email}</span>
                <.icon name="hero-chevron-down-micro" class="size-4" />
              </div>
              <ul
                tabindex="0"
                class="dropdown-content menu bg-base-100 rounded-box z-10 w-52 p-2 shadow-lg"
              >
                <li><a href="/settings">Account Settings</a></li>
                <li class="divider"></li>
                <li><a href="/logout">Log out</a></li>
              </ul>
            </li>
          <% end %>
          <li>
            <.theme_toggle />
          </li>
        </ul>
      </div>
    </header>
    """
  end

  @doc """
  Renders the admin sidebar with permission-aware navigation.
  """
  attr :permissions, :list, default: [], doc: "list of permission keys the user has"

  def admin_sidebar(assigns) do
    # Group permissions by category for sidebar sections
    permission_set = MapSet.new(assigns.permissions)

    # Check if dev routes are enabled
    dev_routes_enabled = Application.get_env(:bezgelor_portal, :dev_routes, false)

    assigns =
      assigns
      |> assign(:permission_set, permission_set)
      |> assign(:dev_routes_enabled, dev_routes_enabled)

    ~H"""
    <aside class="w-64 bg-base-100 border-r border-base-300 hidden lg:block">
      <nav class="p-4 space-y-2">
        <.sidebar_section
          title="Users"
          icon="hero-users"
          permission_set={@permission_set}
          links={[
            %{href: "/admin/users", label: "User Management", permission: "users.view"},
            %{href: "/admin/users/bans", label: "Bans & Suspensions", permission: "users.ban"}
          ]}
        />

        <.sidebar_section
          title="Characters"
          icon="hero-user-group"
          permission_set={@permission_set}
          links={[
            %{href: "/admin/characters", label: "Character Search", permission: "characters.view"},
            %{href: "/admin/characters/items", label: "Item Management", permission: "characters.modify_items"}
          ]}
        />

        <.sidebar_section
          title="Economy"
          icon="hero-currency-dollar"
          permission_set={@permission_set}
          links={[
            %{href: "/admin/economy", label: "Economy Overview", permission: "economy.view_stats"},
            %{href: "/admin/economy/transactions", label: "Transactions", permission: "economy.view_transactions"}
          ]}
        />

        <.sidebar_section
          title="Events"
          icon="hero-calendar"
          permission_set={@permission_set}
          links={[
            %{href: "/admin/events", label: "Event Management", permission: "events.manage"},
            %{href: "/admin/events/broadcast", label: "Broadcast Message", permission: "events.broadcast_message"}
          ]}
        />

        <.sidebar_section
          title="Server"
          icon="hero-server"
          permission_set={@permission_set}
          links={[
            %{href: "/admin/server", label: "Server Status", permission: "server.view_logs"},
            %{href: "/admin/server/logs", label: "Logs", permission: "server.view_logs"}
          ]}
        />

        <.sidebar_section
          title="Administration"
          icon="hero-cog-6-tooth"
          permission_set={@permission_set}
          links={[
            %{href: "/admin/roles", label: "Role Management", permission: "admin.manage_roles"},
            %{href: "/admin/audit", label: "Audit Log", permission: "admin.view_audit_log"}
          ]}
        />

        <!-- Dev Tools (only in development) -->
        <div :if={@dev_routes_enabled} class="collapse collapse-arrow bg-warning/10 rounded-lg border border-warning/30">
          <input type="checkbox" checked />
          <div class="collapse-title font-medium flex items-center gap-2 py-2 min-h-0 text-warning">
            <.icon name="hero-wrench-screwdriver" class="size-5" />
            Dev Tools
          </div>
          <div class="collapse-content px-0">
            <ul class="menu menu-sm">
              <li>
                <a href="/dev/tracing" target="_blank" class="flex items-center gap-2">
                  <.icon name="hero-chart-bar" class="size-4" />
                  Orion Tracing
                  <.icon name="hero-arrow-top-right-on-square" class="size-3 opacity-50" />
                </a>
              </li>
              <li>
                <a href="/dev/mailbox" target="_blank" class="flex items-center gap-2">
                  <.icon name="hero-envelope" class="size-4" />
                  Email Preview
                  <.icon name="hero-arrow-top-right-on-square" class="size-3 opacity-50" />
                </a>
              </li>
            </ul>
          </div>
        </div>
      </nav>
    </aside>
    """
  end

  attr :title, :string, required: true
  attr :icon, :string, required: true
  attr :permission_set, :any, required: true
  attr :links, :list, required: true

  defp sidebar_section(assigns) do
    # Filter links to only show ones the user has permission for
    visible_links = Enum.filter(assigns.links, fn link ->
      MapSet.member?(assigns.permission_set, link.permission)
    end)

    assigns = assign(assigns, :visible_links, visible_links)

    ~H"""
    <div :if={length(@visible_links) > 0} class="collapse collapse-arrow bg-base-200/50 rounded-lg">
      <input type="checkbox" checked />
      <div class="collapse-title font-medium flex items-center gap-2 py-2 min-h-0">
        <.icon name={@icon} class="size-5" />
        {@title}
      </div>
      <div class="collapse-content px-0">
        <ul class="menu menu-sm">
          <li :for={link <- @visible_links}>
            <a href={link.href}>{link.label}</a>
          </li>
        </ul>
      </div>
    </div>
    """
  end

  @doc """
  Renders the auth layout for login/register pages.

  ## Examples

      <Layouts.auth flash={@flash}>
        <h1>Login</h1>
      </Layouts.auth>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  slot :inner_block, required: true

  def auth(assigns) do
    ~H"""
    <div class="min-h-screen flex flex-col items-center justify-center px-4 py-12">
      <div class="w-full max-w-md">
        <div class="text-center mb-8">
          <h1 class="text-3xl font-bold text-primary">Bezgelor</h1>
          <p class="text-base-content/70 mt-2">WildStar Server Emulator</p>
        </div>

        <div class="card bg-base-100 shadow-xl">
          <div class="card-body">
            {render_slot(@inner_block)}
          </div>
        </div>

        <div class="text-center mt-6">
          <.theme_toggle />
        </div>
      </div>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
