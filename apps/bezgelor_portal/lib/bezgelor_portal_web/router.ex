defmodule BezgelorPortalWeb.Router do
  use BezgelorPortalWeb, :router
  import Phoenix.LiveDashboard.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {BezgelorPortalWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug BezgelorPortalWeb.Plugs.FetchCurrentAccount
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :require_admin_plug do
    plug :fetch_session
    plug :fetch_live_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug BezgelorPortalWeb.Plugs.FetchCurrentAccount
    plug :verify_admin_access
  end

  defp verify_admin_access(conn, _opts) do
    BezgelorPortalWeb.Live.Hooks.admins_only(conn)
  end

  # Public routes (no auth required)
  scope "/", BezgelorPortalWeb do
    pipe_through :browser

    get "/", PageController, :home

    # Feature pages
    get "/features", FeatureController, :index
    get "/features/races", FeatureController, :races
    get "/features/classes", FeatureController, :classes
    get "/features/combat", FeatureController, :combat
    get "/features/housing", FeatureController, :housing
    get "/features/paths", FeatureController, :paths
    get "/features/dungeons", FeatureController, :dungeons

    # Content pages
    get "/about", ContentController, :about
    get "/terms", ContentController, :terms
    get "/privacy", ContentController, :privacy
    get "/download", ContentController, :download
    get "/community", ContentController, :community
    get "/news", ContentController, :news

    # Auth callback (not LiveView)
    get "/auth/callback", AuthController, :callback
  end

  # Auth LiveView routes with auth layout
  live_session :auth,
    layout: {BezgelorPortalWeb.Layouts, :auth} do
    scope "/", BezgelorPortalWeb do
      pipe_through :browser

      live "/login", LoginLive, :index
      live "/register", RegisterLive, :index
      live "/auth/totp-verify", TotpVerifyLive, :index
    end
  end

  # Remaining public routes
  scope "/", BezgelorPortalWeb do
    pipe_through :browser

    get "/verify/:token", VerificationController, :verify
    get "/verify-email-change/:token", EmailChangeController, :verify
    delete "/logout", AuthController, :logout
    # Also allow GET for simple links
    get "/logout", AuthController, :logout
  end

  # Authenticated routes
  live_session :authenticated,
    on_mount: [{BezgelorPortalWeb.Live.Hooks, :require_auth}],
    layout: {BezgelorPortalWeb.Layouts, :app} do
    scope "/", BezgelorPortalWeb do
      pipe_through :browser

      live "/dashboard", DashboardLive, :index
      live "/characters", CharactersLive, :index
      live "/characters/:id", CharacterDetailLive, :show
      live "/settings", SettingsLive, :index
      live "/settings/totp/setup", TotpSetupLive, :index
      live "/settings/totp/disable", TotpDisableLive, :index
    end
  end

  # Admin routes
  live_session :admin,
    on_mount: [{BezgelorPortalWeb.Live.Hooks, :require_admin}] do
    scope "/admin", BezgelorPortalWeb.Admin do
      pipe_through :browser

      live "/", AdminDashboardLive, :index

      # User Management
      live "/users", UsersLive, :index
      live "/users/bans", BansLive, :index
      live "/users/:id", UserDetailLive, :show

      # Character Management
      live "/characters", CharactersLive, :index
      live "/characters/:id", CharacterDetailLive, :show

      # Audit Log
      live "/audit-log", AuditLogLive, :index

      # Economy Management
      live "/economy", EconomyLive, :index

      # Item Database
      live "/items", ItemsLive, :index

      # Role Management
      live "/roles", RolesLive, :index
      live "/roles/:id/edit", RoleEditLive, :edit

      # Event Management
      live "/events", EventsLive, :index
      live "/events/broadcast", BroadcastLive, :index

      # Instance Management
      live "/instances", InstancesLive, :index

      # Server Operations
      live "/server", ServerLive, :index
      live "/server/logs", LogsLive, :index
      live "/settings", SettingsLive, :index

      # Analytics
      live "/analytics", AnalyticsLive, :index

      # Testing Tools (development only)
      live "/testing", TestingToolsLive, :index
    end
  end

  # LiveDashboard for admins (outside live_session, uses plug-based auth)
  scope "/admin" do
    pipe_through [:require_admin_plug]

    live_dashboard "/live-dashboard",
      metrics: BezgelorPortalWeb.Telemetry,
      ecto_repos: [BezgelorDb.Repo],
      ecto_psql_extras_options: [long_running_queries: [threshold: "200 milliseconds"]],
      env_keys: ["POSTGRES_HOST", "POSTGRES_PORT", "MIX_ENV"],
      additional_pages: []
  end

  # Development routes - mailbox preview and tracing
  if Application.compile_env(:bezgelor_portal, :dev_routes) do
    import OrionWeb.Router

    scope "/dev" do
      pipe_through :browser

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end

    # Orion distributed tracing UI
    live_orion("/dev/tracing")
  end
end
