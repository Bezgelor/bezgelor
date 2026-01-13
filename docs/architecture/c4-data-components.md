# C4 Component Diagram - Data Layer

This diagram shows the data architecture including both persistent (PostgreSQL) and in-memory (ETS) data stores.

```mermaid
C4Component
    title Component Diagram - Data Layer (bezgelor_db + bezgelor_data)

    Container_Ext(auth, "Auth Server", "Authentication")
    Container_Ext(realm, "Realm Server", "Character selection")
    Container_Ext(world, "World Server", "Game simulation")
    Container_Ext(portal, "Web Portal", "Account management")

    Container_Boundary(db, "Database Layer (bezgelor_db)") {
        Component(repo, "Ecto.Repo", "Ecto", "Database connection pool")

        Component(accounts, "Accounts Context", "Module", "Users, sessions, bans")
        Component(characters, "Characters Context", "Module", "Character CRUD, appearance")
        Component(guilds, "Guilds Context", "Module", "Guilds, ranks, membership")
        Component(inventory, "Inventory Context", "Module", "Items, containers, equipment")
        Component(social, "Social Context", "Module", "Friends, ignore, mail")
        Component(quests, "Quests Context", "Module", "Quest log, progress, rewards")
        Component(economy, "Economy Context", "Module", "Currency, transactions, prices")
        Component(pvp, "PvP Context", "Module", "Ratings, seasons, matchmaking")
        Component(housing, "Housing Context", "Module", "Plots, decor, neighbors")

        Component(schemas, "Schema Modules", "Ecto.Schema", "Database table mappings")
    }

    Container_Boundary(data, "Static Data (bezgelor_data)") {
        Component(store, "Store", "GenServer", "Data loading and caching")
        Component(ets, "ETS Tables", "ETS", "In-memory game data")
        Component(json, "JSON Files", "Files", "priv/data/*.json")
    }

    ContainerDb(postgres, "PostgreSQL", "Database", "Port 5433")

    Rel(auth, accounts, "Validates users")
    Rel(realm, characters, "Loads character list")
    Rel(world, characters, "Updates stats")
    Rel(world, inventory, "Manages items")
    Rel(world, guilds, "Guild operations")
    Rel(world, quests, "Quest progress")
    Rel(world, pvp, "Rating updates")
    Rel(portal, accounts, "Account management")

    Rel(accounts, repo, "Uses")
    Rel(characters, repo, "Uses")
    Rel(guilds, repo, "Uses")
    Rel(inventory, repo, "Uses")
    Rel(social, repo, "Uses")
    Rel(quests, repo, "Uses")
    Rel(economy, repo, "Uses")
    Rel(pvp, repo, "Uses")
    Rel(housing, repo, "Uses")

    Rel(accounts, schemas, "Uses")
    Rel(characters, schemas, "Uses")

    Rel(repo, postgres, "Queries", "TCP 5433")

    Rel(world, ets, "Reads game data")
    Rel(store, json, "Loads on startup")
    Rel(store, ets, "Populates")

    UpdateLayoutConfig($c4ShapeInRow="5", $c4BoundaryInRow="1")
```

## Database Contexts (bezgelor_db)

Each context provides a public API for a domain:

| Context | Tables | Responsibility |
|---------|--------|----------------|
| **Accounts** | users, sessions, bans | User authentication, session management |
| **Characters** | characters, character_appearance, stats | Character CRUD, customization |
| **Guilds** | guilds, guild_members, guild_ranks | Guild management, permissions |
| **Inventory** | items, containers, equipped_items | Item storage, equipment |
| **Social** | friends, ignored, mail | Social features, messaging |
| **Quests** | quest_log, quest_progress | Quest tracking, completion |
| **Economy** | currency, transactions, vendor_prices | Gold, commodities, trading |
| **PvP** | arena_ratings, bg_stats, seasons | Competitive rankings |
| **Housing** | housing_plots, decor, neighbors | Player housing |

Additional contexts: Instances, Pets, Mounts, Achievements, Paths, Reputation, Trading

## Static Data (bezgelor_data)

Loaded into ETS on startup from JSON files:

| Data Type | Source File | Contents |
|-----------|-------------|----------|
| **Creatures** | creature2.json | Spawns, stats, loot tables |
| **Spells** | spell4.json | Abilities, effects, cooldowns |
| **Items** | item2.json | Equipment, consumables |
| **Zones** | worldzone.json | Zone definitions, bounds |
| **Achievements** | achievement.json | Categories, criteria |
| **Classes** | class.json | Abilities, progression |

## Data Access Patterns

```elixir
# Persistent data (Ecto)
BezgelorDb.Characters.get_character!(character_id)
BezgelorDb.Inventory.add_item(character_id, item_id, count)
BezgelorDb.Guilds.create_guild(params)

# Static data (ETS - O(1) lookup)
BezgelorData.creatures(creature_id)
BezgelorData.spells(spell_id)
BezgelorData.zones(zone_id)
```

## Schema Organization

```
lib/bezgelor_db/schema/
├── user.ex                 # Account schema
├── character.ex            # Character schema
├── character_appearance.ex # Customization
├── guild.ex               # Guild schema
├── guild_member.ex        # Membership
├── item.ex                # Inventory item
├── quest_log.ex           # Quest progress
└── ...                    # 30+ schemas
```
