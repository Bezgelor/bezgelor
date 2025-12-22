# LiveDashboard + Telemetry Integration - Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Integrate Phoenix LiveDashboard into Portal with admin-only access, implement a convention-based telemetry discovery system, and add telemetry instrumentation across all umbrella apps.

**Architecture:** LiveDashboard mounts under `/admin/dashboard` protected by existing admin auth hooks. A new `@telemetry_events` module attribute convention allows declaring telemetry events at their source. A mix task scans all apps for these declarations and generates consolidated metrics configuration. Telemetry events are added to key flows: auth, player sessions, combat, and quests.

**Tech Stack:** Phoenix LiveDashboard, Telemetry, telemetry_metrics, telemetry_poller

---

## Task 1: Add LiveDashboard Dependency

**Files:**
- Modify: `apps/bezgelor_portal/mix.exs:45-93`

**Step 1: Add phoenix_live_dashboard to deps**

In `apps/bezgelor_portal/mix.exs`, add to the `deps` list after the Observability section (around line 92):

```elixir
      # LiveDashboard
      {:phoenix_live_dashboard, "~> 0.8"}
```

**Step 2: Run mix deps.get**

Run: `mix deps.get`
Expected: Dependencies fetched successfully

**Step 3: Commit**

```bash
git add apps/bezgelor_portal/mix.exs mix.lock
git commit -m "deps(portal): add phoenix_live_dashboard"
```

---

## Task 2: Create Admin Auth Function for LiveDashboard

**Files:**
- Modify: `apps/bezgelor_portal/lib/bezgelor_portal_web/live/hooks.ex`

**Step 1: Add admins_only/1 function**

Add this function at the end of the module (before the final `end`):

```elixir
  @doc """
  Check if session has admin access for LiveDashboard.

  Used by LiveDashboard's :on_mount option.
  Returns the account ID if admin, halts otherwise.
  """
  def admins_only(conn) do
    account_id = get_session(conn, :current_account_id)

    case account_id && BezgelorDb.Accounts.get_by_id(account_id) do
      nil ->
        conn
        |> Phoenix.Controller.put_flash(:error, "You must be logged in to access this page.")
        |> Phoenix.Controller.redirect(to: "/login")
        |> Plug.Conn.halt()

      account ->
        if has_admin_access?(account) and TOTP.enabled?(account) do
          conn
        else
          conn
          |> Phoenix.Controller.put_flash(:error, "Admin access with 2FA required.")
          |> Phoenix.Controller.redirect(to: "/dashboard")
          |> Plug.Conn.halt()
        end
    end
  end
```

**Step 2: Add import for get_session**

At the top of the module (around line 24), add:

```elixir
  import Plug.Conn, only: [get_session: 2]
```

**Step 3: Verify module compiles**

Run: `mix compile`
Expected: Compiles without errors

**Step 4: Commit**

```bash
git add apps/bezgelor_portal/lib/bezgelor_portal_web/live/hooks.ex
git commit -m "feat(portal): add admins_only/1 function for LiveDashboard auth"
```

---

## Task 3: Add LiveDashboard Route and Admin Integration

**Files:**
- Modify: `apps/bezgelor_portal/lib/bezgelor_portal_web/router.ex`
- Modify: `apps/bezgelor_portal/lib/bezgelor_portal_web/components/layouts.ex`
- Create: `apps/bezgelor_portal/assets/css/live_dashboard.css`

**Step 1: Import LiveDashboard**

Add at the top of `router.ex` (after line 2):

```elixir
  import Phoenix.LiveDashboard.Router
```

**Step 2: Add LiveDashboard route in admin scope**

Add inside the `if Application.compile_env(:bezgelor_portal, :dev_routes)` block (around line 135), or better, add a new scope after the admin live_session (around line 132):

```elixir
  # LiveDashboard for admins
  scope "/admin" do
    pipe_through [:browser, :require_admin_plug]

    live_dashboard "/dashboard",
      metrics: BezgelorPortalWeb.Telemetry,
      ecto_repos: [BezgelorDb.Repo],
      ecto_psql_extras_options: [long_running_queries: [threshold: "200 milliseconds"]],
      env_keys: ["POSTGRES_HOST", "POSTGRES_PORT", "MIX_ENV"],
      on_mount: {BezgelorPortalWeb.Live.Hooks, :require_admin},
      csp_nonce_assign_key: :csp_nonce,
      additional_pages: []
  end
```

**Step 3: Create the require_admin_plug pipeline**

Add a new pipeline after the `:api` pipeline (around line 16):

```elixir
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
```

**Step 4: Add Live Dashboard link to admin sidebar**

