# Fly.io Deployment Guide

Complete guide for deploying Bezgelor to Fly.io with all services (Portal, Auth, Realm, World) running in a single container.

## Prerequisites

1. Install flyctl CLI:
   ```bash
   # macOS
   brew install flyctl

   # Linux
   curl -L https://fly.io/install.sh | sh

   # Windows
   pwsh -Command "iwr https://fly.io/install.ps1 -useb | iex"
   ```

2. Create Fly.io account at https://fly.io/app/sign-up

3. Authenticate:
   ```bash
   fly auth login
   ```

## Initial Setup

### 1. Create Application

```bash
# Create app (use your desired name)
fly apps create bezgelor

# Verify creation
fly apps list
```

### 2. Create and Attach PostgreSQL Database

```bash
# Create Postgres database (adjust region as needed)
fly postgres create --name bezgelor-db \
  --region sjc \
  --initial-cluster-size 1 \
  --vm-size shared-cpu-1x \
  --volume-size 10

# Attach database to app (automatically sets DATABASE_URL secret)
fly postgres attach bezgelor-db --app bezgelor
```

### 3. Allocate Public IPv4 Address

Game clients require a public IPv4 address to connect to TCP game servers:

```bash
# Allocate IPv4 address
fly ips allocate-v4 --app bezgelor

# Get the allocated IP (save this for next step)
fly ips list --app bezgelor
```

You should see output like:
```
VERSION  IP              TYPE    REGION  CREATED AT
v4       203.0.113.45    public  global  just now
```

Save the IPv4 address - you'll need it for `WORLD_PUBLIC_ADDRESS`.

## Required Secrets

### Generate Secrets Locally (Secure Method)

Generate all secrets on your local machine before setting them:

```bash
# 1. Generate SECRET_KEY_BASE (64+ character string)
mix phx.gen.secret
# Copy the output

# 2. Generate CLOAK_KEY (32-byte base64 key for TOTP encryption)
elixir -e ':crypto.strong_rand_bytes(32) |> Base.encode64() |> IO.puts()'
# Copy the output
```

### Set All Required Secrets

Set all secrets in a single command (CRITICAL - app will not start without these):

```bash
fly secrets set \
  SECRET_KEY_BASE="<paste-secret-from-step-1>" \
  CLOAK_KEY="<paste-key-from-step-2>" \
  WORLD_PUBLIC_ADDRESS="<IPv4-from-allocate-step>" \
  PHX_HOST="bezgelor.fly.dev" \
  --app bezgelor
```

Replace:
- `<paste-secret-from-step-1>` with output from `mix phx.gen.secret`
- `<paste-key-from-step-2>` with output from the `elixir -e` command
- `<IPv4-from-allocate-step>` with the IP from `fly ips list`
- `bezgelor.fly.dev` with your actual Fly app hostname

### Optional Secrets (Email)

To enable email verification, configure Resend:

```bash
fly secrets set \
  RESEND_API_KEY="re_your_api_key_here" \
  MAIL_FROM="noreply@yourdomain.com" \
  --app bezgelor
```

Get your Resend API key:
1. Create account at https://resend.com
2. Add and verify your domain
3. Create an API key

## Deploy

Deploy with version tagging:

```bash
fly deploy --app bezgelor --build-arg APP_VERSION=$(git describe --tags --always)
```

First deployment will:
1. Build Docker image with multi-stage build
2. Upload to Fly.io registry
3. Run database migrations (via `release_command`)
4. Start all services (Portal, Auth, Realm, World)

Expected build time: 3-5 minutes for first deploy, 1-2 minutes for subsequent deploys.

## Post-Deployment Verification

### 1. Check Deployment Status

```bash
# View deployment status
fly status --app bezgelor

# Should show:
# - 1 instance running
# - Health checks passing
```

### 2. Verify Health Endpoints

```bash
# Comprehensive health check (includes all services)
curl https://bezgelor.fly.dev/health

# Expected response:
# {
#   "status": "healthy",
#   "timestamp": "2025-12-22T...",
#   "services": {
#     "database": "ok",
#     "auth": "ok",
#     "realm": "ok",
#     "world": "ok"
#   },
#   "version": "0.1.0"
# }

# Lightweight liveness check
curl https://bezgelor.fly.dev/livez
```

