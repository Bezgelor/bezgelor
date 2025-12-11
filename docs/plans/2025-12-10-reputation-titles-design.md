# Reputation & Titles System Design

**Date:** 2025-12-10

## Summary

Complete the Reputation system (Phase 7.12) by adding:
1. Faction gains from kills and quests
2. Reputation-gated vendors
3. Full title system with account-wide tracking

## Existing Infrastructure

Already implemented:
- `BezgelorDb.Schema.Reputation` - character_id, faction_id, standing
- `BezgelorCore.Reputation` - 8 levels (hated→exalted), thresholds, vendor discounts
- `BezgelorDb.Reputation` - context with get/set/modify, `can_purchase?`, `meets_requirement?`
- `BezgelorWorld.Handler.ReputationHandler` - send list/updates
- Protocol packets: ServerReputationList, ServerReputationUpdate
- 23 tests covering all core functionality

## Part 1: Reputation Integration

### Faction Gains from Kills

Creature data includes configurable reputation rewards:

```json
{
  "id": 12345,
  "name": "Dominion Soldier",
  "reputation_rewards": [
    {"faction_id": 166, "amount": 25},
    {"faction_id": 167, "amount": -10}
  ]
}
```

On creature death, award all reputation rewards to the killer:

```elixir
# In combat/creature kill flow
Enum.each(creature.reputation_rewards, fn reward ->
  ReputationHandler.modify_reputation(conn, char_id, reward.faction_id, reward.amount)
end)
```

### Faction Gains from Quests

Quest definitions include optional reputation rewards:

```json
{
  "id": 5001,
  "name": "Defend the Settlement",
  "reputation_rewards": [
    {"faction_id": 166, "amount": 250}
  ]
}
```

On quest turn-in, award each reputation reward after other rewards.

### Reputation-Gated Vendors

Vendor NPCs have optional `required_reputation`:

```json
{
  "vendor_id": 8001,
  "required_reputation": {"faction_id": 166, "level": "friendly"}
}
```

Before showing vendor UI:
1. Check `Reputation.meets_requirement?(char_id, faction_id, level)`
2. If not met, send error packet with required level
3. If met, show vendor with applicable discount from `get_vendor_discount/2`

## Part 2: Title System

### Design Decisions

- **Storage**: Per-account (titles unlocked once available to all characters)
- **Sources**: Reputation, achievements, quests, paths, store purchases, events
- **Data model**: Hybrid - static definitions in bezgelor_data, player state in database

### Title Categories

| Category | Source | Example |
|----------|--------|---------|
| reputation | Reaching faction standing | "Exile's Champion" (Exalted with Exiles) |
| achievement | Earning achievements | "Lore Seeker" (100 datacubes) |
| quest | Completing specific quests | "Savior of Thayd" |
| path | Path milestones | "Master Explorer" |
| store | Store purchases | "Deluxe Founder" |
| event | Seasonal/world events | "Shade's Eve Survivor" |
| special | GM granted, legacy | "Developer" |

### Static Data (titles.json)

```json
{
  "titles": {
    "1001": {
      "name": "Exile's Champion",
      "description": "Reached Exalted standing with the Exiles",
      "category": "reputation",
      "rarity": "epic",
      "unlock_type": "reputation",
      "unlock_requirements": {"faction_id": 166, "level": "exalted"}
    },
    "1002": {
      "name": "Dominion's Bane",
      "description": "Reached Hated standing with the Dominion",
      "category": "reputation",
      "rarity": "rare",
      "unlock_type": "reputation",
      "unlock_requirements": {"faction_id": 167, "level": "hated"}
    },
    "2001": {
      "name": "Lore Seeker",
      "description": "Discovered 100 datacubes",
      "category": "achievement",
      "rarity": "rare",
      "unlock_type": "achievement",
      "unlock_requirements": {"achievement_id": 500}
    },
    "3001": {
      "name": "Savior of Thayd",
      "description": "Completed the defense of Thayd",
      "category": "quest",
      "rarity": "epic",
      "unlock_type": "quest",
      "unlock_requirements": {"quest_id": 7500}
    },
    "4001": {
      "name": "Master Explorer",
      "description": "Reached max Explorer path level",
      "category": "path",
      "rarity": "legendary",
      "unlock_type": "path",
      "unlock_requirements": {"path": "explorer", "level": 30}
    }
  }
}
```

