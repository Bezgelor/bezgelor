# Bezgelor Account Portal - Design Document

**Date:** 2025-12-12
**Status:** Approved

## Overview

A new `bezgelor_portal` umbrella app providing:
- User account registration, login, and management
- Admin panel for server/player management
- Real-time analytics dashboard
- OpenTelemetry integration for observability

## Architecture Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| App structure | New `bezgelor_portal` umbrella app | Separates REST API (stateless, token auth) from portal (sessions, CSRF, LiveView) |
| Web framework | Phoenix + LiveView | Real-time dashboard updates, modern Elixir web stack |
| Authentication | Reuse SRP6 credentials | Single password for game client and web portal |
| Authorization | Pure RBAC | Permissions (seeded) → Roles (admin-managed) → Users (multiple roles) |
| Telemetry | OpenTelemetry | Standardized metrics/traces, exportable to Honeycomb/Datadog/etc |
| 2FA (TOTP) | Web portal only | Optional for users, required for admin roles |

## Schema Changes

### New Tables

```sql
-- Permissions are code-defined and seeded
CREATE TABLE permissions (
  id SERIAL PRIMARY KEY,
  key VARCHAR(100) UNIQUE NOT NULL,      -- e.g., "ban_users"
  category VARCHAR(50) NOT NULL,          -- e.g., "user_management"
  description TEXT,
  inserted_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);

-- Roles are admin-managed
CREATE TABLE roles (
  id SERIAL PRIMARY KEY,
  name VARCHAR(100) UNIQUE NOT NULL,      -- e.g., "Moderator"
  description TEXT,
  protected BOOLEAN DEFAULT FALSE,        -- Can't delete built-in roles
  inserted_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);

-- Join table: which permissions each role has
CREATE TABLE role_permissions (
  role_id INTEGER REFERENCES roles(id) ON DELETE CASCADE,
  permission_id INTEGER REFERENCES permissions(id) ON DELETE CASCADE,
  PRIMARY KEY (role_id, permission_id)
);

-- Join table: which roles each account has
CREATE TABLE account_roles (
  account_id INTEGER REFERENCES accounts(id) ON DELETE CASCADE,
  role_id INTEGER REFERENCES roles(id) ON DELETE CASCADE,
  assigned_by INTEGER REFERENCES accounts(id),
  assigned_at TIMESTAMP NOT NULL,
  PRIMARY KEY (account_id, role_id)
);

-- Audit log for admin actions
CREATE TABLE admin_audit_log (
  id SERIAL PRIMARY KEY,
  admin_account_id INTEGER REFERENCES accounts(id),
  action VARCHAR(100) NOT NULL,           -- e.g., "ban_user", "grant_item"
  target_type VARCHAR(50),                -- e.g., "account", "character"
  target_id INTEGER,
  details JSONB,                          -- Action-specific data
  ip_address INET,
  inserted_at TIMESTAMP NOT NULL
);
```

### Accounts Table Extensions

```sql
ALTER TABLE accounts ADD COLUMN email_verified_at TIMESTAMP;
ALTER TABLE accounts ADD COLUMN totp_secret_encrypted BYTEA;
ALTER TABLE accounts ADD COLUMN totp_enabled_at TIMESTAMP;
ALTER TABLE accounts ADD COLUMN backup_codes_hashed TEXT[];  -- Array of hashed codes
ALTER TABLE accounts ADD COLUMN discord_id VARCHAR(50);
ALTER TABLE accounts ADD COLUMN discord_username VARCHAR(100);
ALTER TABLE accounts ADD COLUMN discord_linked_at TIMESTAMP;
```

## Seeded Permissions

### User Management
| Key | Description |
|-----|-------------|
| `view_users` | Search and view account details |
| `reset_passwords` | Generate password reset or force new password |
| `ban_users` | Ban or suspend accounts |
| `unban_users` | Lift bans and suspensions |
| `view_login_history` | View IP addresses and login timestamps |
| `impersonate_users` | View-only impersonation |

### Character Management
| Key | Description |
|-----|-------------|
| `view_characters` | View character details, inventory, currency |
| `modify_character_items` | Add/remove items from inventory |
| `modify_character_currency` | Add/subtract currency |
| `modify_character_level` | Set level, add XP |
| `teleport_character` | Move character to location |
| `rename_character` | Force name change |
| `delete_characters` | Soft delete characters |
| `restore_characters` | Restore deleted characters |
| `view_character_mail` | View sent/received mail |
| `view_character_trades` | View trade history |

### Achievements & Collections
| Key | Description |
|-----|-------------|
| `grant_achievements` | Unlock achievements |
| `grant_titles` | Unlock titles |
| `grant_mounts` | Add mounts to collection |
| `grant_costumes` | Unlock costume pieces |