### 3. Verify Game Server Ports

Test TCP connectivity to game servers:

```bash
# Get your app's IP
FLY_IP=$(fly ips list --app bezgelor | grep v4 | awk '{print $2}')

# Test Auth server (port 6600)
nc -zv $FLY_IP 6600

# Test Realm server (port 23115)
nc -zv $FLY_IP 23115

# Test World server (port 24000)
nc -zv $FLY_IP 24000
```

All should respond with "succeeded" or "open".

### 4. Verify Portal Access

Navigate to `https://bezgelor.fly.dev` in your browser and verify:
- Portal loads successfully
- HTTPS is enforced
- Registration/login pages work

## Monitoring and Logs

### View Live Logs

```bash
# Stream all logs
fly logs --app bezgelor

# Filter by severity
fly logs --app bezgelor | grep -i error
fly logs --app bezgelor | grep -i warn

# View recent logs (last 100 lines)
fly logs --app bezgelor -n 100
```

### Application Metrics

```bash
# Resource usage and metrics
fly status --app bezgelor

# Database metrics
fly postgres db status --app bezgelor-db
```

### Remote Console Access

```bash
# SSH into container
fly ssh console --app bezgelor

# Remote IEx (Elixir console)
fly ssh console --app bezgelor -C "/app/bin/bezgelor remote"

# Run migrations manually
fly ssh console --app bezgelor -C "/app/bin/migrate"
```

### Health Check Monitoring

Fly.io automatically monitors:
- **HTTP health check**: `GET /health` every 10s (grace period: 120s)
- **TCP checks**: Auth (6600), Realm (23115), World (24000) every 15s

If health checks fail, Fly will:
1. Mark instance as unhealthy
2. Stop routing traffic
3. Attempt to restart the instance

## Scaling Considerations

### Memory Scaling

Default configuration: 4GB RAM (handles ~2-3GB game data in ETS)

Monitor memory usage:
```bash
fly status --app bezgelor
```

If memory pressure occurs under load:
```bash
# Scale to 6GB
fly scale memory 6144 --app bezgelor

# Scale to 8GB
fly scale memory 8192 --app bezgelor
```

### CPU Scaling

Default: 2 shared vCPUs

Scale CPU if needed:
```bash
# Performance CPU (dedicated cores)
fly scale vm performance-1x --app bezgelor

# More cores
fly scale vm performance-2x --app bezgelor
```

### Horizontal Scaling

Current architecture runs all services in a single machine. For horizontal scaling:
1. Split services into separate apps (auth-app, realm-app, world-app)
2. Use Fly.io service discovery
3. Configure load balancing

This is recommended only after validating single-machine performance.

### Database Scaling

```bash
# Check database size
fly postgres db status --app bezgelor-db

# Increase volume size
fly volumes extend <volume-id> -s 20 --app bezgelor-db

# Upgrade to larger VM
fly postgres update --vm-size shared-cpu-2x --app bezgelor-db
```

## Troubleshooting Common Issues

### App Won't Start

**Symptom**: Deployment succeeds but instances crash immediately

**Diagnostics**:
```bash
fly logs --app bezgelor | grep -i error
fly status --app bezgelor
```

**Common causes**:
1. Missing `WORLD_PUBLIC_ADDRESS` secret
2. Missing `SECRET_KEY_BASE` or `CLOAK_KEY`
3. Database connection failure
4. Migration errors

**Fix**:
```bash
# Verify all secrets are set
fly secrets list --app bezgelor

# Check database connectivity
fly postgres connect --app bezgelor-db

# Run migrations manually
fly ssh console --app bezgelor -C "/app/bin/migrate"
```

### Health Checks Failing

**Symptom**: `/health` returns 503 or times out

**Diagnostics**:
```bash
# Check health endpoint directly
curl -v https://bezgelor.fly.dev/health

# Check individual service status
fly ssh console --app bezgelor -C "netstat -tlnp"
```

**Common causes**:
1. Game servers not starting (check logs for port binding errors)
2. Database connectivity issues
3. ETS data not loaded (insufficient memory)

