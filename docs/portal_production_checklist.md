# Bezgelor Portal - Production Deployment Checklist

## Environment Variables

### Required

```bash
# Database (inherited from bezgelor_db)
POSTGRES_DB=bezgelor
POSTGRES_USER=bezgelor
POSTGRES_PASSWORD=<secure-password>
POSTGRES_HOST=localhost
POSTGRES_PORT=5433

# Phoenix
SECRET_KEY_BASE=<generate with: mix phx.gen.secret>
PHX_HOST=portal.yourdomain.com
PORT=4001

# Encryption (TOTP secrets)
CLOAK_KEY=<generate with: :crypto.strong_rand_bytes(32) |> Base.encode64()>
```

### Optional - Discord OAuth (#24)

```bash
DISCORD_CLIENT_ID=<from Discord Developer Portal>
DISCORD_CLIENT_SECRET=<from Discord Developer Portal>
```

### Optional - Email (#25)

```bash
# SMTP (generic)
SMTP_HOST=smtp.example.com
SMTP_PORT=587
SMTP_USER=apikey
SMTP_PASSWORD=<api-key>

# Or use SendGrid/Mailgun/Postmark specific config
```

### Optional - OpenTelemetry (#25)

```bash
OTEL_EXPORTER_OTLP_ENDPOINT=http://jaeger:4317
OTEL_SERVICE_NAME=bezgelor_portal
```

---

## Pre-Deployment Checklist

### Database
- [ ] Run migrations: `mix ecto.migrate`
- [ ] Seed permissions and roles: `mix run priv/repo/seeds.exs`
- [ ] Create initial super admin account manually

### Security
- [ ] Generate production `SECRET_KEY_BASE`
- [ ] Generate production `CLOAK_KEY`
- [ ] Ensure HTTPS is configured (reverse proxy or direct)
- [ ] Review CORS settings if API is cross-origin

### Phoenix
- [ ] Set `PHX_HOST` to production domain
- [ ] Disable `dev_routes` (automatic in prod)
- [ ] Build assets: `mix assets.deploy`
- [ ] Compile release: `MIX_ENV=prod mix release`

---

## Development URLs

When running locally (`mix phx.server`):

| URL | Purpose |
|-----|---------|
| http://localhost:4001 | Portal home |
| http://localhost:4001/dashboard | User dashboard |
| http://localhost:4001/admin | Admin panel |
| http://localhost:4001/dev/mailbox | Email preview (dev only) |
| http://localhost:4001/dev/tracing | Orion tracing UI (dev only) |

---

## Related Issues

- #24 - Discord OAuth integration
- #25 - Phase 6 production integrations (OpenTelemetry, Email)
