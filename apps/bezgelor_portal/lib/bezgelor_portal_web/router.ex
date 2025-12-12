defmodule BezgelorPortalWeb.Router do
  use BezgelorPortalWeb, :router

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

  # Public routes (no auth required)
  scope "/", BezgelorPortalWeb do
    pipe_through :browser

    get "/", PageController, :home

    # Auth routes
    live "/login", LoginLive, :index
    live "/register", RegisterLive, :index
    live "/auth/totp-verify", TotpVerifyLive, :index
    get "/verify/:token", VerificationController, :verify
    get "/verify-email-change/:token", EmailChangeController, :verify
    get "/auth/callback", AuthController, :callback
    delete "/logout", AuthController, :logout
    get "/logout", AuthController, :logout  # Also allow GET for simple links
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
      live "/users/:id", UserDetailLive, :show

      # Character Management
      live "/characters", CharactersLive, :index
      live "/characters/:id", CharacterDetailLive, :show

      # Audit Log
      live "/audit-log", AuditLogLive, :index

      # Economy Management
      live "/economy", EconomyLive, :index

      # Role Management
      live "/roles", RolesLive, :index
      live "/roles/:id/edit", RoleEditLive, :edit

      # Event Management
      live "/events", EventsLive, :index

      # Instance Management
      live "/instances", InstancesLive, :index

      # Server Operations
      live "/server", ServerLive, :index

      # Analytics
      live "/analytics", AnalyticsLive, :index
    end
  end

  # Development routes - mailbox preview and tracing
  if Application.compile_env(:bezgelor_portal, :dev_routes) do
    scope "/dev" do
      pipe_through :browser

      forward "/mailbox", Plug.Swoosh.MailboxPreview

      # Orion distributed tracing UI
      live "/tracing", Orion.LiveView
    end
  end
end
