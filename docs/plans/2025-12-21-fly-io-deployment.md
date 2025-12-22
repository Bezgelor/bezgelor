# Fly.io Deployment Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Configure Bezgelor for single-app deployment on Fly.io with all services in one container.

**Architecture:** All services (Portal HTTP, Auth/Realm/World TCP) run in a single Fly machine. Fly Postgres provides the database. Release builds use multi-stage Docker with Elixir 1.17/OTP 27.

**Tech Stack:** Elixir releases, Docker multi-stage builds, Fly.io, Fly Postgres

**Memory Analysis:**
- Game data (1GB JSON → ~2-3GB in ETS)
- BEAM VM base: ~200MB
- Phoenix/Cowboy: ~100MB
- GenServers (World, Zone, Sessions): ~200MB base
- Database connections (pool 10): ~50MB
- **Recommended: 4GB RAM** (leaves ~500MB-1GB headroom)
- **Monitor and scale:** If memory pressure occurs under load, scale to 6GB with `fly scale memory 6144`

**Security Notes:**
- `ssl_opts: [verify: :verify_none]` is used for Fly Postgres connections. This disables certificate verification but is acceptable for Fly's internal network where connections are already encrypted. Document this tradeoff.
- Dev CLOAK_KEY exists in config.exs with a default value for local development. Production MUST use a real secret via environment variable.

---

## Task 1: Add Release Configuration and Umbrella Aliases to mix.exs

**Files:**
- Modify: `mix.exs`

**Step 1: Add releases function and aliases to mix.exs**

Add `releases: releases()` and `aliases: aliases()` to the project list. Create both functions.

**Note:** Exclude `bezgelor_dev` - it's a development-only app.

**CRITICAL:** The `assets.setup` and `assets.deploy` aliases are defined in `apps/bezgelor_portal/mix.exs`, not at the umbrella level. We must add umbrella-level aliases that delegate to the portal app, or the Dockerfile build will fail.

```elixir
def project do
  [
    apps_path: "apps",
    version: "0.1.0",
    start_permanent: Mix.env() == :prod,
    deps: deps(),
    aliases: aliases(),
    listeners: [Phoenix.CodeReloader],
    releases: releases()
  ]
end

# Umbrella-level aliases that delegate to child apps
# CRITICAL: assets.setup and assets.deploy are defined in bezgelor_portal,
# so we must delegate from the umbrella level for Docker builds.
defp aliases do
  [
    "assets.setup": ["cmd --app bezgelor_portal mix assets.setup"],
    "assets.deploy": ["cmd --app bezgelor_portal mix assets.deploy"]
  ]
end

defp releases do
  [
    bezgelor: [
      applications: [
        bezgelor_portal: :permanent,
        bezgelor_auth: :permanent,
        bezgelor_realm: :permanent,
        bezgelor_world: :permanent,
        bezgelor_api: :permanent,
        bezgelor_db: :permanent,
        bezgelor_data: :permanent,
        bezgelor_protocol: :permanent,
        bezgelor_crypto: :permanent,
        bezgelor_core: :permanent
        # Note: bezgelor_dev excluded - dev-only tools
      ],
      include_executables_for: [:unix],
      # CRITICAL: Include overlay scripts (migrate, server)
      overlay: "rel/overlays"
    ]
  ]
end
```

**Step 2: Verify release configuration and aliases**

Run: `mix release --help`
Expected: No errors, shows release help

Run: `mix help assets.setup`
Expected: Shows the alias definition

**Step 3: Commit**

```bash
git add mix.exs
git commit -m "chore: add release configuration and asset aliases for Fly.io deployment"
```

---

## Task 1b: Fix Broken prod.exs Configuration

**Files:**
- Modify: `config/prod.exs`

**Problem:** The current prod.exs has a syntax error where `exclude:` is outside the `force_ssl` block. This is broken code that will cause issues.