In `apps/bezgelor_portal/lib/bezgelor_portal_web/components/layouts.ex`, find the "Server" sidebar section (around line 258) and add the Live Dashboard link:

```elixir
        <.sidebar_section
          title="Server"
          icon="hero-server"
          permission_set={@permission_set}
          links={[
            %{href: "/admin/server", label: "Server Status", permission: "server.view_logs"},
            %{href: "/admin/dashboard", label: "Live Dashboard", permission: "server.view_logs"},
            %{href: "/admin/server/logs", label: "Logs", permission: "server.view_logs"},
            %{href: "/admin/settings", label: "Server Settings", permission: "server.settings"}
          ]}
        />
```

**Step 5: Create LiveDashboard custom CSS for admin look & feel**

Create `apps/bezgelor_portal/assets/css/live_dashboard.css`:

```css
/*
 * LiveDashboard Styling - Adopts admin panel look & feel
 * Uses DaisyUI/Tailwind variables for consistency
 */

/* Override LiveDashboard colors to match admin theme */
[data-dashboard] {
  --ld-bg-color: oklch(var(--b2));
  --ld-text-color: oklch(var(--bc));
  --ld-primary-color: oklch(var(--p));
  --ld-success-color: oklch(var(--su));
  --ld-warning-color: oklch(var(--wa));
  --ld-danger-color: oklch(var(--er));
  --ld-border-color: oklch(var(--b3));
  --ld-card-bg: oklch(var(--b1));
}

/* Card styling to match admin cards */
[data-dashboard] .card,
[data-dashboard] .ld-card {
  background: oklch(var(--b1));
  border-radius: var(--rounded-box, 1rem);
  box-shadow: 0 1px 3px 0 rgb(0 0 0 / 0.1), 0 1px 2px -1px rgb(0 0 0 / 0.1);
  border: 1px solid oklch(var(--b3));
}

/* Navigation tabs styling */
[data-dashboard] nav[role="tablist"] a {
  color: oklch(var(--bc) / 0.7);
  transition: color 0.2s;
}

[data-dashboard] nav[role="tablist"] a:hover {
  color: oklch(var(--p));
}

[data-dashboard] nav[role="tablist"] a[aria-current="page"] {
  color: oklch(var(--p));
  border-bottom-color: oklch(var(--p));
}

/* Table styling to match DaisyUI tables */
[data-dashboard] table {
  width: 100%;
  border-collapse: collapse;
}

[data-dashboard] table th {
  background: oklch(var(--b2));
  color: oklch(var(--bc) / 0.7);
  font-size: 0.75rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  padding: 0.75rem 1rem;
  text-align: left;
}

[data-dashboard] table td {
  padding: 0.75rem 1rem;
  border-bottom: 1px solid oklch(var(--b3));
}

[data-dashboard] table tr:hover td {
  background: oklch(var(--b2) / 0.5);
}

/* Button styling */
[data-dashboard] button,
[data-dashboard] .btn {
  background: oklch(var(--p));
  color: oklch(var(--pc));
  border-radius: var(--rounded-btn, 0.5rem);
  padding: 0.5rem 1rem;
  font-weight: 500;
  transition: background 0.2s;
}

[data-dashboard] button:hover,
[data-dashboard] .btn:hover {
  background: oklch(var(--p) / 0.8);
}

/* Charts and metrics styling */
[data-dashboard] .metric-value {
  font-size: 1.5rem;
  font-weight: 700;
  color: oklch(var(--p));
}

/* Info boxes */
[data-dashboard] .alert-info {
  background: oklch(var(--in) / 0.1);
  border: 1px solid oklch(var(--in) / 0.3);
  color: oklch(var(--in));
}

[data-dashboard] .alert-warning {
  background: oklch(var(--wa) / 0.1);
  border: 1px solid oklch(var(--wa) / 0.3);
  color: oklch(var(--wa));
}

[data-dashboard] .alert-error {
  background: oklch(var(--er) / 0.1);
  border: 1px solid oklch(var(--er) / 0.3);
  color: oklch(var(--er));
}
```

**Step 6: Import LiveDashboard CSS in main stylesheet**

In `apps/bezgelor_portal/assets/css/app.css`, add at the end:

```css
/* LiveDashboard custom styling */
@import "./live_dashboard.css";
```

**Step 7: Verify routes compile**

Run: `mix compile`
Expected: Compiles without errors

**Step 8: Commit**

