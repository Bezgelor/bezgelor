# Production Deployment Guide

This document covers all configuration required to deploy Bezgelor to production.

## Required Environment Variables

### Core (Required)

| Variable | Description | Example |
|----------|-------------|---------|
| `SECRET_KEY_BASE` | Phoenix secret for signing cookies/tokens. Generate with `mix phx.gen.secret` | `abc123...` (64+ chars) |
| `DATABASE_URL` | PostgreSQL connection string | `postgres://user:pass@host:5432/bezgelor` |
| `PHX_HOST` | Public hostname for the portal | `bezgelor.com` |
| `CLOAK_KEY` | 32-byte base64 key for TOTP encryption. Generate with `:crypto.strong_rand_bytes(32) \|> Base.encode64()` | `abc123...` |

### Email (Required for account verification)

| Variable | Description | Default |
|----------|-------------|---------|
| `RESEND_API_KEY` | Resend API key from https://resend.com | - |
| `MAIL_FROM` | Sender email address | `noreply@bezgelor.com` |

### Game Servers

| Variable | Description | Default |
|----------|-------------|---------|
| `AUTH_HOST` | Auth server bind address | `0.0.0.0` |
| `AUTH_PORT` | Auth server port | `6600` |
| `REALM_HOST` | Realm server bind address | `0.0.0.0` |
| `REALM_PORT` | Realm server port | `23115` |
| `WORLD_HOST` | World server bind address | `0.0.0.0` |
| `WORLD_PORT` | World server port | `24000` |
| `WORLD_PUBLIC_ADDRESS` | Public IP/hostname clients connect to | `127.0.0.1` |
| `REALM_ID` | Realm identifier | `1` |
| `REALM_NAME` | Realm display name | `Bezgelor` |

### Portal/Web

| Variable | Description | Default |
|----------|-------------|---------|
| `PORT` | HTTP port for Phoenix | `4000` |
| `PHX_SERVER` | Set to `true` to start the web server | - |
| `POOL_SIZE` | Database connection pool size | `10` |
| `DNS_CLUSTER_QUERY` | DNS query for cluster discovery (Fly.io) | - |

## Deployment Platforms

### Fly.io

For Fly.io deployment, set secrets using:

```bash
# Required
fly secrets set SECRET_KEY_BASE=$(mix phx.gen.secret)
fly secrets set DATABASE_URL="postgres://..."
fly secrets set CLOAK_KEY=$(elixir -e ':crypto.strong_rand_bytes(32) |> Base.encode64() |> IO.puts()')

# Email
fly secrets set RESEND_API_KEY="re_..."
fly secrets set MAIL_FROM="noreply@yourdomain.com"

# Game servers (use your Fly app's public IP or hostname)
fly secrets set WORLD_PUBLIC_ADDRESS="your-app.fly.dev"
fly secrets set PHX_HOST="your-app.fly.dev"
```

Fly.io automatically sets `PORT` and `PHX_SERVER=true`.

### Docker / Self-Hosted

Create a `.env` file (never commit this):

```bash
# Core
SECRET_KEY_BASE=your_64_char_secret_here
DATABASE_URL=postgres://bezgelor:password@localhost:5432/bezgelor_prod
PHX_HOST=bezgelor.example.com
CLOAK_KEY=your_32_byte_base64_key

# Email
RESEND_API_KEY=re_your_api_key
MAIL_FROM=noreply@bezgelor.example.com

# Game servers
WORLD_PUBLIC_ADDRESS=game.bezgelor.example.com
AUTH_HOST=0.0.0.0
REALM_HOST=0.0.0.0
WORLD_HOST=0.0.0.0

# Portal
PORT=4000
PHX_SERVER=true
POOL_SIZE=20
```

## Database Setup

### Option 1: DATABASE_URL (Recommended)

Set `DATABASE_URL` to a full connection string:
```
postgres://username:password@hostname:5432/database_name
```

### Option 2: Individual Variables

If not using `DATABASE_URL`, set these individually:
- `POSTGRES_HOST`
- `POSTGRES_PORT` (default: 5433 in dev, 5432 standard)
- `POSTGRES_DB`
- `POSTGRES_USER`
- `POSTGRES_PASSWORD`

### Migrations

Run migrations before starting:
```bash
mix ecto.migrate
# Or in release:
bin/bezgelor_portal eval "BezgelorDb.Release.migrate()"
```

## Security Checklist

- [ ] Generate unique `SECRET_KEY_BASE` (never reuse from dev)
- [ ] Generate unique `CLOAK_KEY` (TOTP secrets encrypted with this)
- [ ] Use strong database password
- [ ] Enable HTTPS (Fly.io handles this automatically)
- [ ] Set `PHX_HOST` to your actual domain
- [ ] Configure firewall to only expose needed ports:
  - `443` - HTTPS (portal)
  - `6600` - Auth server (game clients)
  - `23115` - Realm server (game clients)
  - `24000` - World server (game clients)

## Email Setup with Resend

1. Create account at https://resend.com
2. Add and verify your domain
3. Create an API key
4. Set `RESEND_API_KEY` environment variable
5. Set `MAIL_FROM` to an address on your verified domain

## Network Architecture

```
                    ┌─────────────────┐
   HTTPS (443)      │                 │
   ────────────────►│  Portal (4000)  │
                    │                 │
                    └─────────────────┘

   Game Client      ┌─────────────────┐
   ────────────────►│  Auth (6600)    │
         │          └─────────────────┘
         │
         │          ┌─────────────────┐
         └─────────►│  Realm (23115)  │
         │          └─────────────────┘
         │
         │          ┌─────────────────┐
         └─────────►│  World (24000)  │
                    └─────────────────┘
```

Game clients connect to Auth first, then Realm, then World. The `WORLD_PUBLIC_ADDRESS` must be reachable by game clients.

## Generating Secrets

```bash
# SECRET_KEY_BASE (64+ character string)
mix phx.gen.secret

# CLOAK_KEY (32-byte base64 encoded)
elixir -e ':crypto.strong_rand_bytes(32) |> Base.encode64() |> IO.puts()'
```

## Health Checks

The portal responds to health checks at:
- `GET /` - Returns 200 if running

## Troubleshooting

### Email not sending
- Verify `RESEND_API_KEY` is set correctly
- Check Resend dashboard for delivery status
- Ensure `MAIL_FROM` domain is verified in Resend

### Game clients can't connect
- Verify `WORLD_PUBLIC_ADDRESS` is the correct public IP/hostname
- Check firewall allows ports 6600, 23115, 24000
- Ensure game servers are bound to `0.0.0.0` not `127.0.0.1`

### Database connection errors
- Verify `DATABASE_URL` format is correct
- Check database is accessible from app server
- Ensure SSL settings match if using managed Postgres