### Economy
| Key | Description |
|-----|-------------|
| `grant_currency` | Gift gold or other currencies |
| `grant_items` | Send items via system mail |
| `view_economy_stats` | View gold circulation, sinks/faucets |
| `view_transaction_log` | View gold transfers, sales |
| `rollback_transactions` | Reverse specific transactions |

### Events & Content
| Key | Description |
|-----|-------------|
| `manage_events` | Start/stop public events |
| `spawn_creatures` | Spawn creatures at location |
| `broadcast_message` | Server-wide announcements |
| `schedule_maintenance` | Set maintenance windows |
| `manage_world_bosses` | Force spawn, reset timers |

### Instances
| Key | Description |
|-----|-------------|
| `view_instances` | View active dungeon/raid instances |
| `close_instances` | Force close instances |
| `reset_lockouts` | Clear raid/dungeon lockouts |

### PvP
| Key | Description |
|-----|-------------|
| `view_pvp_stats` | View arena teams, battleground stats |
| `reset_arena_ratings` | Reset ratings for team or player |
| `ban_from_pvp` | Temporary PvP ban |

### Server Operations
| Key | Description |
|-----|-------------|
| `maintenance_mode` | Enable/disable maintenance |
| `restart_zones` | Reload specific zone instances |
| `reload_data` | Hot-reload game data from ETS |
| `kick_players` | Force disconnect players |
| `view_server_logs` | View recent errors/warnings |

### Administration
| Key | Description |
|-----|-------------|
| `manage_roles` | Create/edit/delete roles |
| `assign_roles` | Assign roles to users |
| `view_audit_log` | View admin action history |
| `export_audit_log` | Download audit logs |

## Seeded Roles (Protected)

### Moderator
Community management focused:
- `view_users`
- `ban_users`
- `unban_users`
- `view_characters`
- `view_login_history`
- `broadcast_message`
- `kick_players`
- `view_audit_log`

### Admin
Full player support + some server operations:
- All Moderator permissions
- `reset_passwords`
- `modify_character_items`
- `modify_character_currency`
- `modify_character_level`
- `teleport_character`
- `rename_character`
- `delete_characters`
- `restore_characters`
- `grant_achievements`
- `grant_titles`
- `grant_mounts`
- `grant_costumes`
- `grant_currency`
- `grant_items`
- `view_economy_stats`
- `view_transaction_log`
- `manage_events`
- `spawn_creatures`
- `view_instances`
- `close_instances`
- `reset_lockouts`
- `view_pvp_stats`
- `view_server_logs`

### Super Admin
Everything including role management:
- All permissions
- `manage_roles`
- `assign_roles`
- `rollback_transactions`
- `maintenance_mode`
- `restart_zones`
- `reload_data`
- `reset_arena_ratings`
- `ban_from_pvp`
- `impersonate_users`
- `export_audit_log`

## User Portal Features

### Registration & Authentication
- Email registration with verification (confirmation link)
- Login with SRP6 credentials (server-side verifier comparison)
- Optional TOTP setup (QR code, backup codes)
- Password change (requires current password)
- Email change (requires re-verification)
- Account deletion (double-confirm by typing email)

### Discord Integration
- OAuth2 link flow
- Display linked Discord username
- "Discord Linked" badge visible in-game
- Unlink option

### Character Viewer (Read-Only)
- List all characters with basic info (name, level, class, race)
- Character details: stats, location, play time, last online
- Inventory viewer: equipped items, bags, bank
- Currency display: gold, elder gems, renown, prestige, etc.
- Guild association
- Tradeskill levels and recipes known
- Achievements progress
- Mount/pet/costume collections
- Delete character option

## Admin Panel Features

### Dashboard
- Quick stats: online players, registered accounts, active zones
- Recent admin actions
- Server health indicators

### User Management
- Search by email, character name, account ID, Discord ID
- Account detail view with full history
- Actions: reset password, ban/suspend, unban, assign roles

### Character Management
- Search by name or browse by account
- Full character inspection
- Modification actions (based on permissions)

### Economy Tools
- Server economy overview (gold circulation, daily sinks/faucets)
- Transaction search and history
- Gift tools (currency, items via system mail)

### Event Management
- Public event controls (start, stop, schedule)
- World boss management
- Creature spawning tools

### Instance Management
- Active instance list with player counts
- Instance details and controls
- Lockout management

### Server Operations
- Maintenance mode toggle with MOTD
- Broadcast message sender
- Zone restart controls
- Connected player list with kick option

### Role Management (Super Admin)
- List all roles with permission counts
- Create new roles
- Edit role permissions (checkbox grid by category)
- Delete non-protected roles (with confirmation)
- User role assignment

### Audit Log
- Searchable/filterable action history
- Export to CSV/JSON

## Analytics Dashboard (LiveView Real-Time)