```bash
git add apps/bezgelor_portal/lib/bezgelor_portal_web/router.ex \
        apps/bezgelor_portal/lib/bezgelor_portal_web/components/layouts.ex \
        apps/bezgelor_portal/assets/css/live_dashboard.css \
        apps/bezgelor_portal/assets/css/app.css
git commit -m "feat(portal): add LiveDashboard route with admin styling"
```

---

## Task 4: Create Telemetry Event Behaviour

**Files:**
- Create: `apps/bezgelor_core/lib/bezgelor_core/telemetry_event.ex`
- Test: `apps/bezgelor_core/test/telemetry_event_test.exs`

**Step 1: Write the test**

```elixir
# apps/bezgelor_core/test/telemetry_event_test.exs
defmodule BezgelorCore.TelemetryEventTest do
  use ExUnit.Case, async: true

  alias BezgelorCore.TelemetryEvent

  describe "validate/1" do
    test "validates a correct event definition" do
      event = %{
        event: [:bezgelor, :auth, :login],
        measurements: [:duration_ms, :success],
        tags: [:account_id],
        description: "User login attempt",
        domain: :auth
      }

      assert :ok = TelemetryEvent.validate(event)
    end

    test "returns error for missing event key" do
      event = %{measurements: [:count], tags: [], description: "test", domain: :test}
      assert {:error, "missing required key: event"} = TelemetryEvent.validate(event)
    end

    test "returns error for non-list event" do
      event = %{event: "bad", measurements: [], tags: [], description: "test", domain: :test}
      assert {:error, "event must be a list of atoms"} = TelemetryEvent.validate(event)
    end
  end

  describe "to_metric_def/1" do
    test "converts event to telemetry_metrics summary definition" do
      event = %{
        event: [:bezgelor, :auth, :login],
        measurements: [:duration_ms],
        tags: [:account_id],
        description: "Login duration",
        domain: :auth
      }

      result = TelemetryEvent.to_metric_def(event, :summary)

      assert result.name == "bezgelor.auth.login.duration_ms"
      assert result.measurement == :duration_ms
      assert result.tags == [:account_id]
      assert result.description == "Login duration"
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test apps/bezgelor_core/test/telemetry_event_test.exs -v`
Expected: FAIL with "TelemetryEvent not defined"

**Step 3: Write the module**

```elixir
# apps/bezgelor_core/lib/bezgelor_core/telemetry_event.ex
defmodule BezgelorCore.TelemetryEvent do
  @moduledoc """
  Defines the structure for telemetry event declarations.

  ## Usage

  Add `@telemetry_events` attribute to modules that emit telemetry:

      @telemetry_events [
        %{
          event: [:bezgelor, :auth, :login],
          measurements: [:duration_ms],
          tags: [:account_id, :success],
          description: "User login attempt",
          domain: :auth
        }
      ]

  Then use the mix task to discover and generate metrics config.
  """

  @type t :: %{
          event: [atom()],
          measurements: [atom()],
          tags: [atom()],
          description: String.t(),
          domain: atom()
        }

  @required_keys [:event, :measurements, :tags, :description, :domain]

  @doc "Validate an event definition map."
  @spec validate(map()) :: :ok | {:error, String.t()}
  def validate(event) when is_map(event) do
    with :ok <- validate_required_keys(event),
         :ok <- validate_event_format(event.event),
         :ok <- validate_list_of_atoms(event.measurements, "measurements"),
         :ok <- validate_list_of_atoms(event.tags, "tags"),
         :ok <- validate_string(event.description, "description"),
         :ok <- validate_atom(event.domain, "domain") do
      :ok
    end
  end

  defp validate_required_keys(event) do
    missing = @required_keys -- Map.keys(event)

    case missing do
      [] -> :ok
      [key | _] -> {:error, "missing required key: #{key}"}
    end
  end

  defp validate_event_format(event) when is_list(event) do
    if Enum.all?(event, &is_atom/1) do
      :ok
    else
      {:error, "event must be a list of atoms"}
    end
  end

  defp validate_event_format(_), do: {:error, "event must be a list of atoms"}

  defp validate_list_of_atoms(list, name) when is_list(list) do
    if Enum.all?(list, &is_atom/1) do
      :ok
    else
      {:error, "#{name} must be a list of atoms"}
    end
  end

  defp validate_list_of_atoms(_, name), do: {:error, "#{name} must be a list"}

  defp validate_string(value, _name) when is_binary(value), do: :ok
  defp validate_string(_, name), do: {:error, "#{name} must be a string"}

  defp validate_atom(value, _name) when is_atom(value), do: :ok
  defp validate_atom(_, name), do: {:error, "#{name} must be an atom"}

  @doc """
  Convert an event definition to a telemetry_metrics metric definition.

  Returns a struct-like map that can be used with Telemetry.Metrics.
  """
  @spec to_metric_def(t(), :summary | :counter | :last_value | :sum) :: map()
  def to_metric_def(event, metric_type \\ :summary) do
    event_name = Enum.join(event.event, ".")

    for measurement <- event.measurements do
      %{
        type: metric_type,
        name: "#{event_name}.#{measurement}",
        event_name: event.event,
        measurement: measurement,
        tags: event.tags,
        description: event.description,
        domain: event.domain
      }
    end
  end

  @doc "Get the event name as a dot-separated string."
  @spec event_name(t()) :: String.t()
  def event_name(event) do
    Enum.join(event.event, ".")
  end
end
```