### Database Schema

```elixir
# New table: account_titles
create table(:account_titles) do
  add :account_id, references(:accounts, on_delete: :delete_all), null: false
  add :title_id, :integer, null: false
  add :unlocked_at, :utc_datetime, null: false
  timestamps()
end

create unique_index(:account_titles, [:account_id, :title_id])
create index(:account_titles, [:account_id])

# Add active title to accounts
alter table(:accounts) do
  add :active_title_id, :integer
end
```

### Title Unlock Flow

```
[Trigger Event] → [TitleManager.check_unlocks] → [Grant if new] → [Notify client]
       ↓                     ↓                          ↓                ↓
  Reputation           Load matching              account_titles    ServerTitleUnlocked
  Achievement          titles from data              INSERT              packet
  Quest complete       Check requirements
  Path progress
```

### Core Module: BezgelorCore.Titles

```elixir
defmodule BezgelorCore.Titles do
  @moduledoc "Title unlock logic and requirement checking."

  @doc "Get all titles that should unlock for a reputation level change."
  @spec titles_for_reputation(integer(), atom()) :: [integer()]
  def titles_for_reputation(faction_id, level)

  @doc "Get all titles that should unlock for an achievement."
  @spec titles_for_achievement(integer()) :: [integer()]
  def titles_for_achievement(achievement_id)

  @doc "Get all titles that should unlock for quest completion."
  @spec titles_for_quest(integer()) :: [integer()]
  def titles_for_quest(quest_id)

  @doc "Get all titles that should unlock for path progress."
  @spec titles_for_path(atom(), integer()) :: [integer()]
  def titles_for_path(path, level)

  @doc "Check if account meets requirements for a specific title."
  @spec meets_requirements?(map(), map()) :: boolean()
  def meets_requirements?(title_def, account_state)
end
```

### Database Context: BezgelorDb.Titles

```elixir
defmodule BezgelorDb.Titles do
  @doc "Get all unlocked titles for account."
  @spec get_titles(integer()) :: [AccountTitle.t()]
  def get_titles(account_id)

  @doc "Check if account has unlocked a title."
  @spec has_title?(integer(), integer()) :: boolean()
  def has_title?(account_id, title_id)

  @doc "Grant title to account (idempotent)."
  @spec grant_title(integer(), integer()) :: {:ok, AccountTitle.t()} | {:already_owned, AccountTitle.t()}
  def grant_title(account_id, title_id)

  @doc "Set active displayed title."
  @spec set_active_title(integer(), integer() | nil) :: {:ok, Account.t()} | {:error, :not_owned}
  def set_active_title(account_id, title_id)

  @doc "Get active title for account."
  @spec get_active_title(integer()) :: integer() | nil
  def get_active_title(account_id)
end
```

### Protocol Packets

| Packet | Direction | Wire Format |
|--------|-----------|-------------|
| ServerTitleList | S→C | count:u16, titles[]:(id:u32, unlocked_at:u64) |
| ServerTitleUnlocked | S→C | title_id:u32, unlocked_at:u64 |
| ClientSetActiveTitle | C→S | title_id:u32 (0 = clear) |
| ServerActiveTitleChanged | S→C | title_id:u32, success:u8 |
| ClientGetTitles | C→S | (empty) |

### Handler: BezgelorWorld.Handler.TitleHandler