**Fix**:
```bash
# Restart app
fly apps restart bezgelor

# Increase memory if data loading fails
fly scale memory 6144 --app bezgelor
```

### Game Clients Can't Connect

**Symptom**: Clients fail to connect to Auth/Realm/World servers

**Diagnostics**:
```bash
# Verify ports are open
fly ips list --app bezgelor
nc -zv <IP> 6600
nc -zv <IP> 23115
nc -zv <IP> 24000

# Check TCP service configuration
fly services list --app bezgelor
```

**Common causes**:
1. `WORLD_PUBLIC_ADDRESS` not set or incorrect
2. Firewall blocking TCP ports (unlikely on Fly.io)
3. Client configured with wrong IP/hostname

**Fix**:
```bash
# Verify public address is set correctly
fly secrets list --app bezgelor

# Update if needed
fly secrets set WORLD_PUBLIC_ADDRESS="<correct-IPv4>" --app bezgelor
```

### Database Connection Errors

**Symptom**: Logs show database timeout or connection refused

**Diagnostics**:
```bash
# Check database status
fly postgres db status --app bezgelor-db

# Test connection manually
fly postgres connect --app bezgelor-db
```

**Fix**:
```bash
# Restart database
fly postgres restart --app bezgelor-db

# If DATABASE_URL is wrong, detach and reattach
fly postgres detach bezgelor-db --app bezgelor
fly postgres attach bezgelor-db --app bezgelor
```

### Out of Memory

**Symptom**: App crashes with OOM errors in logs

**Diagnostics**:
```bash
fly logs --app bezgelor | grep -i "memory"
fly status --app bezgelor
```

**Fix**:
```bash
# Immediate: Scale to 6GB or 8GB
fly scale memory 8192 --app bezgelor

# Long-term: Optimize ETS data loading or implement caching
```

### Slow Build Times

**Symptom**: `fly deploy` takes 5+ minutes

**Optimization**:
```bash
# Use remote builder (faster than local)
fly deploy --remote-only --app bezgelor

# Clean build cache if stale
fly deploy --no-cache --app bezgelor
```

## Secrets Reference

| Secret | Required | Generate With | Example |
|--------|----------|---------------|---------|
| `SECRET_KEY_BASE` | Yes | `mix phx.gen.secret` | `abc123...` (64+ chars) |
| `CLOAK_KEY` | Yes | `elixir -e ':crypto.strong_rand_bytes(32) \| Base.encode64() \| IO.puts()'` | `def456...` (44 chars base64) |
| `WORLD_PUBLIC_ADDRESS` | Yes | `fly ips list --app bezgelor` | `203.0.113.45` |
| `PHX_HOST` | Yes | Your Fly app hostname | `bezgelor.fly.dev` |
| `RESEND_API_KEY` | No | https://resend.com | `re_...` |
| `MAIL_FROM` | No | Your verified domain | `noreply@yourdomain.com` |

See `/Users/jrimmer/work/bezgelor/docs/production_setup.md` for complete environment variable reference.

## Cost Estimate

| Resource | Specification | Monthly Cost |
|----------|---------------|--------------|
| App VM | shared-cpu-2x, 4GB RAM | $30 |
| Postgres | shared-cpu-1x, 10GB storage | $15 |
| IPv4 Address | Public IPv4 | $2 |
| Bandwidth | 100GB included, $0.02/GB after | ~$0-5 |
| **Total** | | **~$47-52/month** |

Actual costs may vary based on region and usage. Check current pricing at https://fly.io/docs/about/pricing/

## Additional Resources

- [Fly.io Documentation](https://fly.io/docs/)
- [Elixir Releases Guide](https://hexdocs.pm/mix/Mix.Tasks.Release.html)
- [Phoenix Deployment Guide](https://hexdocs.pm/phoenix/deployment.html)
- [Production Setup Guide](/Users/jrimmer/work/bezgelor/docs/production_setup.md)
- [Rollback Procedures](/Users/jrimmer/work/bezgelor/docs/plans/2025-12-21-fly-io-deployment.md#task-11-create-rollback-procedures-documentation)
- [Backup Strategy](/Users/jrimmer/work/bezgelor/docs/plans/2025-12-21-fly-io-deployment.md#task-10-configure-fly-postgres-backups)