**Step 4: Run test to verify it passes**

Run: `mix test apps/bezgelor_core/test/telemetry_event_test.exs -v`
Expected: PASS

**Step 5: Commit**

```bash
git add apps/bezgelor_core/lib/bezgelor_core/telemetry_event.ex apps/bezgelor_core/test/telemetry_event_test.exs
git commit -m "feat(core): add TelemetryEvent module for event declarations"
```

---

## Task 5: Create Telemetry Discovery Mix Task

**Files:**
- Create: `apps/bezgelor_dev/lib/mix/tasks/bezgelor.telemetry.discover.ex`
- Test: `apps/bezgelor_dev/test/tasks/telemetry_discover_test.exs`

**Step 1: Write the test**

```elixir
# apps/bezgelor_dev/test/tasks/telemetry_discover_test.exs
defmodule Mix.Tasks.Bezgelor.Telemetry.DiscoverTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Bezgelor.Telemetry.Discover

  describe "extract_events_from_module/1" do
    test "extracts @telemetry_events from module" do
      defmodule TestModuleWithEvents do
        @telemetry_events [
          %{
            event: [:test, :event],
            measurements: [:count],
            tags: [:tag1],
            description: "Test event",
            domain: :test
          }
        ]

        def telemetry_events, do: @telemetry_events
      end

      events = Discover.extract_events_from_module(TestModuleWithEvents)
      assert length(events) == 1
      assert hd(events).event == [:test, :event]
    end

    test "returns empty list for module without events" do
      defmodule TestModuleWithoutEvents do
        def some_function, do: :ok
      end

      events = Discover.extract_events_from_module(TestModuleWithoutEvents)
      assert events == []
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test apps/bezgelor_dev/test/tasks/telemetry_discover_test.exs -v`
Expected: FAIL with module not defined

**Step 3: Write the mix task**

