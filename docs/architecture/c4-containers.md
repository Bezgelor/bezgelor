# C4 Container Diagram

This diagram shows the high-level technical building blocks (Elixir umbrella apps) that make up Bezgelor.

```mermaid
C4Container
    title Container Diagram - Bezgelor Umbrella Applications

    Person(player, "Player", "WildStar game player")
    Person(admin, "Administrator", "Server operator")

    System_Ext(client, "WildStar Client", "Official game client")
    System_Ext(browser, "Web Browser", "")

    System_Boundary(bezgelor, "Bezgelor Server") {
        Container(auth, "Auth Server", "Elixir/OTP", "STS authentication server handling SRP6 login<br/>Port 6600")
        Container(realm, "Realm Server", "Elixir/OTP", "Character selection and realm info<br/>Port 23115")
        Container(world, "World Server", "Elixir/OTP", "Game world simulation, combat, zones<br/>Port 24000")

        Container(portal, "Web Portal", "Phoenix LiveView", "Account management, admin console<br/>Port 4000")
        Container(api, "REST API", "Plug/Cowboy", "Server monitoring and data API<br/>Port 4002")

        Container(protocol, "Protocol Library", "Elixir", "WildStar binary protocol, packet handling, TCP connections")
        Container(db, "Database Layer", "Ecto", "30+ context modules for data access")
        Container(data, "Static Data", "ETS", "Game data loaded from JSON files")
        Container(core, "Core Library", "Elixir", "Shared types, game logic, combat calculations")
        Container(crypto, "Crypto Library", "Elixir", "SRP6, packet encryption, password hashing")
    }

    ContainerDb(postgres, "PostgreSQL", "Database", "Accounts, characters, guilds, inventory, quests")

    Rel(client, auth, "Authenticates", "TCP 6600")
    Rel(client, realm, "Selects character", "TCP 23115")
    Rel(client, world, "Plays game", "TCP 24000")

    Rel(browser, portal, "Uses", "HTTP 4000")
    Rel(browser, api, "Queries", "HTTP 4002")

    Rel(auth, protocol, "Uses")
    Rel(realm, protocol, "Uses")
    Rel(world, protocol, "Uses")

    Rel(auth, crypto, "Uses")
    Rel(protocol, crypto, "Uses")

    Rel(auth, db, "Validates accounts")
    Rel(realm, db, "Loads characters")
    Rel(world, db, "Persists state")
    Rel(portal, db, "Manages data")

    Rel(world, data, "Reads game data")
    Rel(world, core, "Uses game logic")

    Rel(db, postgres, "Reads/Writes", "TCP 5433")

    UpdateLayoutConfig($c4ShapeInRow="4", $c4BoundaryInRow="1")
```

## Container Descriptions

### Server Layer (Network-Facing)

| Container | Technology | Port | Responsibility |
|-----------|------------|------|----------------|
| **Auth Server** | Elixir/OTP, Ranch | 6600 | SRP6 authentication, game token generation |
| **Realm Server** | Elixir/OTP, Ranch | 23115 | Character list, realm selection, session keys |
| **World Server** | Elixir/OTP, Ranch | 24000 | Game simulation, zones, combat, entities |
| **Web Portal** | Phoenix LiveView | 4000 | Account dashboard, character viewer, admin |
| **REST API** | Plug/Cowboy | 4002 | Server monitoring, data queries |

### Foundation Layer (Shared Libraries)

| Container | Technology | Responsibility |
|-----------|------------|----------------|
| **Protocol Library** | Elixir | Binary protocol parsing, packet handlers, TCP connections |
| **Database Layer** | Ecto | Context modules for all database operations |
| **Static Data** | ETS | In-memory game data (creatures, spells, items, zones) |
| **Core Library** | Elixir | Shared types (Entity, Vector3), game calculations |
| **Crypto Library** | Elixir | SRP6 algorithm, packet encryption, password hashing |

### Data Storage

| Container | Technology | Responsibility |
|-----------|------------|----------------|
| **PostgreSQL** | Database | Persistent storage for all game data |

## Data Flow

```
Player Login Flow:
1. Client → Auth (6600): SRP6 authentication → Game token
2. Client → Realm (23115): Token validation → Character list → Session key
3. Client → World (24000): Session validation → World entry → Gameplay
```
