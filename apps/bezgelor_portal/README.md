# BezgelorPortal

Phoenix LiveView web interface for players and administrators.

## Features

### Player Dashboard
- Character overview with stats, gear, and progression
- Inventory browser (bags, bank, equipped items)
- Achievement tracker across all categories
- Guild management and roster viewing
- Mail center with attachment support
- Account settings and preferences

### Admin Console
- Real-time server monitoring (players, zones, health)
- User management (search, suspend, ban, password reset)
- Character tools (grant items/currency, teleport, reset lockouts)
- Economy monitoring and transaction history
- Instance management (dungeons, raids)
- Event control (public events, world bosses)
- Analytics and player activity trends
- Audit logs with filtering

## Access Control

Role-based permissions (Player, GM, Admin, SuperAdmin) control feature access. All admin actions are logged.

## Running

```bash
# Start with live reload (development)
mix phx.server

# Or inside IEx
iex -S mix phx.server
```

Visit http://localhost:4000 in your browser.

## Configuration

See `config/dev.exs` for development settings and `config/runtime.exs` for environment variable configuration.