```elixir
# apps/bezgelor_dev/lib/mix/tasks/bezgelor.telemetry.discover.ex
defmodule Mix.Tasks.Bezgelor.Telemetry.Discover do
  @moduledoc """
  Discovers telemetry events declared across all umbrella apps.

  Scans for modules with `@telemetry_events` attribute and generates
  a consolidated metrics configuration.

  ## Usage

      mix bezgelor.telemetry.discover

  ## Options

      --output PATH   Output file path (default: prints to stdout)
      --format FORMAT Output format: elixir, json (default: elixir)
  """

  use Mix.Task

  alias BezgelorCore.TelemetryEvent

  @shortdoc "Discover telemetry events across all apps"

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: [output: :string, format: :string])
    format = Keyword.get(opts, :format, "elixir")
    output = Keyword.get(opts, :output)

    # Ensure all apps are compiled
    Mix.Task.run("compile", ["--no-warnings-as-errors"])

    # Get all modules from umbrella apps
    apps = [:bezgelor_core, :bezgelor_db, :bezgelor_protocol, :bezgelor_world, :bezgelor_auth, :bezgelor_realm, :bezgelor_portal]

    events =
      apps
      |> Enum.flat_map(&get_app_modules/1)
      |> Enum.flat_map(&extract_events_from_module/1)
      |> Enum.map(&add_source_info/1)

    # Validate all events
    invalid = Enum.reject(events, fn e -> TelemetryEvent.validate(e) == :ok end)

    if invalid != [] do
      Mix.shell().error("Invalid telemetry events found:")
      Enum.each(invalid, fn e ->
        {:error, msg} = TelemetryEvent.validate(e)
        Mix.shell().error("  - #{inspect(e.event)}: #{msg}")
      end)
      exit({:shutdown, 1})
    end

    # Group by domain
    by_domain = Enum.group_by(events, & &1.domain)

    # Output
    output_content = format_output(by_domain, format)

    if output do
      File.write!(output, output_content)
      Mix.shell().info("Wrote #{length(events)} events to #{output}")
    else
      Mix.shell().info(output_content)
    end

    # Summary
    Mix.shell().info("\nSummary:")
    Enum.each(by_domain, fn {domain, domain_events} ->
      Mix.shell().info("  #{domain}: #{length(domain_events)} events")
    end)
    Mix.shell().info("  Total: #{length(events)} events")
  end

  @doc "Extract @telemetry_events from a module."
  def extract_events_from_module(module) do
    if function_exported?(module, :telemetry_events, 0) do
      module.telemetry_events()
    else
      try do
        module.__info__(:attributes)
        |> Keyword.get_values(:telemetry_events)
        |> List.flatten()
      rescue
        _ -> []
      end
    end
  end

  defp get_app_modules(app) do
    case :application.get_key(app, :modules) do
      {:ok, modules} -> modules
      :undefined -> []
    end
  end

  defp add_source_info(event) do
    Map.put_new(event, :source_module, "unknown")
  end

  defp format_output(by_domain, "elixir") do
    """
    # Auto-generated by mix bezgelor.telemetry.discover
    # Do not edit manually - regenerate with: mix bezgelor.telemetry.discover --output <path>

    defmodule BezgelorPortal.Telemetry.DiscoveredMetrics do
      @moduledoc \"\"\"
      Auto-discovered telemetry metrics from all umbrella apps.
      \"\"\"

      import Telemetry.Metrics

      def metrics do
        [
    #{format_metrics(by_domain)}
        ]
      end
    end
    """
  end

  defp format_output(by_domain, "json") do
    Jason.encode!(by_domain, pretty: true)
  end

  defp format_output(by_domain, _), do: format_output(by_domain, "elixir")

  defp format_metrics(by_domain) do
    by_domain
    |> Enum.flat_map(fn {domain, events} ->
      [
        "      # #{String.capitalize(to_string(domain))} Metrics"
        | Enum.flat_map(events, &format_event_metrics/1)
      ]
    end)
    |> Enum.join(",\n")
  end

  defp format_event_metrics(event) do
    event_name = Enum.join(event.event, ".")

    Enum.map(event.measurements, fn measurement ->
      tags = inspect(event.tags)
      """
            summary("#{event_name}.#{measurement}",
              tags: #{tags},
              description: "#{event.description}"
            )
      """
      |> String.trim()
    end)
  end
end
```

**Step 4: Run test to verify it passes**

Run: `mix test apps/bezgelor_dev/test/tasks/telemetry_discover_test.exs -v`
Expected: PASS

**Step 5: Commit**

```bash
git add apps/bezgelor_dev/lib/mix/tasks/bezgelor.telemetry.discover.ex apps/bezgelor_dev/test/tasks/telemetry_discover_test.exs
git commit -m "feat(dev): add mix bezgelor.telemetry.discover task"
```

---

## Task 6: Add Auth Telemetry Events

**Files:**
- Modify: `apps/bezgelor_auth/lib/bezgelor_auth/sts/handler/auth_handler.ex`

**Step 1: Add telemetry_events declaration**

Add after the `@moduledoc` (around line 10):

```elixir
  @telemetry_events [
    %{
      event: [:bezgelor, :auth, :login_complete],
      measurements: [:duration_ms, :success],
      tags: [:account_id, :failure_reason],
      description: "Authentication attempt completed",
      domain: :auth
    }
  ]

  def telemetry_events, do: @telemetry_events
```

**Step 2: Find the login success point and add telemetry**

In the `handle_request_game_token/2` function (around line 131), add telemetry emission after successful token generation:

```elixir
    # After creating the session key, before sending response:
    :telemetry.execute(
      [:bezgelor, :auth, :login_complete],
      %{duration_ms: 0, success: 1},
      %{account_id: state.account_id, failure_reason: nil}
    )
```

**Step 3: Add telemetry for login failures**

In `handle_key_data/2` where authentication fails (around line 95), add:

```elixir
    # In the {:error, :invalid_proof} branch:
    :telemetry.execute(
      [:bezgelor, :auth, :login_complete],
      %{duration_ms: 0, success: 0},
      %{account_id: state.account_id, failure_reason: :invalid_credentials}
    )
```

**Step 4: Verify module compiles**

Run: `mix compile`
Expected: Compiles without errors

**Step 5: Commit**

```bash
git add apps/bezgelor_auth/lib/bezgelor_auth/sts/handler/auth_handler.ex
git commit -m "feat(auth): add telemetry for login events"
```

---

## Task 7: Add Player Session Telemetry Events

**Files:**
- Modify: `apps/bezgelor_world/lib/bezgelor_world/world_manager.ex`

**Step 1: Add telemetry_events declaration**

Add after the `@moduledoc` (around line 31):

