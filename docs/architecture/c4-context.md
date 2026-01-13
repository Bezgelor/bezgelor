# C4 System Context Diagram

This diagram shows Bezgelor (WildStar Server Emulator) and its relationships with external actors and systems.

```mermaid
C4Context
    title System Context Diagram - Bezgelor WildStar Server Emulator

    Person(player, "Player", "WildStar game player connecting via the official game client")
    Person(admin, "Administrator", "Server operator managing accounts and monitoring")

    System(bezgelor, "Bezgelor Server", "WildStar MMORPG server emulator providing authentication, realm selection, and game world simulation")

    System_Ext(client, "WildStar Game Client", "Official WildStar game client (binary)")
    System_Ext(postgres, "PostgreSQL Database", "Stores accounts, characters, inventory, guilds, and all persistent game data")
    System_Ext(browser, "Web Browser", "Used for account management and server administration")

    Rel(player, client, "Plays game via")
    Rel(client, bezgelor, "Connects via WildStar binary protocol", "TCP 6600, 23115, 24000")
    Rel(admin, browser, "Manages server via")
    Rel(browser, bezgelor, "Accesses portal and API", "HTTP 4000, 4002")
    Rel(bezgelor, postgres, "Reads/writes persistent data", "TCP 5433")

    UpdateLayoutConfig($c4ShapeInRow="3", $c4BoundaryInRow="1")
```

## Actors

| Actor | Description |
|-------|-------------|
| **Player** | End user playing WildStar through the official game client |
| **Administrator** | Server operator with access to the web portal for management |

## External Systems

| System | Description | Protocol |
|--------|-------------|----------|
| **WildStar Game Client** | Official game client binary connecting to game servers | WildStar Binary Protocol |
| **PostgreSQL Database** | Persistent storage for all game data | Port 5433 (non-standard) |
| **Web Browser** | Access point for portal and API interfaces | HTTP/HTTPS |

## Communication Flows

1. **Player → Game Client → Bezgelor**: Players use the WildStar client to connect to game servers
2. **Admin → Browser → Bezgelor**: Administrators manage the server via web portal (port 4000) or API (port 4002)
3. **Bezgelor → PostgreSQL**: All persistent data (accounts, characters, guilds, inventory, etc.)
