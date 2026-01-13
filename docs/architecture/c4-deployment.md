# C4 Deployment Diagram

This diagram shows how Bezgelor is deployed in production.

```mermaid
C4Deployment
    title Deployment Diagram - Bezgelor Production

    Deployment_Node(internet, "Internet", "") {
        Deployment_Node(player_machine, "Player Machine", "") {
            Container(client, "WildStar Client", "Windows Executable", "Official game client")
        }
        Deployment_Node(admin_machine, "Admin Machine", "") {
            Container(browser, "Web Browser", "Chrome/Firefox", "Admin access")
        }
    }

    Deployment_Node(hetzner, "Hetzner Cloud", "VPS") {
        Deployment_Node(docker, "Docker", "Container Runtime") {
            Deployment_Node(app_container, "bezgelor Container", "Elixir Release") {
                Container(auth, "Auth Server", "Elixir/OTP", "Port 6600")
                Container(realm, "Realm Server", "Elixir/OTP", "Port 23115")
                Container(world, "World Server", "Elixir/OTP", "Port 24000")
                Container(portal, "Web Portal", "Phoenix", "Port 4000")
                Container(api, "REST API", "Plug", "Port 4002")
            }
            Deployment_Node(db_container, "postgres Container", "PostgreSQL 15") {
                ContainerDb(postgres, "PostgreSQL", "Database", "Port 5433")
            }
        }
        Deployment_Node(volume, "Hetzner Volume", "Persistent Storage") {
            Container(pgdata, "PostgreSQL Data", "Volume Mount", "/var/lib/postgresql/data")
        }
    }

    Rel(client, auth, "Authenticates", "TCP 6600")
    Rel(client, realm, "Character select", "TCP 23115")
    Rel(client, world, "Gameplay", "TCP 24000")
    Rel(browser, portal, "Admin UI", "HTTPS 4000")
    Rel(browser, api, "API calls", "HTTPS 4002")
    Rel(auth, postgres, "Queries", "TCP 5433")
    Rel(realm, postgres, "Queries", "TCP 5433")
    Rel(world, postgres, "Queries", "TCP 5433")
    Rel(portal, postgres, "Queries", "TCP 5433")
    Rel(postgres, pgdata, "Persists to")

    UpdateLayoutConfig($c4ShapeInRow="3", $c4BoundaryInRow="2")
```

## Deployment Components

### Application Container

| Component | Port | Protocol | Purpose |
|-----------|------|----------|---------|
| Auth Server | 6600 | TCP/Binary | SRP6 authentication |
| Realm Server | 23115 | TCP/Binary | Character selection |
| World Server | 24000 | TCP/Binary | Game world simulation |
| Web Portal | 4000 | HTTP/WS | Admin interface |
| REST API | 4002 | HTTP | Monitoring and data |

### Database Container

| Component | Port | Purpose |
|-----------|------|---------|
| PostgreSQL | 5433 | Persistent data storage |

### Persistent Storage

| Volume | Mount Point | Purpose |
|--------|-------------|---------|
| Hetzner Volume | /var/lib/postgresql/data | Database files survive container restarts |

## Network Configuration

```
External Access:
  - 6600/tcp   → Auth Server
  - 23115/tcp  → Realm Server
  - 24000/tcp  → World Server
  - 4000/tcp   → Web Portal (optional, can be internal)
  - 4002/tcp   → REST API (optional, can be internal)

Internal Only:
  - 5433/tcp   → PostgreSQL (container network only)
```

## Release Configuration

The Elixir release includes all umbrella apps:

```elixir
# mix.exs release config
releases: [
  bezgelor_portal: [
    applications: [
      bezgelor_portal: :permanent,
      bezgelor_auth: :permanent,
      bezgelor_realm: :permanent,
      bezgelor_world: :permanent,
      bezgelor_db: :permanent,
      bezgelor_data: :permanent,
      bezgelor_core: :permanent,
      bezgelor_crypto: :permanent,
      bezgelor_protocol: :permanent
    ]
  ]
]
```

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `AUTH_PORT` | 6600 | Auth server listen port |
| `REALM_PORT` | 23115 | Realm server listen port |
| `WORLD_PORT` | 24000 | World server listen port |
| `WORLD_PUBLIC_ADDRESS` | - | Public IP for client connections |
| `POSTGRES_HOST` | localhost | Database host |
| `POSTGRES_PORT` | 5433 | Database port |
| `POSTGRES_DB` | bezgelor | Database name |
| `POSTGRES_USER` | - | Database user |
| `POSTGRES_PASSWORD` | - | Database password |
| `SECRET_KEY_BASE` | - | Phoenix secret key |