```elixir
  @telemetry_events [
    %{
      event: [:bezgelor, :server, :player_connected],
      measurements: [:count],
      tags: [:character_id, :character_name],
      description: "Player connected to world server",
      domain: :server
    },
    %{
      event: [:bezgelor, :server, :player_disconnected],
      measurements: [:count, :session_duration_seconds],
      tags: [:character_id, :character_name, :disconnect_reason],
      description: "Player disconnected from world server",
      domain: :server
    },
    %{
      event: [:bezgelor, :server, :active_sessions],
      measurements: [:session_count],
      tags: [],
      description: "Current active player session count",
      domain: :server
    }
  ]

  def telemetry_events, do: @telemetry_events
```

**Step 2: Add telemetry in register_session callback**

In the `handle_call({:register_session, ...}, ...)` callback, add after updating state:

```elixir
    :telemetry.execute(
      [:bezgelor, :server, :player_connected],
      %{count: 1},
      %{character_id: character_id, character_name: character_name || "unknown"}
    )
```

**Step 3: Add telemetry in unregister_session callback**

In the `handle_cast({:unregister_session, ...}, ...)` callback, add before removing from state:

```elixir
    case Map.get(state.sessions, account_id) do
      nil -> :ok
      session ->
        :telemetry.execute(
          [:bezgelor, :server, :player_disconnected],
          %{count: 1, session_duration_seconds: 0},
          %{
            character_id: session.character_id,
            character_name: session.character_name || "unknown",
            disconnect_reason: :normal
          }
        )
    end
```

**Step 4: Verify module compiles**

Run: `mix compile`
Expected: Compiles without errors

**Step 5: Commit**

```bash
git add apps/bezgelor_world/lib/bezgelor_world/world_manager.ex
git commit -m "feat(world): add telemetry for player connect/disconnect"
```

---

## Task 8: Add World Entry Telemetry

**Files:**
- Modify: `apps/bezgelor_protocol/lib/bezgelor_protocol/handler/world_entry_handler.ex`

**Step 1: Add telemetry_events declaration**

Add after the `@moduledoc`:

```elixir
  @telemetry_events [
    %{
      event: [:bezgelor, :player, :world_entered],
      measurements: [:duration_ms],
      tags: [:character_id, :character_name, :zone_id, :world_id],
      description: "Player entered the game world",
      domain: :player
    }
  ]

  def telemetry_events, do: @telemetry_events
```

**Step 2: Add telemetry at end of handle/2 after successful world entry**

After the player is fully spawned, add:

```elixir
    :telemetry.execute(
      [:bezgelor, :player, :world_entered],
      %{duration_ms: 0},
      %{
        character_id: state.session_data[:character_id],
        character_name: state.session_data[:character_name] || "unknown",
        zone_id: character.world_zone_id,
        world_id: character.world_id
      }
    )
```

**Step 3: Verify module compiles**

Run: `mix compile`
Expected: Compiles without errors

**Step 4: Commit**

```bash
git add apps/bezgelor_protocol/lib/bezgelor_protocol/handler/world_entry_handler.ex
git commit -m "feat(protocol): add telemetry for world entry"
```

---

## Task 9: Add Combat Telemetry Events

**Files:**
- Modify: `apps/bezgelor_world/lib/bezgelor_world/handler/spell_handler.ex`

**Step 1: Add telemetry_events declaration**

Add after the `@moduledoc`:

```elixir
  @telemetry_events [
    %{
      event: [:bezgelor, :combat, :spell_cast],
      measurements: [:count, :power_cost],
      tags: [:character_id, :spell_id, :success, :failure_reason],
      description: "Spell cast attempt",
      domain: :combat
    },
    %{
      event: [:bezgelor, :combat, :damage_applied],
      measurements: [:damage_amount],
      tags: [:attacker_id, :target_type, :spell_id, :was_crit, :was_killing_blow],
      description: "Damage applied to target",
      domain: :combat
    }
  ]

  def telemetry_events, do: @telemetry_events
```

**Step 2: Add telemetry after spell cast validation**

In the spell cast handling, after determining success/failure:

```elixir
    :telemetry.execute(
      [:bezgelor, :combat, :spell_cast],
      %{count: 1, power_cost: 0},
      %{
        character_id: character_id,
        spell_id: spell_id,
        success: success?,
        failure_reason: failure_reason
      }
    )
```

**Step 3: Add telemetry after damage is applied**

In the damage application code:

