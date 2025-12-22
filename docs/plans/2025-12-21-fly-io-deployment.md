# Fly.io Deployment Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Configure Bezgelor for single-app deployment on Fly.io with all services in one container.

**Architecture:** All services (Portal HTTP, Auth/Realm/World TCP) run in a single Fly machine. Fly Postgres provides the database. Release builds use multi-stage Docker with Elixir 1.18/OTP 27.

**Tech Stack:** Elixir releases, Docker multi-stage builds, Fly.io, Fly Postgres

---

## Task 1: Add Release Configuration to mix.exs

**Files:**
- Modify: `mix.exs`

**Step 1: Add releases function to mix.exs**

Add `releases: releases()` to the project list and create the releases function:

```elixir
def project do
  [
    apps_path: "apps",
    version: "0.1.0",
    start_permanent: Mix.env() == :prod,
    deps: deps(),
    listeners: [Phoenix.CodeReloader],
    releases: releases()
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
      ],
      include_executables_for: [:unix]
    ]
  ]
end
```

**Step 2: Verify release configuration**

Run: `mix release --help`
Expected: No errors, shows release help

**Step 3: Commit**

```bash
git add mix.exs
git commit -m "chore: add release configuration for Fly.io deployment"
```

---

## Task 2: Create Release Module for Migrations

**Files:**
- Create: `lib/bezgelor/release.ex`

**Step 1: Create lib directory**

```bash
mkdir -p lib/bezgelor
```

**Step 2: Create release.ex**

```elixir
defmodule Bezgelor.Release do
  @moduledoc """
  Release tasks for running migrations in production.
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

**Step 3: Verify module compiles**

Run: `mix compile`
Expected: Compilation succeeds

**Step 4: Commit**

```bash
git add lib/bezgelor/release.ex
git commit -m "feat: add release module for production migrations"
```

---

## Task 3: Create Release Overlay Scripts

**Files:**
- Create: `rel/overlays/bin/migrate`
- Create: `rel/overlays/bin/server`

**Step 1: Create overlay directory**

```bash
mkdir -p rel/overlays/bin
```

**Step 2: Create migrate script**

```bash
#!/bin/sh
set -eu

cd -P -- "$(dirname -- "$0")"
exec ./bezgelor eval Bezgelor.Release.migrate
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

## Task 4: Create .dockerignore

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
```

**Step 2: Commit**

```bash
git add .dockerignore
git commit -m "chore: add .dockerignore for Fly.io builds"
```

---

## Task 5: Create Dockerfile

**Files:**
- Create: `Dockerfile`

**Step 1: Create Dockerfile**

```dockerfile
# Elixir 1.18.x with OTP 27 for stable Docker images
ARG ELIXIR_VERSION=1.18.3
ARG OTP_VERSION=27.3.1
ARG DEBIAN_VERSION=bookworm-20250113-slim

ARG BUILDER_IMAGE="docker.io/hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="docker.io/debian:${DEBIAN_VERSION}"

# Build stage
FROM ${BUILDER_IMAGE} AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential git curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV="prod"

# Copy mix files for dependency caching
COPY mix.exs mix.lock ./
COPY apps/bezgelor_api/mix.exs apps/bezgelor_api/
COPY apps/bezgelor_auth/mix.exs apps/bezgelor_auth/
COPY apps/bezgelor_core/mix.exs apps/bezgelor_core/
COPY apps/bezgelor_crypto/mix.exs apps/bezgelor_crypto/
COPY apps/bezgelor_data/mix.exs apps/bezgelor_data/
COPY apps/bezgelor_db/mix.exs apps/bezgelor_db/
COPY apps/bezgelor_dev/mix.exs apps/bezgelor_dev/
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

# Copy priv directories
COPY apps/bezgelor_api/priv apps/bezgelor_api/priv
COPY apps/bezgelor_data/priv apps/bezgelor_data/priv
COPY apps/bezgelor_db/priv apps/bezgelor_db/priv
COPY apps/bezgelor_portal/priv apps/bezgelor_portal/priv

# Copy source
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

# Copy release module
COPY lib lib

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

RUN apt-get update && apt-get install -y --no-install-recommends \
    libstdc++6 openssl libncurses6 locales ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8
ENV MIX_ENV="prod"

WORKDIR /app
RUN chown nobody /app

COPY --from=builder --chown=nobody:root /app/_build/prod/rel/bezgelor ./

USER nobody

EXPOSE 4000 6600 23115 24000

CMD ["/app/bin/server"]
```

**Step 2: Verify Dockerfile syntax**

Run: `docker build --help` (just verify docker is available)

**Step 3: Commit**

```bash
git add Dockerfile
git commit -m "feat: add multi-stage Dockerfile for Fly.io deployment"
```

---

## Task 6: Create fly.toml

**Files:**
- Create: `fly.toml`

**Step 1: Create fly.toml**

```toml
app = "bezgelor"
primary_region = "sjc"