**Current broken code (lines 14-19):**
```elixir
config :bezgelor_portal, BezgelorPortalWeb.Endpoint,
  force_ssl: [rewrite_on: [:x_forwarded_proto]],
  exclude: [
    # paths: ["/health"],
    hosts: ["localhost", "127.0.0.1"]
  ]
```

**Step 1: Fix force_ssl configuration**

The `exclude` option must be INSIDE the `force_ssl` keyword list, and we should merge the `hsts: true` setting here (not duplicate in runtime.exs):

```elixir
config :bezgelor_portal, BezgelorPortalWeb.Endpoint,
  cache_static_manifest: "priv/static/cache_manifest.json",
  force_ssl: [
    rewrite_on: [:x_forwarded_proto],
    hsts: true,
    # Exclude health checks and local development
    exclude: ["localhost", "127.0.0.1"]
  ]
```

**Note:** The `exclude` option takes a list of hosts (strings), not a keyword list with `hosts:` key.

**Step 2: Verify config compiles**

Run: `MIX_ENV=prod mix compile`
Expected: Compilation succeeds without warnings

**Step 3: Commit**

```bash
git add config/prod.exs
git commit -m "fix: correct force_ssl exclude syntax in prod.exs"
```

---

## Task 2: Create Health Check Endpoint

**Files:**
- Modify: `apps/bezgelor_portal/lib/bezgelor_portal_web/router.ex`
- Create: `apps/bezgelor_portal/lib/bezgelor_portal_web/controllers/health_controller.ex`

**Step 1: Create health controller**

This controller verifies actual TCP listener connectivity, not just application state.

```elixir
defmodule BezgelorPortalWeb.HealthController do
  use BezgelorPortalWeb, :controller

  @doc """
  Health check endpoint for Fly.io and load balancers.

  Returns 200 OK with system status.
  Verifies actual TCP listener connectivity for game servers.
  """
  def index(conn, _params) do
    # Check database connectivity
    db_status = check_database()

    # Check game servers via actual TCP connection
    auth_status = check_tcp_service(6600)
    realm_status = check_tcp_service(23115)
    world_status = check_tcp_service(24000)

    all_services_ok = db_status == :ok && auth_status == :ok &&
                      realm_status == :ok && world_status == :ok

    status = %{
      status: if(all_services_ok, do: "healthy", else: "degraded"),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      services: %{
        database: db_status,
        auth: auth_status,
        realm: realm_status,
        world: world_status
      },
      version: Application.spec(:bezgelor_portal, :vsn) |> to_string()
    }

    # Return 503 if ANY service is down, not just database
    # This ensures Fly's health check accurately reflects app health
    http_status = if all_services_ok, do: 200, else: 503

    conn
    |> put_status(http_status)
    |> json(status)
  end

  @doc """
  Lightweight liveness probe - just checks if app is running.
  Use for Kubernetes/Fly liveness checks separate from readiness.
  """
  def liveness(conn, _params) do
    conn
    |> put_status(200)
    |> json(%{status: "alive", timestamp: DateTime.utc_now() |> DateTime.to_iso8601()})
  end

  defp check_database do
    case BezgelorDb.Repo.query("SELECT 1") do
      {:ok, _} -> :ok
      {:error, _} -> :error
    end
  rescue
    _ -> :error
  end

  # Verify TCP listener is actually accepting connections
  defp check_tcp_service(port) do
    case :gen_tcp.connect({127, 0, 0, 1}, port, [], 1000) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        :ok
      {:error, _} ->
        :error
    end
  end
end
```

**Step 2: Add routes to router.ex**

Add before the existing routes (outside any pipeline):

```elixir
# Health checks - no auth required
get "/health", BezgelorPortalWeb.HealthController, :index
get "/api/health", BezgelorPortalWeb.HealthController, :index

# Liveness probe - lightweight check
get "/livez", BezgelorPortalWeb.HealthController, :liveness
```

**Step 3: Verify endpoint works**

Run: `mix phx.server` then `curl http://localhost:4000/health`
Expected: JSON response with status

