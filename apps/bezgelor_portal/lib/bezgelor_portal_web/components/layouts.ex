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
  attr :flash, :map, default: %{}, doc: "the map of flash messages"
  attr :current_account, :map, default: nil, doc: "the currently logged-in account"
  attr :has_admin_access, :boolean, default: false, doc: "whether user has any admin permissions"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :server_status, :map, default: nil, doc: "server status for navbar display"
  attr :inner_content, :any, default: nil, doc: "content when used as a layout"
  slot :inner_block, doc: "content when used as a component"

  def app(assigns) do
    assigns = assign_new(assigns, :flash, fn -> %{} end)

    ~H"""
    <div class="min-h-screen flex flex-col">
      <.navbar
        current_account={@current_account}
        has_admin_access={@has_admin_access}
        server_status={@server_status}
      />

      <main class="flex-1 px-4 py-8 sm:px-6 lg:px-8">
        <div class="mx-auto max-w-7xl">
          <%= if @inner_content do %>
            {@inner_content}
          <% else %>
            {render_slot(@inner_block)}
          <% end %>
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
  attr :flash, :map, default: %{}, doc: "the map of flash messages"
  attr :current_account, :map, default: nil, doc: "the currently logged-in account"
  attr :permissions, :list, default: [], doc: "list of permission keys the user has"
  attr :page_title, :string, default: nil, doc: "the current page title for breadcrumb"
  attr :parent_path, :string, default: nil, doc: "optional parent breadcrumb path"
  attr :parent_label, :string, default: nil, doc: "optional parent breadcrumb label"
  attr :inner_content, :any, default: nil, doc: "content when used as a layout"
  slot :inner_block, doc: "content when used as a component"

  def admin(assigns) do
    assigns = assign_new(assigns, :flash, fn -> %{} end)

    ~H"""
    <div class="min-h-screen flex flex-col">
      <.navbar current_account={@current_account} has_admin_access={true} />

      <div class="flex-1 flex">
        <.admin_sidebar permissions={@permissions} />

        <main class="flex-1 px-4 py-8 sm:px-6 lg:px-8 bg-base-200/50">
          <div class="mx-auto max-w-7xl">
            <nav :if={@page_title} class="breadcrumbs text-sm mb-4">
              <ul>
                <li><.link navigate={~p"/admin"}>Admin</.link></li>
                <li :if={@parent_path && @parent_label}>
                  <.link navigate={@parent_path}>{@parent_label}</.link>
                </li>
                <li>{@page_title}</li>
              </ul>
            </nav>
            <%= if @inner_content do %>
              {@inner_content}
            <% else %>
              {render_slot(@inner_block)}
            <% end %>
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
  attr :server_status, :map, default: nil

  def navbar(assigns) do
    ~H"""
    <header class="navbar bg-base-100 shadow-sm px-4 sm:px-6 lg:px-8 relative z-40 items-center">
      <!-- Left: Logo - overlaps into body -->
      <div class="flex-1">
        <a href="/" class="logo-overlap">
          <img
            src={~p"/images/bezgelor_logotype_b_squash.png"}
            alt="Bezgelor"
            class="logo-overlap-img"
          />
        </a>
      </div>
      
    <!-- Center: Server Status (if available) -->
      <div
        :if={@server_status}
        class="hidden sm:flex items-center gap-2 absolute left-1/2 -translate-x-1/2"
      >
        <%= if @server_status[:maintenance_mode] do %>
          <div class="badge badge-warning gap-1.5">
            <span class="size-2 rounded-full bg-warning-content animate-pulse"></span>
            <span>Maintenance</span>
          </div>
        <% else %>
          <div class="badge badge-success gap-1.5">
            <span class="size-2 rounded-full bg-success-content animate-pulse"></span>
            <span>Online</span>
          </div>
        <% end %>
        <div class="badge badge-ghost gap-1.5">
          <.icon name="hero-users-micro" class="size-3" />
          <span>{@server_status[:online_players] || 0}</span>
        </div>
      </div>
      
    <!-- Right: Account & Theme -->
      <div class="flex-1 flex justify-end items-center h-full">
        <ul class="flex items-center space-x-1 h-full">
          <%= if @current_account do %>
            <li class="dropdown dropdown-end">
              <div tabindex="0" role="button" class="btn btn-ghost">
                <span class="hidden sm:inline">{@current_account.email}</span>
                <.icon name="hero-chevron-down-micro" class="size-4" />
              </div>
              <ul
                tabindex="0"
                class="dropdown-content menu bg-base-100 rounded-box z-10 w-52 p-2 shadow-lg"
              >
                <li><a href="/dashboard">Dashboard</a></li>
                <li><a href="/characters">Characters</a></li>
                <li :if={@has_admin_access}><a href="/admin">Admin Panel</a></li>
                <hr class="my-1 border-base-300" />
                <li><a href="/settings">Account Settings</a></li>
                <li><a href="/settings/totp/setup">Two-Factor Auth</a></li>
                <hr class="my-1 border-base-300" />
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
    <aside class="w-52 bg-base-100 border-r border-base-300 hidden lg:block sticky top-0 h-screen overflow-y-auto pt-8">
      <nav class="p-2 space-y-1">
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
            %{
              href: "/admin/characters",
              label: "Character Management",
              permission: "characters.view"
            },
            %{href: "/admin/items", label: "Item Management", permission: "characters.view"}
          ]}
        />

        <.sidebar_section
          title="Economy"
          icon="hero-currency-dollar"
          permission_set={@permission_set}
          links={[
            %{href: "/admin/economy", label: "Economy Overview", permission: "economy.view_stats"}
          ]}
        />

        <.sidebar_section
          title="Events"
          icon="hero-calendar"
          permission_set={@permission_set}
          links={[
            %{href: "/admin/events", label: "Event Manager", permission: "events.manage"},
            %{
              href: "/admin/events/broadcast",
              label: "Broadcast Message",
              permission: "events.broadcast_message"
            }
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
            %{href: "/admin/audit-log", label: "Audit Log", permission: "admin.view_audit_log"}
          ]}
        />

    <!-- Testing Tools (only in development) -->
        <div :if={@dev_routes_enabled} class="mb-2">
          <div class="text-xs font-semibold text-info uppercase tracking-wider px-2 py-1 flex items-center gap-1.5">
            <.icon name="hero-beaker" class="size-3.5" /> Testing Tools
          </div>
          <ul class="menu menu-xs">
            <li>
              <.link navigate="/admin/testing">Character Creation</.link>
            </li>
          </ul>
        </div>

    <!-- Dev Tools (only in development) -->
        <div :if={@dev_routes_enabled} class="mb-2">
          <div class="text-xs font-semibold text-warning uppercase tracking-wider px-2 py-1 flex items-center gap-1.5">
            <.icon name="hero-wrench-screwdriver" class="size-3.5" /> Dev Tools
          </div>
          <ul class="menu menu-xs">
            <li>
              <a href="/dev/tracing" target="_blank" class="flex items-center gap-1.5">
                Orion Tracing
                <.icon name="hero-arrow-top-right-on-square" class="size-3 opacity-50" />
              </a>
            </li>
            <li>
              <a href="/dev/mailbox" target="_blank" class="flex items-center gap-1.5">
                Email Preview
                <.icon name="hero-arrow-top-right-on-square" class="size-3 opacity-50" />
              </a>
            </li>
          </ul>
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
    visible_links =
      Enum.filter(assigns.links, fn link ->
        MapSet.member?(assigns.permission_set, link.permission)
      end)

    assigns = assign(assigns, :visible_links, visible_links)

    ~H"""
    <div :if={length(@visible_links) > 0} class="mb-2">
      <div class="text-xs font-semibold text-base-content/50 uppercase tracking-wider px-2 py-1 flex items-center gap-1.5">
        <.icon name={@icon} class="size-3.5" />
        {@title}
      </div>
      <ul class="menu menu-xs">
        <li :for={link <- @visible_links}>
          <.link navigate={link.href}>{link.label}</.link>
        </li>
      </ul>
    </div>
    """
  end

  @doc """
  Renders the gaming auth layout for login/register pages.

  Features the bombastic WildStar-inspired gaming aesthetic with animated
  backgrounds, glowing effects, and gaming-styled forms.

  Can be used either as a LiveView layout (receives @inner_content) or
  as a component (receives @inner_block slot).

  ## Examples

      # As a LiveView layout:
      {:ok, socket, layout: {BezgelorPortalWeb.Layouts, :auth}}

      # As a component:
      <Layouts.auth flash={@flash}>
        <h1>Login</h1>
      </Layouts.auth>

  """
  attr :flash, :map, default: %{}, doc: "the map of flash messages"
  attr :inner_content, :any, default: nil, doc: "content when used as a layout"
  slot :inner_block, doc: "content when used as a component"

  def auth(assigns) do
    # Ensure flash has a default value
    assigns = assign_new(assigns, :flash, fn -> %{} end)

    ~H"""
    <div class="gaming-bg min-h-screen flex flex-col">
      <!-- Animated background elements -->
      <div class="fixed inset-0 overflow-hidden pointer-events-none">
        <div class="gaming-starfield"></div>
        <div class="gaming-mesh"></div>
      </div>
      
    <!-- Navigation back to home -->
      <nav class="relative z-10 p-4">
        <a
          href="/"
          class="inline-flex items-center gap-2 text-white/70 hover:text-[var(--gaming-cyan)] transition-colors"
        >
          <.icon name="hero-arrow-left" class="size-5" />
          <span>Back to Home</span>
        </a>
      </nav>
      
    <!-- Auth content -->
      <main class="flex-1 flex flex-col items-center justify-center px-4 py-8 relative z-10">
        <div class="w-full max-w-md">
          <!-- Logo and title -->
          <div class="text-center mb-8">
            <a href="/" class="inline-block">
              <h1 class="text-4xl font-bold text-glow-cyan text-glow-pulse">BEZGELOR</h1>
            </a>
            <p class="text-white/60 mt-2">Your gateway to Nexus awaits</p>
          </div>
          
    <!-- Auth card - no animate-on-scroll to prevent LiveView patch issues -->
          <div class="card-gaming auth-card">
            <div class="p-8">
              <%= if @inner_content do %>
                {@inner_content}
              <% else %>
                {render_slot(@inner_block)}
              <% end %>
            </div>
          </div>
          
    <!-- Footer links -->
          <div class="text-center mt-6 space-y-3">
            <div class="flex items-center justify-center gap-4 text-sm">
              <a href="/terms" class="text-white/50 hover:text-[var(--gaming-cyan)] transition-colors">
                Terms
              </a>
              <span class="text-white/30">•</span>
              <a
                href="/privacy"
                class="text-white/50 hover:text-[var(--gaming-cyan)] transition-colors"
              >
                Privacy
              </a>
              <span class="text-white/30">•</span>
              <a
                href="https://discord.gg/bezgelor"
                target="_blank"
                class="text-white/50 hover:text-[var(--gaming-cyan)] transition-colors"
              >
                Support
              </a>
            </div>
          </div>
        </div>
      </main>
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

  # ============================================
  # GAMING WEBSITE LAYOUTS
  # ============================================

  @doc """
  Renders the gaming layout for public-facing pages.

  This layout features the bombastic WildStar-inspired gaming aesthetic
  with animated backgrounds, glowing effects, and full gaming footer.
  """
  attr :flash, :map, default: %{}, doc: "the map of flash messages"
  attr :current_account, :map, default: nil, doc: "the currently logged-in account"
  attr :inner_content, :any, default: nil, doc: "content when used as a layout"
  slot :inner_block, doc: "content when used as a component"

  def gaming(assigns) do
    assigns = assign_new(assigns, :flash, fn -> %{} end)

    ~H"""
    <div class="gaming-bg min-h-screen flex flex-col">
      <.gaming_navbar current_account={@current_account} />

      <main class="flex-1">
        <%= if @inner_content do %>
          {@inner_content}
        <% else %>
          {render_slot(@inner_block)}
        <% end %>
      </main>

      <.gaming_footer />
      
    <!-- Back to top button -->
      <button id="back-to-top" aria-label="Back to top"></button>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Renders the gaming navbar with transparent-to-solid scroll effect.
  """
  attr :current_account, :map, default: nil

  def gaming_navbar(assigns) do
    ~H"""
    <nav class="navbar-gaming flex items-center justify-between">
      <a href="/" class="navbar-gaming-logo-link">
        <img
          src={~p"/images/bezgelor_logotype_b_squash.png"}
          alt="Bezgelor"
          class="navbar-gaming-logo-img"
        />
      </a>

      <div class="hidden md:flex items-center gap-2">
        <a href="/features" class="navbar-gaming-link">Features</a>
        <a href="/news" class="navbar-gaming-link">News</a>
        <a href="/download" class="navbar-gaming-link">Download</a>
        <a href="/community" class="navbar-gaming-link">Community</a>
      </div>

      <div class="flex items-center gap-4">
        <%= if @current_account do %>
          <a href="/dashboard" class="btn-gaming btn-gaming-primary btn-shimmer text-sm">
            Dashboard
          </a>
        <% else %>
          <a href="/login" class="navbar-gaming-link hidden sm:block">Login</a>
          <a href="/register" class="btn-gaming btn-gaming-primary btn-shimmer text-sm">
            Play Now
          </a>
        <% end %>
        
    <!-- Mobile menu button -->
        <button
          class="md:hidden text-white"
          onclick="document.getElementById('mobile-menu').classList.toggle('hidden')"
        >
          <.icon name="hero-bars-3" class="size-6" />
        </button>
      </div>
    </nav>

    <!-- Mobile menu -->
    <div id="mobile-menu" class="hidden fixed inset-0 z-50 bg-[var(--gaming-bg-dark)] md:hidden">
      <div class="flex flex-col h-full p-6">
        <div class="flex justify-between items-center mb-8">
          <img src={~p"/images/bezgelor_logotype_b_squash.png"} alt="Bezgelor" class="h-10 w-auto" />
          <button onclick="document.getElementById('mobile-menu').classList.add('hidden')">
            <.icon name="hero-x-mark" class="size-6 text-white" />
          </button>
        </div>
        <div class="flex flex-col gap-4">
          <a href="/features" class="text-xl text-white hover:text-[var(--gaming-cyan)]">Features</a>
          <a href="/news" class="text-xl text-white hover:text-[var(--gaming-cyan)]">News</a>
          <a href="/download" class="text-xl text-white hover:text-[var(--gaming-cyan)]">Download</a>
          <a href="/community" class="text-xl text-white hover:text-[var(--gaming-cyan)]">
            Community
          </a>
          <hr class="border-[var(--gaming-cyan)]/30 my-4" />
          <%= if @current_account do %>
            <a href="/dashboard" class="btn-gaming btn-gaming-primary text-center">Dashboard</a>
          <% else %>
            <a href="/login" class="text-xl text-white hover:text-[var(--gaming-cyan)]">Login</a>
            <a href="/register" class="btn-gaming btn-gaming-primary text-center mt-4">Play Now</a>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders the full gaming footer with all sections.
  """
  def gaming_footer(assigns) do
    ~H"""
    <footer class="footer-gaming">
      <div class="footer-gaming-grid">
        <!-- About Section -->
        <div class="footer-gaming-section">
          <h4>About</h4>
          <a href="/about">About Bezgelor</a>
          <a href="/about#team">The Team</a>
          <a href="/about#open-source">Open Source</a>
          <a href="/about#credits">Credits</a>
        </div>
        
    <!-- Legal Section -->
        <div class="footer-gaming-section">
          <h4>Legal</h4>
          <a href="/terms">Terms of Service</a>
          <a href="/privacy">Privacy Policy</a>
          <a href="/privacy#dmca">DMCA</a>
          <a href="/privacy#cookies">Cookie Policy</a>
        </div>
        
    <!-- Community Section -->
        <div class="footer-gaming-section">
          <h4>Community</h4>
          <a href="https://discord.gg/bezgelor" target="_blank" rel="noopener">
            <span class="flex items-center gap-2">
              Discord <.icon name="hero-arrow-top-right-on-square-micro" class="size-3 opacity-50" />
            </span>
          </a>
          <a href="https://github.com/bezgelor" target="_blank" rel="noopener">
            <span class="flex items-center gap-2">
              GitHub <.icon name="hero-arrow-top-right-on-square-micro" class="size-3 opacity-50" />
            </span>
          </a>
          <a href="/community#forums">Forums</a>
          <a href="https://reddit.com/r/bezgelor" target="_blank" rel="noopener">
            <span class="flex items-center gap-2">
              Reddit <.icon name="hero-arrow-top-right-on-square-micro" class="size-3 opacity-50" />
            </span>
          </a>
        </div>
        
    <!-- Support Section -->
        <div class="footer-gaming-section">
          <h4>Support</h4>
          <a href="/download#faq">FAQ</a>
          <a href="/download#setup">Setup Guide</a>
          <a href="/about#contact">Contact</a>
          <a href="https://github.com/bezgelor/bezgelor/issues" target="_blank" rel="noopener">
            <span class="flex items-center gap-2">
              Bug Reports
              <.icon name="hero-arrow-top-right-on-square-micro" class="size-3 opacity-50" />
            </span>
          </a>
        </div>
      </div>

      <div class="footer-gaming-bottom">
        <!-- Social Icons -->
        <div class="footer-gaming-social">
          <a href="https://discord.gg/bezgelor" target="_blank" rel="noopener" aria-label="Discord">
            <svg class="size-5" fill="currentColor" viewBox="0 0 24 24">
              <path d="M20.317 4.37a19.791 19.791 0 0 0-4.885-1.515.074.074 0 0 0-.079.037c-.21.375-.444.864-.608 1.25a18.27 18.27 0 0 0-5.487 0 12.64 12.64 0 0 0-.617-1.25.077.077 0 0 0-.079-.037A19.736 19.736 0 0 0 3.677 4.37a.07.07 0 0 0-.032.027C.533 9.046-.32 13.58.099 18.057a.082.082 0 0 0 .031.057 19.9 19.9 0 0 0 5.993 3.03.078.078 0 0 0 .084-.028 14.09 14.09 0 0 0 1.226-1.994.076.076 0 0 0-.041-.106 13.107 13.107 0 0 1-1.872-.892.077.077 0 0 1-.008-.128 10.2 10.2 0 0 0 .372-.292.074.074 0 0 1 .077-.01c3.928 1.793 8.18 1.793 12.062 0a.074.074 0 0 1 .078.01c.12.098.246.198.373.292a.077.077 0 0 1-.006.127 12.299 12.299 0 0 1-1.873.892.077.077 0 0 0-.041.107c.36.698.772 1.362 1.225 1.993a.076.076 0 0 0 .084.028 19.839 19.839 0 0 0 6.002-3.03.077.077 0 0 0 .032-.054c.5-5.177-.838-9.674-3.549-13.66a.061.061 0 0 0-.031-.03zM8.02 15.33c-1.183 0-2.157-1.085-2.157-2.419 0-1.333.956-2.419 2.157-2.419 1.21 0 2.176 1.096 2.157 2.42 0 1.333-.956 2.418-2.157 2.418zm7.975 0c-1.183 0-2.157-1.085-2.157-2.419 0-1.333.955-2.419 2.157-2.419 1.21 0 2.176 1.096 2.157 2.42 0 1.333-.946 2.418-2.157 2.418z" />
            </svg>
          </a>
          <a href="https://github.com/bezgelor" target="_blank" rel="noopener" aria-label="GitHub">
            <svg class="size-5" fill="currentColor" viewBox="0 0 24 24">
              <path
                fill-rule="evenodd"
                clip-rule="evenodd"
                d="M12 2C6.477 2 2 6.484 2 12.017c0 4.425 2.865 8.18 6.839 9.504.5.092.682-.217.682-.483 0-.237-.008-.868-.013-1.703-2.782.605-3.369-1.343-3.369-1.343-.454-1.158-1.11-1.466-1.11-1.466-.908-.62.069-.608.069-.608 1.003.07 1.531 1.032 1.531 1.032.892 1.53 2.341 1.088 2.91.832.092-.647.35-1.088.636-1.338-2.22-.253-4.555-1.113-4.555-4.951 0-1.093.39-1.988 1.029-2.688-.103-.253-.446-1.272.098-2.65 0 0 .84-.27 2.75 1.026A9.564 9.564 0 0112 6.844c.85.004 1.705.115 2.504.337 1.909-1.296 2.747-1.027 2.747-1.027.546 1.379.202 2.398.1 2.651.64.7 1.028 1.595 1.028 2.688 0 3.848-2.339 4.695-4.566 4.943.359.309.678.92.678 1.855 0 1.338-.012 2.419-.012 2.747 0 .268.18.58.688.482A10.019 10.019 0 0022 12.017C22 6.484 17.522 2 12 2z"
              />
            </svg>
          </a>
          <a href="https://twitter.com/bezgelor" target="_blank" rel="noopener" aria-label="Twitter">
            <svg class="size-5" fill="currentColor" viewBox="0 0 24 24">
              <path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z" />
            </svg>
          </a>
          <a href="https://youtube.com/@bezgelor" target="_blank" rel="noopener" aria-label="YouTube">
            <svg class="size-5" fill="currentColor" viewBox="0 0 24 24">
              <path d="M23.498 6.186a3.016 3.016 0 0 0-2.122-2.136C19.505 3.545 12 3.545 12 3.545s-7.505 0-9.377.505A3.017 3.017 0 0 0 .502 6.186C0 8.07 0 12 0 12s0 3.93.502 5.814a3.016 3.016 0 0 0 2.122 2.136c1.871.505 9.376.505 9.376.505s7.505 0 9.377-.505a3.015 3.015 0 0 0 2.122-2.136C24 15.93 24 12 24 12s0-3.93-.502-5.814zM9.545 15.568V8.432L15.818 12l-6.273 3.568z" />
            </svg>
          </a>
        </div>
        
    <!-- Logo and Copyright -->
        <div class="mb-4">
          <span class="text-xl font-bold text-[var(--gaming-cyan)]">BEZGELOR</span>
        </div>
        <p class="mb-2">
          A fan-made WildStar server emulator. Open source and free to play.
        </p>
        <p class="text-xs opacity-60">
          &copy; {DateTime.utc_now().year} Bezgelor Project. Not affiliated with NCSOFT or Carbine Studios.
          <br /> WildStar and all related content are trademarks of NCSOFT Corporation.
        </p>
      </div>
    </footer>
    """
  end
end
