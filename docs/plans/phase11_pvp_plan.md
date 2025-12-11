# Phase 11: PvP Implementation Plan

## Overview

WildStar's PvP system includes dueling, battlegrounds (Walatiki Temple, Halls of the Bloodsworn), rated arenas (2v2, 3v3, 5v5), and Warplots (40v40 fortress warfare). This plan breaks implementation into manageable phases.

## Sub-Phases

### Phase A: Database Schemas (Tasks 1-8)
1. `pvp_stats` - Character PvP statistics (kills, deaths, assists per bracket)
2. `pvp_rating` - Rating history per bracket (arena 2v2, 3v3, 5v5, warplot)
3. `arena_team` - Arena team roster, rating, games played
4. `arena_team_member` - Team membership with personal contribution
5. `warplot` - Warplot ownership, upgrades, war coins
6. `warplot_plug` - Installed warplot plugs/buildings
7. `battleground_queue` - Queue state for BG matchmaking
8. `pvp_season` - Season tracking, rewards, cutoffs

### Phase B: Context Modules (Tasks 9-12)
9. `BezgelorDb.PvP` - Core PvP context (stats, ratings, seasons)
10. `BezgelorDb.ArenaTeams` - Team management context
11. `BezgelorDb.Warplots` - Warplot ownership context
12. `BezgelorDb.BattlegroundQueue` - Queue management context

### Phase C: Static Data (Tasks 13-16)
13. `battlegrounds.json` - BG definitions (maps, objectives, team sizes)
14. `arenas.json` - Arena definitions (maps, team sizes, spawn points)
15. `warplot_plugs.json` - Warplot plug definitions (costs, effects)
16. ETS store integration for PvP data lookup

### Phase D: Protocol Layer (Tasks 17-28)
**Client Packets:**
17. `ClientDuelChallenge` - Challenge player to duel
18. `ClientDuelResponse` - Accept/decline duel
19. `ClientBattlegroundQueue` - Join BG queue
20. `ClientBattlegroundLeave` - Leave BG/queue
21. `ClientArenaQueue` - Join arena queue
22. `ClientArenaTeamCreate` - Create arena team
23. `ClientWarplotQueue` - Queue for warplot battle

**Server Packets:**
24. `ServerDuelRequest` - Incoming duel challenge
25. `ServerDuelStart` - Duel countdown/start
26. `ServerDuelEnd` - Duel result
27. `ServerBattlegroundStatus` - BG queue/match status
28. `ServerBattlegroundScore` - Scoreboard update
29. `ServerArenaStatus` - Arena queue/match status
30. `ServerArenaTeamInfo` - Team roster/rating
31. `ServerPvPStats` - Player PvP statistics
32. `ServerWarplotStatus` - Warplot battle status

### Phase E: Duel System (Tasks 33-38)
33. `DuelManager` GenServer - Track active duels per zone
34. Duel request/response handling
35. Duel boundaries (circular arena around start point)
36. Victory conditions (health, forfeit, boundary)
37. Duel cooldowns and restrictions
38. `duel_handler.ex` - Packet handler

### Phase F: Battleground System (Tasks 39-48)
39. `BattlegroundQueue` GenServer - Queue management
40. `BattlegroundInstance` GenServer - Match state
41. Walatiki Temple objectives (capture the mask)
42. Halls of the Bloodsworn objectives (control points)
43. Scoring and victory conditions
44. Respawn mechanics and graveyards
45. Team balancing (class/role composition)
46. Deserter debuff handling
47. Honor/conquest currency rewards
48. `battleground_handler.ex` - Packet handler

### Phase G: Arena System (Tasks 49-58)
49. `ArenaQueue` GenServer - Rated queue with MMR matching
50. `ArenaInstance` GenServer - Arena match state
51. Arena team management (create, invite, leave)
52. 2v2, 3v3, 5v5 bracket handling
53. ELO/MMR rating calculation
54. Rating gains/losses per match
55. Team rating vs personal rating
56. Arena point rewards
57. Seasonal title cutoffs
58. `arena_handler.ex` - Packet handler

### Phase H: Warplot System (Tasks 59-66)
59. `WarplotManager` GenServer - Warplot ownership
60. Warplot building/plug system
61. War coin currency
62. 40v40 queue matching
63. Warplot battle instance
64. Objective-based victory (generators, boss)
65. Warplot rewards
66. `warplot_handler.ex` - Packet handler

### Phase I: Rating & Seasons (Tasks 67-72)
67. Season start/end handling
68. Rating decay mechanics
69. Seasonal reward distribution
70. Title/mount unlocks based on rating
71. Leaderboard queries
72. `pvp_season_handler.ex` - Admin/season management

### Phase J: Integration & Testing (Tasks 73-78)
73. Duel system tests
74. Battleground flow tests
75. Arena matchmaking tests
76. Rating calculation tests
77. Season reward tests
78. Full PvP integration test

## Database Schema Details

### pvp_stats
```elixir
schema "pvp_stats" do
  belongs_to :character, Character

  field :honorable_kills, :integer, default: 0
  field :deaths, :integer, default: 0
  field :killing_blows, :integer, default: 0
  field :battlegrounds_played, :integer, default: 0
  field :battlegrounds_won, :integer, default: 0
  field :arenas_played, :integer, default: 0
  field :arenas_won, :integer, default: 0
  field :highest_arena_rating, :integer, default: 0
  field :conquest_earned_total, :integer, default: 0
  field :honor_earned_total, :integer, default: 0

  timestamps()
end
```

### pvp_rating
```elixir
schema "pvp_ratings" do
  belongs_to :character, Character

  field :bracket, :string  # "2v2", "3v3", "5v5", "rbg", "warplot"
  field :rating, :integer, default: 0
  field :season_high, :integer, default: 0
  field :games_played, :integer, default: 0
  field :games_won, :integer, default: 0
  field :win_streak, :integer, default: 0
  field :last_decay_at, :utc_datetime

  timestamps()
end
```

### arena_team
```elixir
schema "arena_teams" do
  field :name, :string
  field :bracket, :string  # "2v2", "3v3", "5v5"
  field :rating, :integer, default: 0
  field :season_high, :integer, default: 0
  field :games_played, :integer, default: 0
  field :games_won, :integer, default: 0
  field :captain_id, :integer
  field :created_at, :utc_datetime
  field :disbanded_at, :utc_datetime

  has_many :members, ArenaTeamMember

  timestamps()
end
```

## Key Implementation Notes

### Rating System (ELO-based)
- Base rating: 0 (new players/teams)
- K-factor varies by games played (higher early, stabilizes later)
- Rating gains/losses based on opponent rating difference
- Personal rating can differ from team rating
- Weekly decay for inactive high-rated players

### Battleground Matching
- Solo queue fills teams based on role/class balance
- Group queue attempts to match group sizes
- MMR-based matching for rated BGs
- Mercenary mode for faction imbalance

### Warplot Specifics
- 40v40 requires full raid groups
- Warplot plugs cost War Coins
- Plugs provide strategic advantages (turrets, guards, buffs)
- Victory by destroying enemy generator or boss kill

## File Locations

- Schemas: `apps/bezgelor_db/lib/bezgelor_db/schema/`
- Contexts: `apps/bezgelor_db/lib/bezgelor_db/`
- Packets: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/`
- Handlers: `apps/bezgelor_world/lib/bezgelor_world/handler/`
- GenServers: `apps/bezgelor_world/lib/bezgelor_world/pvp/`
- Static Data: `apps/bezgelor_data/priv/data/`
- Tests: `apps/bezgelor_world/test/`