```elixir
    :telemetry.execute(
      [:bezgelor, :combat, :damage_applied],
      %{damage_amount: damage},
      %{
        attacker_id: attacker_id,
        target_type: target_type,
        spell_id: spell_id,
        was_crit: was_crit?,
        was_killing_blow: killing_blow?
      }
    )
```

**Step 4: Verify module compiles**

Run: `mix compile`
Expected: Compiles without errors

**Step 5: Commit**

```bash
git add apps/bezgelor_world/lib/bezgelor_world/handler/spell_handler.ex
git commit -m "feat(world): add telemetry for combat events"
```

---

## Task 10: Add Quest Telemetry Events

**Files:**
- Modify: `apps/bezgelor_world/lib/bezgelor_world/handler/quest_handler.ex`

**Step 1: Add telemetry_events declaration**

Add after the `@moduledoc`:

```elixir
  @telemetry_events [
    %{
      event: [:bezgelor, :quest, :completed],
      measurements: [:count, :xp_reward, :gold_reward],
      tags: [:character_id, :quest_id],
      description: "Quest completed",
      domain: :quest
    },
    %{
      event: [:bezgelor, :quest, :abandoned],
      measurements: [:count],
      tags: [:character_id, :quest_id],
      description: "Quest abandoned",
      domain: :quest
    }
  ]

  def telemetry_events, do: @telemetry_events
```

**Step 2: Add telemetry in quest completion handler**

After successful quest turn-in:

```elixir
    :telemetry.execute(
      [:bezgelor, :quest, :completed],
      %{count: 1, xp_reward: xp_reward, gold_reward: gold_reward},
      %{character_id: character_id, quest_id: quest_id}
    )
```

**Step 3: Add telemetry in quest abandon handler**

After successful quest abandonment:

```elixir
    :telemetry.execute(
      [:bezgelor, :quest, :abandoned],
      %{count: 1},
      %{character_id: character_id, quest_id: quest_id}
    )
```

**Step 4: Verify module compiles**

Run: `mix compile`
Expected: Compiles without errors

**Step 5: Commit**

```bash
git add apps/bezgelor_world/lib/bezgelor_world/handler/quest_handler.ex
git commit -m "feat(world): add telemetry for quest events"
```

---

## Task 11: Add Creature Kill Telemetry

**Files:**
- Modify: `apps/bezgelor_world/lib/bezgelor_world/creature_manager.ex`

**Step 1: Add telemetry_events declaration**

Add after the `@moduledoc`:

```elixir
  @telemetry_events [
    %{
      event: [:bezgelor, :combat, :creature_killed],
      measurements: [:count],
      tags: [:creature_id, :creature_template_id, :killer_id, :zone_id],
      description: "Creature killed",
      domain: :combat
    }
  ]

  def telemetry_events, do: @telemetry_events
```

**Step 2: Add telemetry when creature dies**

In the damage handling where creature health reaches 0:

```elixir
    :telemetry.execute(
      [:bezgelor, :combat, :creature_killed],
      %{count: 1},
      %{
        creature_id: creature_guid,
        creature_template_id: creature.template_id,
        killer_id: killer_id,
        zone_id: zone_id
      }
    )
```

**Step 3: Verify module compiles**

Run: `mix compile`
Expected: Compiles without errors

**Step 4: Commit**

```bash
git add apps/bezgelor_world/lib/bezgelor_world/creature_manager.ex
git commit -m "feat(world): add telemetry for creature kills"
```

---

## Task 12: Add Periodic Server Stats via Telemetry Poller

**Files:**
- Modify: `apps/bezgelor_portal/lib/bezgelor_portal_web/telemetry.ex`

**Step 1: Add periodic measurement function**

Add after the `metrics/0` function:

```elixir
  defp periodic_measurements do
    [
      # Server stats - emitted every 10 seconds
      {__MODULE__, :emit_server_stats, []}
    ]
  end

  @doc false
  def emit_server_stats do
    session_count =
      try do
        BezgelorWorld.WorldManager.session_count()
      rescue
        _ -> 0
      end

    :telemetry.execute(
      [:bezgelor, :server, :active_sessions],
      %{session_count: session_count},
      %{}
    )
  end
```

**Step 2: Add the metric to metrics/0**

Add to the metrics list:

```elixir
      # Server Stats (periodic)
      last_value("bezgelor.server.active_sessions.session_count",
        description: "Current active player sessions"
      ),
```

**Step 3: Verify module compiles**

Run: `mix compile`
Expected: Compiles without errors

**Step 4: Commit**

```bash
git add apps/bezgelor_portal/lib/bezgelor_portal_web/telemetry.ex
git commit -m "feat(portal): add periodic server stats telemetry"
```

---

## Task 13: Update Telemetry Metrics Configuration