[build]
  dockerfile = "Dockerfile"

[env]
  PHX_HOST = "bezgelor.fly.dev"
  PHX_SERVER = "true"

[deploy]
  release_command = "/app/bin/migrate"

# Phoenix Portal - HTTP
[[services]]
  internal_port = 4000
  protocol = "tcp"
  auto_stop_machines = "suspend"
  auto_start_machines = true
  min_machines_running = 1

  [[services.ports]]
    handlers = ["http"]
    port = 80
    force_https = true

  [[services.ports]]
    handlers = ["tls", "http"]
    port = 443

  [[services.http_checks]]
    interval = "10s"
    timeout = "2s"
    grace_period = "30s"
    method = "GET"
    path = "/"

# Auth Server - TCP
[[services]]
  internal_port = 6600
  protocol = "tcp"
  auto_stop_machines = "suspend"
  auto_start_machines = true

  [[services.ports]]
    port = 6600
    handlers = []

  [[services.tcp_checks]]
    interval = "15s"
    timeout = "2s"
    grace_period = "30s"

# Realm Server - TCP
[[services]]
  internal_port = 23115
  protocol = "tcp"
  auto_stop_machines = "suspend"
  auto_start_machines = true

  [[services.ports]]
    port = 23115
    handlers = []

  [[services.tcp_checks]]
    interval = "15s"
    timeout = "2s"
    grace_period = "30s"

# World Server - TCP
[[services]]
  internal_port = 24000
  protocol = "tcp"
  auto_stop_machines = "suspend"
  auto_start_machines = true

  [[services.ports]]
    port = 24000
    handlers = []

  [[services.tcp_checks]]
    interval = "15s"
    timeout = "2s"
    grace_period = "30s"

[[vm]]
  memory = "2gb"
  cpu_kind = "shared"
  cpus = 2
```

**Step 2: Commit**

```bash
git add fly.toml
git commit -m "feat: add Fly.io configuration with multi-service support"
```

---

## Task 7: Update runtime.exs for WORLD_PUBLIC_ADDRESS

**Files:**
- Modify: `config/runtime.exs`

**Step 1: Add WORLD_PUBLIC_ADDRESS config**

Add after the existing prod database config block (around line 95):

```elixir
if config_env() == :prod do
  # World server public address for game client connections
  # On Fly.io, set via: fly secrets set WORLD_PUBLIC_ADDRESS="<fly-app-ip>"
  world_public_address = System.get_env("WORLD_PUBLIC_ADDRESS")

  if world_public_address do
    config :bezgelor_world, public_address: world_public_address
  end
end
```

**Step 2: Verify config compiles**

Run: `MIX_ENV=prod mix compile --warnings-as-errors`
Expected: Compilation succeeds

**Step 3: Commit**

```bash
git add config/runtime.exs
git commit -m "feat: add WORLD_PUBLIC_ADDRESS config for Fly.io deployment"
```

---

## Task 8: Verify Local Release Build

**Step 1: Build release locally**

Run: `MIX_ENV=prod mix release bezgelor`
Expected: Release built successfully

**Step 2: Verify release structure**

Run: `ls _build/prod/rel/bezgelor/bin/`
Expected: Shows `bezgelor`, `migrate`, `server`

**Step 3: Clean up**

Run: `rm -rf _build/prod`

---

## Task 9: Create Deployment Documentation

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

### 2. Set Secrets

```bash
# Generate and set secrets
fly secrets set SECRET_KEY_BASE=$(mix phx.gen.secret) --app bezgelor
fly secrets set CLOAK_KEY=$(elixir -e ':crypto.strong_rand_bytes(32) |> Base.encode64() |> IO.puts()') --app bezgelor
```

### 3. Deploy

```bash
fly deploy --app bezgelor
```

### 4. Set World Server Address

After deploy, get the app's IP and set it for game clients:

```bash
fly ips list --app bezgelor
fly secrets set WORLD_PUBLIC_ADDRESS="<IPv4-address>" --app bezgelor
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
```

## Ports

| Service | Port | Protocol |
|---------|------|----------|
| Portal | 443 | HTTPS |
| Auth | 6600 | TCP |
| Realm | 23115 | TCP |
| World | 24000 | TCP |
```

**Step 2: Commit**

```bash
git add docs/fly-deployment.md
git commit -m "docs: add Fly.io deployment guide"
```

---

## Task 10: Final Commit and Summary

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
3. `fly postgres create --name bezgelor-db --region sjc`
4. `fly postgres attach bezgelor-db --app bezgelor`
5. `fly secrets set SECRET_KEY_BASE=$(mix phx.gen.secret)`
6. `fly secrets set CLOAK_KEY=$(elixir -e ':crypto.strong_rand_bytes(32) |> Base.encode64() |> IO.puts()')`
7. `fly deploy`
8. `fly ips list` → `fly secrets set WORLD_PUBLIC_ADDRESS="<IP>"`