**Step 4: Commit**

```bash
git add apps/bezgelor_portal/lib/bezgelor_portal_web/controllers/health_controller.ex
git add apps/bezgelor_portal/lib/bezgelor_portal_web/router.ex
git commit -m "feat: add health check endpoint with TCP verification for Fly.io"
```

---

## Task 3: Create Release Module for Migrations

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/release.ex`

**CRITICAL:** The release module MUST be placed inside an umbrella app (not at `lib/bezgelor/`). The umbrella root `lib/` directory is not compiled into releases. Placing it in `bezgelor_db` makes sense since it handles database migrations.

**Step 1: Create release.ex in bezgelor_db**

```elixir
defmodule BezgelorDb.Release do
  @moduledoc """
  Release tasks for running migrations in production.

  Called from rel/overlays/bin/migrate script.
  """

  @app :bezgelor_db

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.ensure_all_started(:ssl)
    Application.load(@app)
  end
end
```

**Step 2: Verify module compiles**

Run: `mix compile`
Expected: Compilation succeeds

**Step 3: Commit**

```bash
git add apps/bezgelor_db/lib/bezgelor_db/release.ex
git commit -m "feat: add release module for production migrations"
```

---

## Task 4: Create Release Overlay Scripts

**Files:**
- Create: `rel/overlays/bin/migrate`
- Create: `rel/overlays/bin/server`

**Step 1: Create overlay directory**

```bash
mkdir -p rel/overlays/bin
```

**Step 2: Create migrate script**

Note: Calls `BezgelorDb.Release.migrate` (the module is in bezgelor_db app, not umbrella root).

```bash
#!/bin/sh
set -eu

cd -P -- "$(dirname -- "$0")"
exec ./bezgelor eval BezgelorDb.Release.migrate
```

**Step 3: Create server script**

```bash
#!/bin/sh
set -eu

cd -P -- "$(dirname -- "$0")"
PHX_SERVER=true exec ./bezgelor start
```

**Step 4: Make scripts executable**

Run: `chmod +x rel/overlays/bin/migrate rel/overlays/bin/server`

**Step 5: Commit**

```bash
git add rel/
git commit -m "feat: add release overlay scripts for migrate and server"
```

---

## Task 5: Create .dockerignore

**Files:**
- Create: `.dockerignore`

**Step 1: Create .dockerignore**

```dockerignore
# Build artifacts
/_build/
/deps/
*.ez
*.beam
erl_crash.dump

# Git
.git
.gitignore

# Environment
.env
.env.*

# IDE
.elixir_ls/
.idea/
.vscode/
*.swp
*~

# Documentation
/doc/
/cover/