```elixir
defmodule BezgelorWorld.Handler.TitleHandler do
  @doc "Send full title list on login."
  def send_title_list(connection_pid, account_id)

  @doc "Check and grant titles after reputation change."
  def check_reputation_titles(connection_pid, account_id, faction_id, new_level)

  @doc "Check and grant titles after achievement."
  def check_achievement_titles(connection_pid, account_id, achievement_id)

  @doc "Check and grant titles after quest completion."
  def check_quest_titles(connection_pid, account_id, quest_id)

  @doc "Handle client request to change active title."
  def handle_set_active_title(packet, state)
end
```

## Integration Points

### ReputationHandler Changes

After `modify_reputation` succeeds and level changes:
```elixir
old_level = RepCore.standing_to_level(old_standing)
new_level = RepCore.standing_to_level(new_standing)

if old_level != new_level do
  TitleHandler.check_reputation_titles(conn, account_id, faction_id, new_level)
end
```

### QuestHandler Changes

After quest turn-in:
```elixir
# Award reputation rewards
Enum.each(quest.reputation_rewards, fn reward ->
  ReputationHandler.modify_reputation(conn, char_id, reward.faction_id, reward.amount)
end)

# Check quest-specific titles
TitleHandler.check_quest_titles(conn, account_id, quest.id)
```

### AchievementHandler Changes

After achievement earned:
```elixir
TitleHandler.check_achievement_titles(conn, account_id, achievement_id)
```

### VendorHandler Changes

Before showing vendor:
```elixir
case vendor.required_reputation do
  nil ->
    show_vendor(conn, vendor, discount: 0.0)

  %{faction_id: fid, level: required_level} ->
    if Reputation.meets_requirement?(char_id, fid, required_level) do
      discount = Reputation.get_vendor_discount(char_id, fid)
      show_vendor(conn, vendor, discount: discount)
    else
      send_error(conn, :reputation_too_low, %{required: required_level})
    end
end
```

## File Summary

| App | File | Action | LOC |
|-----|------|--------|-----|
| bezgelor_data | priv/data/titles.json | Create | ~50 |
| bezgelor_data | lib/bezgelor_data.ex | Modify | +20 |
| bezgelor_core | lib/bezgelor_core/titles.ex | Create | ~100 |
| bezgelor_db | priv/repo/migrations/*_add_titles.exs | Create | ~30 |
| bezgelor_db | lib/bezgelor_db/schema/account_title.ex | Create | ~30 |
| bezgelor_db | lib/bezgelor_db/titles.ex | Create | ~80 |
| bezgelor_protocol | packets/world/server_title_list.ex | Create | ~30 |
| bezgelor_protocol | packets/world/server_title_unlocked.ex | Create | ~20 |
| bezgelor_protocol | packets/world/server_active_title_changed.ex | Create | ~20 |
| bezgelor_protocol | packets/world/client_set_active_title.ex | Create | ~20 |
| bezgelor_protocol | packets/world/client_get_titles.ex | Create | ~15 |
| bezgelor_world | handler/title_handler.ex | Create | ~120 |
| bezgelor_world | handler/reputation_handler.ex | Modify | +20 |
| bezgelor_world | handler/quest_handler.ex | Modify | +15 |
| bezgelor_world | handler/achievement_handler.ex | Modify | +10 |
| bezgelor_db | test/titles_test.exs | Create | ~100 |
| bezgelor_core | test/titles_test.exs | Create | ~80 |

**Total: ~750-800 LOC**

## Implementation Order

1. Database migration + AccountTitle schema
2. BezgelorDb.Titles context
3. titles.json static data + BezgelorData accessors
4. BezgelorCore.Titles unlock logic
5. Protocol packets (5 packets)
6. TitleHandler
7. Integration hooks (reputation, quest, achievement)
8. Vendor reputation gating
9. Tests

## Notes

- Title rarity is cosmetic (affects display color/effects in client)
- Clearing active title (set to 0/nil) shows no title
- Account can have many unlocked titles but only one active
- Title unlock notifications should include title name for chat display