**Files:**
- Modify: `apps/bezgelor_portal/lib/bezgelor_portal_web/telemetry.ex`

**Step 1: Add all new metrics to metrics/0**

Add to the metrics list after the existing client metrics:

```elixir
      # Authentication Metrics
      counter("bezgelor.auth.login_complete.success",
        tags: [:account_id],
        description: "Successful logins"
      ),
      counter("bezgelor.auth.login_complete.duration_ms",
        tags: [:account_id, :failure_reason],
        description: "Login attempts"
      ),

      # Player Session Metrics
      counter("bezgelor.server.player_connected.count",
        tags: [:character_name],
        description: "Player connections"
      ),
      counter("bezgelor.server.player_disconnected.count",
        tags: [:character_name, :disconnect_reason],
        description: "Player disconnections"
      ),
      summary("bezgelor.server.player_disconnected.session_duration_seconds",
        tags: [:character_name],
        description: "Session duration at disconnect"
      ),

      # World Entry Metrics
      summary("bezgelor.player.world_entered.duration_ms",
        tags: [:zone_id, :world_id],
        description: "World entry latency"
      ),

      # Combat Metrics
      counter("bezgelor.combat.spell_cast.count",
        tags: [:spell_id, :success],
        description: "Spell casts"
      ),
      sum("bezgelor.combat.damage_applied.damage_amount",
        tags: [:target_type, :was_crit],
        description: "Total damage dealt"
      ),
      counter("bezgelor.combat.creature_killed.count",
        tags: [:creature_template_id, :zone_id],
        description: "Creatures killed"
      ),

      # Quest Metrics
      counter("bezgelor.quest.completed.count",
        tags: [:quest_id],
        description: "Quests completed"
      ),
      sum("bezgelor.quest.completed.xp_reward",
        tags: [:quest_id],
        description: "XP from quest completions"
      ),
      counter("bezgelor.quest.abandoned.count",
        tags: [:quest_id],
        description: "Quests abandoned"
      ),
```

**Step 2: Verify module compiles**

Run: `mix compile`
Expected: Compiles without errors

**Step 3: Commit**

```bash
git add apps/bezgelor_portal/lib/bezgelor_portal_web/telemetry.ex
git commit -m "feat(portal): add all telemetry metrics to LiveDashboard"
```

---

## Task 14: Run Full Test Suite

**Step 1: Run all tests**

Run: `mix test`
Expected: All tests pass

**Step 2: Fix any failures**

Address test failures as they arise.

**Step 3: Commit fixes if needed**

```bash
git add -A
git commit -m "fix: address test failures from telemetry integration"
```

---

## Task 15: Run Telemetry Discovery

**Step 1: Run the discovery task**

Run: `mix bezgelor.telemetry.discover`
Expected: Shows summary of all discovered events by domain

**Step 2: Verify output**

Should show events for:
- auth: 1 event (login_complete)
- server: 3 events (player_connected, player_disconnected, active_sessions)
- player: 1 event (world_entered)
- combat: 3 events (spell_cast, damage_applied, creature_killed)
- quest: 2 events (completed, abandoned)

**Step 3: Commit**

No commit needed - verification only.

---

## Task 16: Final Verification

**Step 1: Start the server**

Run: `mix phx.server`

**Step 2: Login as admin and verify LiveDashboard**

1. Navigate to `http://localhost:4000/login`
2. Login with an admin account that has TOTP enabled
3. Navigate to `http://localhost:4000/admin/dashboard`
4. Verify dashboard loads with:
   - Home tab with system info
   - Metrics tab with all configured metrics
   - Ecto tab with database stats
   - OS Mon tab with system resources

**Step 3: Verify non-admin access is blocked**

1. Logout
2. Try to access `http://localhost:4000/admin/dashboard` directly
3. Verify redirect to login

**Step 4: Commit any final fixes**

```bash
git add -A
git commit -m "feat: complete LiveDashboard + Telemetry integration"
```

---

## Summary

| Task | Description |
|------|-------------|
| 1 | Add LiveDashboard dependency |
| 2 | Create admin auth function |
| 3 | Add LiveDashboard route |
| 4 | Create TelemetryEvent module |
| 5 | Create discovery mix task |
| 6 | Add auth telemetry |
| 7 | Add player session telemetry |
| 8 | Add world entry telemetry |
| 9 | Add combat telemetry |
| 10 | Add quest telemetry |
| 11 | Add creature kill telemetry |
| 12 | Add periodic server stats |
| 13 | Update telemetry metrics config |
| 14 | Run test suite |
| 15 | Run telemetry discovery |
| 16 | Final verification |