# Tests
/test/
apps/*/test/

# Development tools
/tools/

# OS
.DS_Store
Thumbs.db

# Large assets (fetch separately if needed)
apps/bezgelor_portal/priv/static/models/characters/*.glb
apps/bezgelor_portal/priv/static/textures/
portal_assets/

# Python
__pycache__/
*.pyc

# Docker
/docker/
logs/

# Node (not needed - standalone esbuild/tailwind)
apps/bezgelor_portal/assets/node_modules/

# Misc
.playwright-mcp/
TASK.md
.beads/
```

**Step 2: Commit**

```bash
git add .dockerignore
git commit -m "chore: add .dockerignore for Fly.io builds"
```

---

## Task 6: Create Dockerfile

**Files:**
- Create: `Dockerfile`

**Step 1: Verify Docker image exists**

Before creating the Dockerfile, verify the base image exists:

```bash
docker pull hexpm/elixir:1.17.3-erlang-27.2-debian-bookworm-slim
```

If this fails, check https://hub.docker.com/r/hexpm/elixir/tags for available versions.

**Step 2: Create Dockerfile**

```dockerfile
# Use verified working Elixir/OTP versions
# Check https://hub.docker.com/r/hexpm/elixir/tags for available tags
ARG ELIXIR_VERSION=1.17.3
ARG OTP_VERSION=27.2
ARG DEBIAN_VERSION=bookworm-slim

ARG BUILDER_IMAGE="docker.io/hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="docker.io/debian:${DEBIAN_VERSION}"

# Version for image labeling (override with --build-arg)
ARG APP_VERSION="0.1.0"

# Build stage
FROM ${BUILDER_IMAGE} AS builder

ARG APP_VERSION

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential git curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV="prod"
ENV APP_VERSION=${APP_VERSION}

# Copy mix files for dependency caching
COPY mix.exs mix.lock ./
COPY apps/bezgelor_api/mix.exs apps/bezgelor_api/
COPY apps/bezgelor_auth/mix.exs apps/bezgelor_auth/
COPY apps/bezgelor_core/mix.exs apps/bezgelor_core/
COPY apps/bezgelor_crypto/mix.exs apps/bezgelor_crypto/
COPY apps/bezgelor_data/mix.exs apps/bezgelor_data/
COPY apps/bezgelor_db/mix.exs apps/bezgelor_db/
COPY apps/bezgelor_portal/mix.exs apps/bezgelor_portal/
COPY apps/bezgelor_protocol/mix.exs apps/bezgelor_protocol/
COPY apps/bezgelor_realm/mix.exs apps/bezgelor_realm/
COPY apps/bezgelor_world/mix.exs apps/bezgelor_world/

RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# Compile-time config
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

# Install esbuild and tailwind
RUN mix assets.setup

# Copy priv directories (only apps that have them)
# Note: bezgelor_api has no priv directory
COPY apps/bezgelor_data/priv apps/bezgelor_data/priv
COPY apps/bezgelor_db/priv apps/bezgelor_db/priv
COPY apps/bezgelor_portal/priv apps/bezgelor_portal/priv

# Copy source (excluding bezgelor_dev - dev-only)
COPY apps/bezgelor_api/lib apps/bezgelor_api/lib
COPY apps/bezgelor_auth/lib apps/bezgelor_auth/lib
COPY apps/bezgelor_core/lib apps/bezgelor_core/lib
COPY apps/bezgelor_crypto/lib apps/bezgelor_crypto/lib
COPY apps/bezgelor_data/lib apps/bezgelor_data/lib
COPY apps/bezgelor_db/lib apps/bezgelor_db/lib
COPY apps/bezgelor_portal/lib apps/bezgelor_portal/lib
COPY apps/bezgelor_protocol/lib apps/bezgelor_protocol/lib
COPY apps/bezgelor_realm/lib apps/bezgelor_realm/lib
COPY apps/bezgelor_world/lib apps/bezgelor_world/lib

# NOTE: Release module (BezgelorDb.Release) is in apps/bezgelor_db/lib/
# No need to copy umbrella root lib/ - it should be empty

RUN mix compile

# Assets
COPY apps/bezgelor_portal/assets apps/bezgelor_portal/assets
RUN mix assets.deploy

# Runtime config and overlays
COPY config/runtime.exs config/
COPY rel rel

# Build release
RUN mix release bezgelor

# Runner stage
FROM ${RUNNER_IMAGE} AS final

ARG APP_VERSION

RUN apt-get update && apt-get install -y --no-install-recommends \
    libstdc++6 openssl libncurses6 locales ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8
ENV MIX_ENV="prod"

# BEAM performance tuning
ENV ERL_FLAGS="+JPperf true"

WORKDIR /app
RUN chown nobody /app

COPY --from=builder --chown=nobody:root /app/_build/prod/rel/bezgelor ./

USER nobody

# OCI image labels for versioning and source tracking
LABEL org.opencontainers.image.version=${APP_VERSION}
LABEL org.opencontainers.image.source="https://github.com/Bezgelor/bezgelor"
LABEL org.opencontainers.image.description="Bezgelor WildStar Server Emulator"

EXPOSE 4000 6600 23115 24000

CMD ["/app/bin/server"]
```

**Step 3: Verify Dockerfile syntax**

Run: `docker build --help` (just verify docker is available)

**Step 4: Commit**

```bash
git add Dockerfile
git commit -m "feat: add multi-stage Dockerfile with version labels and BEAM tuning"
```

---

## Task 7: Create fly.toml

**Files:**
- Create: `fly.toml`

**Step 1: Create fly.toml**

**Important Notes:**
- ALL services use `auto_stop_machines = "off"` - since everything runs on a single machine, suspending HTTP would also affect TCP game servers
- 4GB RAM based on game data analysis (1GB JSON → 2-3GB ETS) - monitor usage and scale to 6GB if needed under load
- Grace period increased to 120s for game data loading on startup

```toml
app = "bezgelor"
primary_region = "sjc"

[build]
  dockerfile = "Dockerfile"
  # Pass git version to Dockerfile for labeling
  [build.args]
    APP_VERSION = "0.1.0"

[env]
  PHX_HOST = "bezgelor.fly.dev"
  PHX_SERVER = "true"
  # BEAM performance tuning
  ERL_FLAGS = "+JPperf true"

[deploy]
  release_command = "/app/bin/migrate"

# Phoenix Portal - HTTP
# NOTE: auto_stop = "off" because all services share one machine.
# Suspending HTTP would affect TCP game servers.
[[services]]
  internal_port = 4000
  protocol = "tcp"
  auto_stop_machines = "off"
  auto_start_machines = true
  min_machines_running = 1

  [[services.ports]]
    handlers = ["http"]
    port = 80
    force_https = true

  [[services.ports]]
    handlers = ["tls", "http"]
    port = 443

  # Readiness check - full health including services
  [[services.http_checks]]
    interval = "10s"
    timeout = "5s"
    grace_period = "120s"
    method = "GET"
    path = "/health"

# Auth Server - TCP (must stay running, game clients can't wake)
[[services]]
  internal_port = 6600
  protocol = "tcp"
  auto_stop_machines = "off"
  auto_start_machines = true
  min_machines_running = 1

  [[services.ports]]
    port = 6600
    handlers = []

  [[services.tcp_checks]]
    interval = "15s"
    timeout = "2s"
    grace_period = "120s"

# Realm Server - TCP (must stay running)
[[services]]
  internal_port = 23115
  protocol = "tcp"
  auto_stop_machines = "off"
  auto_start_machines = true
  min_machines_running = 1

  [[services.ports]]
    port = 23115
    handlers = []

  [[services.tcp_checks]]
    interval = "15s"
    timeout = "2s"
    grace_period = "120s"

# World Server - TCP (must stay running)
[[services]]
  internal_port = 24000
  protocol = "tcp"
  auto_stop_machines = "off"
  auto_start_machines = true
  min_machines_running = 1

  [[services.ports]]
    port = 24000
    handlers = []

  [[services.tcp_checks]]
    interval = "15s"
    timeout = "2s"
    grace_period = "120s"

[[vm]]
  memory = "4gb"
  cpu_kind = "shared"
  cpus = 2
```

**Step 2: Commit**

```bash
git add fly.toml
git commit -m "feat: add Fly.io configuration with 4GB RAM and 120s grace period"
```

---

## Task 8: Update runtime.exs for Production Config

**Files:**
- Modify: `config/runtime.exs`

**Step 1: Add comprehensive production configuration**

Consolidate all production config in a single block with:
- CLOAK_KEY validation (required for Vault encryption)
- SSL for Fly Postgres (with security note)
- WORLD_PUBLIC_ADDRESS for game clients (REQUIRED, not optional)
- PORT env var handling (required by Fly.io)

**IMPORTANT:** Do NOT add `force_ssl` here - it's already configured in `prod.exs` (Task 1b). Adding it in both places would cause a conflict.

**SECURITY NOTE:** `ssl_opts: [verify: :verify_none]` disables certificate verification for the database connection. This is acceptable for Fly's internal network (connections are already encrypted via Fly's private networking), but document this tradeoff.

```elixir
if config_env() == :prod do
  # =============================================================================
  # Required Environment Variables
  # =============================================================================

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  cloak_key =
    System.get_env("CLOAK_KEY") ||
      raise """
      environment variable CLOAK_KEY is missing.
      Generate one with: elixir -e ':crypto.strong_rand_bytes(32) |> Base.encode64() |> IO.puts()'
      """

  database_url =
    System.get_env("DATABASE_URL") ||
      raise "DATABASE_URL environment variable is missing"

  # REQUIRED: Game clients need this IP to connect
  world_public_address =
    System.get_env("WORLD_PUBLIC_ADDRESS") ||
      raise """
      environment variable WORLD_PUBLIC_ADDRESS is missing.
      Set it to the Fly app's public IPv4 address for game client connections.
      Get the IP with: fly ips list --app bezgelor
      """

  # =============================================================================
  # Vault Configuration (Encryption)
  # =============================================================================

  config :bezgelor_portal, BezgelorPortal.Vault,
    ciphers: [
      default: {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V1", key: Base.decode64!(cloak_key)}
    ]

  # =============================================================================
  # Phoenix Endpoint Configuration
  # =============================================================================

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :bezgelor_portal, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :bezgelor_portal, BezgelorPortalWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base
    # NOTE: force_ssl is configured in prod.exs, not here

  # =============================================================================
  # Database Configuration
  # =============================================================================

  # SECURITY: verify: :verify_none is acceptable for Fly's internal network
  # where connections are already encrypted via private networking.
  config :bezgelor_db, BezgelorDb.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    ssl: true,
    ssl_opts: [verify: :verify_none]

  # =============================================================================
  # Game Server Configuration
  # =============================================================================

  config :bezgelor_world, public_address: world_public_address
end
```

**Step 2: Verify config compiles**

Run: `MIX_ENV=prod mix compile --warnings-as-errors`
Expected: Compilation succeeds

**Step 3: Commit**

```bash
git add config/runtime.exs
git commit -m "feat: consolidate production config with SSL, CLOAK_KEY, and force_ssl"
```

---

## Task 9: Verify Local Release Build

**Step 1: Build release locally**

Run: `MIX_ENV=prod mix release bezgelor`
Expected: Release built successfully

**Step 2: Verify release structure**

Run: `ls _build/prod/rel/bezgelor/bin/`
Expected: Shows `bezgelor`, `migrate`, `server`

**Step 3: Clean up**

Run: `rm -rf _build/prod`

---

## Task 10: Configure Fly Postgres Backups

**Files:**
- Create: `docs/fly-backup-strategy.md`

**Step 1: Create backup documentation**

```markdown
# Fly.io Postgres Backup Strategy

## Automatic Backups

Fly Postgres includes automatic daily backups retained for 7 days.

### View Backups

```bash
fly postgres backups list --app bezgelor-db
```

### Restore from Backup

```bash
# List available backups
fly postgres backups list --app bezgelor-db

# Restore to a new database
fly postgres restore --app bezgelor-db --backup-id <backup-id>
```

## Manual Backups

### Create On-Demand Backup

```bash
fly postgres backup create --app bezgelor-db
```

### Export Database Locally

```bash
# Get connection string
fly postgres connect --app bezgelor-db

# Use pg_dump (from local machine with tunnel)
fly proxy 5432 -a bezgelor-db &
pg_dump -h localhost -p 5432 -U postgres bezgelor > backup.sql
```

## Backup Schedule

| Type | Frequency | Retention |
|------|-----------|-----------|
| Automatic | Daily | 7 days |
| Manual | Before deploys | As needed |
| Monthly | First of month | 3 months |

## Recovery Procedures

### Full Recovery

1. Create new Postgres cluster from backup
2. Update DATABASE_URL secret
3. Redeploy application

### Point-in-Time Recovery

Not available on shared plans. Upgrade to dedicated for PITR.
```

**Step 2: Commit**

```bash
git add docs/fly-backup-strategy.md
git commit -m "docs: add Fly.io Postgres backup strategy"
```

---

## Task 11: Create Rollback Procedures Documentation

**Files:**
- Create: `docs/fly-rollback.md`

**Step 1: Create rollback documentation**

```markdown
# Fly.io Rollback Procedures

## Application Rollback

### View Release History

```bash
fly releases --app bezgelor
```

### Rollback to Previous Release

```bash
# Rollback to immediately previous version
fly deploy --image <previous-image-ref> --app bezgelor

# Or use release number
fly releases rollback <version> --app bezgelor
```

## Database Migration Rollback

### Check Migration Status

```bash
fly ssh console --app bezgelor -C "/app/bin/bezgelor eval 'Ecto.Migrator.migrations(BezgelorDb.Repo)'"
```

### Rollback Last Migration

```bash
fly ssh console --app bezgelor -C "/app/bin/bezgelor eval 'BezgelorDb.Release.rollback(BezgelorDb.Repo, <version>)'"
```

## Emergency Procedures

### Stop All Traffic

```bash
fly scale count 0 --app bezgelor
```

### Restart Application

```bash
fly apps restart bezgelor
```

### View Crash Logs

```bash
fly logs --app bezgelor | grep -i error
```

## Pre-Deploy Checklist

1. [ ] Backup database: `fly postgres backup create --app bezgelor-db`
2. [ ] Note current release: `fly releases --app bezgelor | head -2`
3. [ ] Run migrations locally: `MIX_ENV=prod mix ecto.migrate`
4. [ ] Deploy: `fly deploy`
5. [ ] Verify health: `curl https://bezgelor.fly.dev/health`
```

**Step 2: Commit**

```bash
git add docs/fly-rollback.md
git commit -m "docs: add Fly.io rollback procedures"
```

---

## Task 12: Create Deployment Documentation

**Files:**
- Create: `docs/fly-deployment.md`

**Step 1: Create deployment guide**

```markdown
# Fly.io Deployment Guide

## Prerequisites

- [flyctl](https://fly.io/docs/hands-on/install-flyctl/) installed
- Fly.io account

## Initial Setup

### 1. Create App and Database

```bash
# Login
fly auth login

# Create app
fly apps create bezgelor

# Create Postgres (sjc region, 10GB)
fly postgres create --name bezgelor-db --region sjc \
  --initial-cluster-size 1 --vm-size shared-cpu-1x --volume-size 10

# Attach database (sets DATABASE_URL)
fly postgres attach bezgelor-db --app bezgelor
```

### 2. Generate Secrets Locally (Secure)

Generate secrets on your local machine, not in shell history:

```bash
# Generate SECRET_KEY_BASE
mix phx.gen.secret
# Copy the output

# Generate CLOAK_KEY
elixir -e ':crypto.strong_rand_bytes(32) |> Base.encode64() |> IO.puts()'
# Copy the output
```

### 3. Allocate Public IP

Game clients need a public IPv4 address to connect. Allocate it before deploying:

```bash
# Allocate a public IPv4 address
fly ips allocate v4 --app bezgelor

# Note the IPv4 address for the next step
fly ips list --app bezgelor
```

### 4. Set ALL Secrets (Before First Deploy)

**CRITICAL:** ALL secrets must be set before deploying. The app will crash on startup without WORLD_PUBLIC_ADDRESS.

```bash
fly secrets set \
  SECRET_KEY_BASE="<paste-secret-key>" \
  CLOAK_KEY="<paste-cloak-key>" \
  WORLD_PUBLIC_ADDRESS="<IPv4-address-from-step-3>" \
  --app bezgelor
```

### 5. Deploy

```bash
# Deploy with version tag
fly deploy --app bezgelor --build-arg APP_VERSION=$(git describe --tags --always)
```

### 6. Verify Deployment

```bash
# Check health endpoint (full readiness)
curl https://bezgelor.fly.dev/health

# Check liveness (lightweight)
curl https://bezgelor.fly.dev/livez

# View logs
fly logs --app bezgelor
```

## Useful Commands

```bash
# View logs
fly logs --app bezgelor

# SSH console
fly ssh console --app bezgelor

# Run migrations manually
fly ssh console --app bezgelor -C "/app/bin/migrate"

# Remote IEx
fly ssh console --app bezgelor -C "/app/bin/bezgelor remote"

# Status
fly status --app bezgelor

# Scale (if needed)
fly scale memory 4096 --app bezgelor
```

## Ports

| Service | Port | Protocol |
|---------|------|----------|
| Portal | 443 | HTTPS |
| Auth | 6600 | TCP |
| Realm | 23115 | TCP |
| World | 24000 | TCP |

## Security Notes

- All secrets stored in Fly.io secrets (encrypted at rest)
- HTTPS enforced with HSTS
- Database connections use SSL with `verify: :verify_none`
  - Certificate verification is disabled because Fly Postgres uses internal certificates
  - This is acceptable for Fly's private networking (connections are already encrypted)
  - If migrating to external Postgres, update to `verify: :verify_peer`
- TCP ports are publicly exposed (game server requirement)
- WORLD_PUBLIC_ADDRESS is required - app will fail to start without it

## Monitoring

### Health Check

The `/health` endpoint returns:
- Database connectivity status
- Game server TCP listener status (auth, realm, world)
- Application version

The `/livez` endpoint returns:
- Lightweight liveness check (app is running)

### Log Aggregation

Fly.io provides built-in log aggregation. For external services:

```bash
# Ship to external service (optional)
fly logs --app bezgelor | your-log-shipper
```

## Cost Estimate

| Resource | Spec | Monthly Cost |
|----------|------|--------------|
| App VM | shared-cpu-2x, 4GB | ~$30 |
| Postgres | shared-cpu-1x, 10GB | ~$15 |
| **Total** | | **~$45/month** |
```

**Step 2: Commit**

```bash
git add docs/fly-deployment.md
git commit -m "docs: add comprehensive Fly.io deployment guide"
```

---

## Task 13: Final Commit and Summary

**Step 1: Create summary commit if needed**

If any uncommitted changes remain:

```bash
git status
git add -A
git commit -m "chore: complete Fly.io deployment setup"
```

**Step 2: Push**

```bash
git push
```

---

## Deployment Checklist

After implementation, deploy with:

1. `fly auth login`
2. `fly apps create bezgelor`
3. `fly postgres create --name bezgelor-db --region sjc --initial-cluster-size 1 --vm-size shared-cpu-1x --volume-size 10`
4. `fly postgres attach bezgelor-db --app bezgelor`
5. `fly ips allocate v4 --app bezgelor` (get public IP for game clients)
6. Generate secrets locally (secure):
   - `mix phx.gen.secret` → copy output
   - `elixir -e ':crypto.strong_rand_bytes(32) |> Base.encode64() |> IO.puts()'` → copy output
7. `fly ips list --app bezgelor` → note the IPv4 address
8. Set ALL required secrets (WORLD_PUBLIC_ADDRESS is REQUIRED):
   ```bash
   fly secrets set \
     SECRET_KEY_BASE="<secret>" \
     CLOAK_KEY="<key>" \
     WORLD_PUBLIC_ADDRESS="<IPv4-address>" \
     --app bezgelor
   ```
9. `fly deploy --build-arg APP_VERSION=$(git describe --tags --always)`
10. Verify: `curl https://bezgelor.fly.dev/health`

---

## Future Considerations

Items intentionally deferred for later:

| Item | Reason |
|------|--------|
| Sentry integration | Add after initial deployment validated |
| Log shipping | Use Fly's built-in logs initially |
| Horizontal scaling | Single machine is sufficient for initial launch |
| IP allowlisting | Game clients need open TCP access |