### Player Statistics
- Registered accounts (total, growth chart)
- Online players (current, 24h chart)
- Peak concurrent (daily, weekly, monthly records)
- Players by zone (live map or table)
- New registrations per day

### BEAM/OTP Metrics
- Total process count
- Memory breakdown: total, processes, atoms, binaries, ETS
- Scheduler utilization (per scheduler)
- Reduction counts
- Message queue lengths (for key processes)
- GC statistics

### Game-Specific Metrics
- Active zone instances
- Active dungeon/raid instances
- Queue sizes (dungeon finder, PvP)
- Combat events per second
- Packets processed per second

### Economy Metrics
- Total gold in circulation
- Gold generated today (quest rewards, loot, etc.)
- Gold removed today (repairs, AH fees, vendors)
- Items crafted today
- AH volume

### System Metrics (via :os_mon)
- CPU usage (per core)
- System memory usage
- Disk I/O (if applicable)
- Network throughput

### Update Strategy
- Fast metrics (online count, process count): Push every 1-2 seconds via PubSub
- Medium metrics (zone populations): Push every 5-10 seconds
- Slow metrics (registered accounts, economy totals): Poll every 30-60 seconds
- Historical data: Query on page load, optionally refresh

## OpenTelemetry Integration

### Instrumentation
- `opentelemetry_phoenix` - HTTP request tracing
- `opentelemetry_ecto` - Database query tracing
- `opentelemetry_cowboy` - (if needed for API)
- Custom spans for game logic (spell casts, combat, zone transitions)

### Exporters
- Development: Console exporter (logs to terminal)
- Production: OTLP exporter to Honeycomb/Grafana/Jaeger

### Configuration
```elixir
# config/runtime.exs
config :opentelemetry,
  span_processor: :batch,
  traces_exporter: {:otlp, endpoint: System.get_env("OTEL_EXPORTER_OTLP_ENDPOINT")}

config :opentelemetry, :resource,
  service: [name: "bezgelor", namespace: "mmo"]
```

### Custom Telemetry Events
```elixir
# Player events
:telemetry.execute([:bezgelor, :player, :login], %{count: 1}, %{zone_id: zone_id})
:telemetry.execute([:bezgelor, :player, :logout], %{count: 1, session_duration: duration}, %{})

# Combat events
:telemetry.execute([:bezgelor, :combat, :damage], %{amount: damage}, %{spell_id: id})

# Economy events
:telemetry.execute([:bezgelor, :economy, :gold_transfer], %{amount: gold}, %{type: :trade})
```

## Tech Stack

### Dependencies (bezgelor_portal)
```elixir
defp deps do
  [
    {:phoenix, "~> 1.7"},
    {:phoenix_live_view, "~> 0.20"},
    {:phoenix_html, "~> 4.0"},
    {:phoenix_live_dashboard, "~> 0.8"},
    {:heroicons, "~> 0.5"},
    {:tailwind, "~> 0.2"},
    {:nimble_totp, "~> 1.0"},
    {:ueberauth, "~> 0.10"},
    {:ueberauth_discord, "~> 0.7"},
    {:opentelemetry, "~> 1.3"},
    {:opentelemetry_exporter, "~> 1.6"},
    {:opentelemetry_phoenix, "~> 1.1"},
    {:opentelemetry_ecto, "~> 1.1"},
    # Umbrella deps
    {:bezgelor_db, in_umbrella: true},
    {:bezgelor_crypto, in_umbrella: true},
    {:bezgelor_world, in_umbrella: true},
    {:bezgelor_data, in_umbrella: true}
  ]
end
```

## Implementation Phases

### Phase 1: Foundation
- Create `bezgelor_portal` Phoenix app
- Database migrations (permissions, roles, account extensions)
- Seed permissions and default roles
- Basic auth (login/logout with SRP6)

### Phase 2: User Portal
- Registration with email verification
- Account management (password change, email change)
- Character viewer (read-only)
- TOTP setup and enforcement

### Phase 3: Admin Panel - Core
- Admin layout and navigation
- User search and management
- Character viewer and basic modifications
- Audit logging

### Phase 4: Admin Panel - Advanced
- Economy tools
- Event management
- Instance controls
- Role management UI

### Phase 5: Analytics Dashboard
- LiveView dashboard structure
- Player statistics (real-time)
- BEAM/OTP metrics
- Game-specific metrics

### Phase 6: Integrations
- Discord OAuth linking
- OpenTelemetry instrumentation
- External exporter configuration

## Security Considerations

- All admin actions logged to audit table
- TOTP required for any user with admin roles
- Session timeout for admin pages (shorter than regular users)
- Rate limiting on login attempts
- CSRF protection on all forms
- Role permission check on every admin action
- Encrypted TOTP secrets at rest
- Hashed backup codes (one-way)
