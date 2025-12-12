# Phase 11: PvP Systems F-J - Detailed Design

**Created:** 2025-12-11
**Status:** Design Document
**Prerequisite:** Phases A-E complete (schemas, contexts, packets, duel system)

## Overview

This document provides detailed design specifications for the remaining Phase 11 PvP implementation: Battleground map objectives (F), Arena instances and rating (G), Warplots (H), Rating systems and seasons (I), and comprehensive testing (J).

### Current State Assessment

| Component | Status | Notes |
|-----------|--------|-------|
| `BattlegroundQueue` | Exists | 378 LOC, faction-based FIFO matching |
| `BattlegroundInstance` | Exists | 575 LOC, generic objectives |
| `battleground_handler.ex` | Exists | 283 LOC, basic packet handling |
| `ArenaQueue` | Exists | 441 LOC, rating-window matching |
| `ArenaInstance` | **Missing** | Needs implementation |
| `arena_handler.ex` | **Missing** | Needs implementation |
| `WarplotManager` | **Missing** | Needs implementation |
| `warplot_handler.ex` | **Missing** | Needs implementation |
| Rating calculations | **Missing** | ELO formulas needed |
| Season management | **Missing** | Needs implementation |

---

## Phase F: Battleground System - Map Objectives

### F.1 Walatiki Temple (Capture the Mask)

**Game Type:** Capture the Flag variant with WildStar flavor

#### Objective Layout

```
                    ┌─────────────────────────────────────┐
                    │           WALATIKI TEMPLE           │
                    │                                     │
    ┌───────────────┼─────────────────────────────────────┼───────────────┐
    │               │                                     │               │
    │   EXILE       │                                     │   DOMINION    │
    │   BASE        │            MASK SPAWN               │   BASE        │
    │               │           (CENTER)                  │               │
    │  [Capture     │              ☆                      │  [Capture     │
    │   Point]      │                                     │   Point]      │
    │     ◉         │                                     │     ◉         │
    │               │                                     │               │
    │  Graveyard    │         Side Paths (x2)             │  Graveyard    │
    │     †         │                                     │     †         │
    │               │                                     │               │
    └───────────────┴─────────────────────────────────────┴───────────────┘
```

#### Mask Mechanics

```elixir
defmodule BezgelorWorld.PvP.Objectives.WalatikiMask do
  @moduledoc """
  Walatiki Temple mask capture mechanics.
  """

  @mask_spawn_time_ms 30_000      # 30 seconds to respawn
  @mask_carrier_debuff :moodie_mask  # Visible debuff, movement slow
  @mask_carrier_speed_reduction 0.15 # 15% slower
  @mask_drop_on_death true
  @mask_return_time_ms 10_000    # 10s on ground before return

  defstruct [
    :id,
    :position,
    :state,          # :spawned, :carried, :dropped, :returning
    :carrier_guid,
    :carrier_faction,
    :dropped_at,
    :drop_position
  ]

  @type mask_state :: :spawned | :carried | :dropped | :returning

  @doc """
  Player picks up the mask.
  """
  def pickup(mask, player_guid, player_faction) do
    case mask.state do
      :spawned ->
        {:ok, %{mask |
          state: :carried,
          carrier_guid: player_guid,
          carrier_faction: player_faction
        }}

      :dropped ->
        if mask.carrier_faction == player_faction do
          # Own faction picks up dropped mask - return it
          {:returned, %{mask | state: :returning}}
        else
          # Enemy picks up dropped mask - they carry it now
          {:ok, %{mask |
            state: :carried,
            carrier_guid: player_guid,
            carrier_faction: player_faction,
            dropped_at: nil,
            drop_position: nil
          }}
        end

      _ ->
        {:error, :mask_not_available}
    end
  end

  @doc """
  Carrier reaches their capture point - score!
  """
  def capture(mask, capture_point_faction) do
    if mask.state == :carried and mask.carrier_faction == capture_point_faction do
      {:captured, %{mask |
        state: :returning,
        carrier_guid: nil,
        carrier_faction: nil
      }}
    else
      {:error, :invalid_capture}
    end
  end

  @doc """
  Carrier dies or disconnects.
  """
  def drop(mask, position) do
    if mask.state == :carried do
      {:ok, %{mask |
        state: :dropped,
        drop_position: position,
        dropped_at: System.monotonic_time(:millisecond)
      }}
    else
      {:error, :not_carried}
    end
  end

  @doc """
  Check if dropped mask should return to center.
  """
  def check_return(mask) do
    if mask.state == :dropped do
      elapsed = System.monotonic_time(:millisecond) - mask.dropped_at
      if elapsed >= @mask_return_time_ms do
        {:return, %{mask | state: :returning}}
      else
        {:wait, mask}
      end
    else
      {:ok, mask}
    end
  end
end
```

#### Scoring System

```elixir
@walatiki_scoring %{
  mask_capture: 500,           # Capturing a mask
  mask_return: 50,             # Returning dropped mask
  killing_blow: 10,            # Kill enemy
  assist: 5,                   # Assist on kill
  healing_threshold: 100,      # Points per X healing done
  score_to_win: 3000,          # First to 3000 wins
  time_limit_ms: 1_200_000     # 20 minute max
}
```

### F.2 Halls of the Bloodsworn (Control Points)

**Game Type:** Domination / King of the Hill

#### Objective Layout

```
    ┌─────────────────────────────────────────────────────────────────┐
    │                   HALLS OF THE BLOODSWORN                       │
    │                                                                 │
    │     EXILE                                           DOMINION    │
    │     SPAWN                                           SPAWN       │
    │       ▼                                               ▼         │
    │                                                                 │
    │              ┌─────┐                   ┌─────┐                  │
    │              │  A  │                   │  C  │                  │
    │              │ ◎  │                   │ ◎  │                  │
    │              └─────┘                   └─────┘                  │
    │                                                                 │
    │                          ┌─────┐                                │
    │                          │  B  │                                │
    │                          │ ◎  │  (CENTER - worth 2x)           │
    │                          └─────┘                                │
    │                                                                 │
    │              ┌─────┐                   ┌─────┐                  │
    │              │  D  │                   │  E  │                  │
    │              │ ◎  │                   │ ◎  │                  │
    │              └─────┘                   └─────┘                  │
    │                                                                 │
    └─────────────────────────────────────────────────────────────────┘
```

#### Control Point Mechanics

```elixir
defmodule BezgelorWorld.PvP.Objectives.ControlPoint do
  @moduledoc """
  Halls of the Bloodsworn control point mechanics.
  """

  @capture_time_ms 8_000           # 8 seconds to capture
  @capture_speed_per_player 1.0    # Base capture rate
  @capture_speed_bonus 0.5         # +50% per additional player (max 3)
  @max_capture_players 3           # Diminishing returns after 3
  @contest_freeze true             # Progress freezes when contested
  @decay_rate 0.0                  # No decay when uncontested (WildStar style)

  defstruct [
    :id,
    :name,
    :position,
    :owner,              # :neutral, :exile, :dominion
    :capture_progress,   # 0.0 to 1.0
    :capturing_faction,  # Which faction is currently capturing
    :players_in_range,   # %{exile: [guids], dominion: [guids]}
    :score_multiplier    # 1.0 normal, 2.0 for center point
  ]

  @doc """
  Process capture tick (called every second).
  """
  def tick(point) do
    exile_count = length(point.players_in_range.exile)
    dominion_count = length(point.players_in_range.dominion)

    cond do
      # Contested - no progress
      exile_count > 0 and dominion_count > 0 ->
        {:contested, point}

      # Exile capturing
      exile_count > 0 ->
        progress = calculate_capture_progress(exile_count)
        update_capture(point, :exile, progress)

      # Dominion capturing
      dominion_count > 0 ->
        progress = calculate_capture_progress(dominion_count)
        update_capture(point, :dominion, progress)

      # Empty - maintain current state
      true ->
        {:unchanged, point}
    end
  end

  defp calculate_capture_progress(player_count) do
    capped = min(player_count, @max_capture_players)
    base = @capture_speed_per_player
    bonus = @capture_speed_bonus * (capped - 1)
    (base + bonus) / (@capture_time_ms / 1000)
  end

  defp update_capture(point, faction, progress_delta) do
    cond do
      # Same faction owns it - already at 100%
      point.owner == faction ->
        {:owned, point}

      # Capturing towards this faction
      point.capturing_faction == faction or point.capturing_faction == nil ->
        new_progress = min(1.0, point.capture_progress + progress_delta)
        point = %{point | capture_progress: new_progress, capturing_faction: faction}

        if new_progress >= 1.0 do
          {:captured, %{point | owner: faction, capture_progress: 1.0, capturing_faction: nil}}
        else
          {:capturing, point}
        end

      # Reversing capture - must neutralize first
      true ->
        new_progress = max(0.0, point.capture_progress - progress_delta)
        point = %{point | capture_progress: new_progress}

        if new_progress <= 0.0 do
          # Neutralized - now can capture
          {:neutralized, %{point | owner: :neutral, capturing_faction: faction}}
        else
          {:reversing, point}
        end
    end
  end
end
```

#### Scoring System

```elixir
@bloodsworn_scoring %{
  # Points per tick (every 5 seconds) per controlled point
  point_per_tick: 10,
  center_multiplier: 2.0,         # Center point (B) worth double

  # Bonus points
  capture_bonus: 100,             # Capturing a point
  defense_kill: 15,               # Kill near owned point
  assault_kill: 20,               # Kill near enemy point
  killing_blow: 10,
  assist: 5,

  # Victory conditions
  score_to_win: 1600,
  time_limit_ms: 900_000          # 15 minute max
}
```

### F.3 Respawn System

```elixir
defmodule BezgelorWorld.PvP.Respawn do
  @moduledoc """
  Battleground respawn mechanics.
  """

  @base_respawn_time_ms 30_000
  @wave_respawn_interval_ms 15_000  # Respawn in waves
  @graveyard_protection_ms 3_000   # Invuln at graveyard

  defstruct [
    :player_guid,
    :faction,
    :death_time,
    :respawn_time,
    :graveyard_id,
    :protection_expires
  ]

  @doc """
  Calculate when player will respawn (wave-based).
  """
  def calculate_respawn_time(death_time, wave_interval \\ @wave_respawn_interval_ms) do
    # Find next wave after minimum respawn time
    min_respawn = death_time + @base_respawn_time_ms
    wave_number = div(min_respawn, wave_interval) + 1
    wave_number * wave_interval
  end

  @doc """
  Select graveyard based on faction and controlled points.
  """
  def select_graveyard(faction, controlled_points, graveyards) do
    # Prefer closest graveyard that faction controls
    faction_graveyards =
      graveyards
      |> Enum.filter(fn g -> g.faction == faction or g.faction == :neutral end)
      |> Enum.sort_by(fn g -> g.priority end, :desc)

    case faction_graveyards do
      [best | _] -> best
      [] -> Enum.find(graveyards, fn g -> g.faction == faction end)  # Fallback to base
    end
  end
end
```

### F.4 Deserter Debuff

```elixir
@deserter_config %{
  enabled: true,
  duration_ms: 900_000,           # 15 minutes
  stacking: true,                 # Increases with repeat offenses
  stack_multiplier: 2.0,          # Double duration per stack
  max_duration_ms: 3_600_000,     # 1 hour max
  clear_on_completion: true,      # Removed if you finish a BG
  applies_to: [:battleground, :arena, :warplot]
}
```

---

## Phase G: Arena System

### G.1 ArenaInstance GenServer

```elixir
defmodule BezgelorWorld.PvP.ArenaInstance do
  @moduledoc """
  Manages a single arena match.

  State machine:
    PREPARATION (30s) -> ACTIVE -> ENDING (10s) -> COMPLETE
  """

  use GenServer

  require Logger

  alias BezgelorDb.{ArenaTeams, PvP}

  # Timing
  @preparation_time_ms 30_000
  @round_time_limit_ms 600_000     # 10 minute round limit (dampening starts)
  @dampening_start_ms 300_000      # 5 min: healing reduction begins
  @dampening_tick_ms 10_000        # Every 10s, dampening increases
  @dampening_per_tick 1            # 1% more healing reduction per tick
  @ending_time_ms 10_000

  @match_state_preparation :preparation
  @match_state_active :active
  @match_state_ending :ending
  @match_state_complete :complete

  defstruct [
    :match_id,
    :bracket,                      # "2v2", "3v3", "5v5"
    :arena_id,                     # Which arena map
    :match_state,
    :team1,                        # %{team_id, name, members: [...], rating}
    :team2,
    :team1_alive,                  # Count of alive players
    :team2_alive,
    :round_number,
    :dampening_percent,            # Current healing reduction
    :started_at,
    :winner,
    :rating_changes                # Calculated at end
  ]

  # Client API

  def start_instance(match_id, bracket, team1_entry, team2_entry) do
    DynamicSupervisor.start_child(
      BezgelorWorld.PvP.ArenaSupervisor,
      {__MODULE__, [match_id, bracket, team1_entry, team2_entry]}
    )
  end

  def start_link([match_id, bracket, team1_entry, team2_entry]) do
    GenServer.start_link(__MODULE__, [match_id, bracket, team1_entry, team2_entry],
      name: via_tuple(match_id)
    )
  end

  defp via_tuple(match_id) do
    {:via, Registry, {BezgelorWorld.PvP.ArenaRegistry, match_id}}
  end

  def report_death(match_id, player_guid) do
    GenServer.call(via_tuple(match_id), {:report_death, player_guid})
  end

  def get_state(match_id) do
    GenServer.call(via_tuple(match_id), :get_state)
  end

  # Server callbacks

  @impl true
  def init([match_id, bracket, team1_entry, team2_entry]) do
    Logger.info("Starting arena #{bracket} match #{match_id}")

    team_size = bracket_size(bracket)

    state = %__MODULE__{
      match_id: match_id,
      bracket: bracket,
      arena_id: select_arena(bracket),
      match_state: @match_state_preparation,
      team1: build_team_state(team1_entry),
      team2: build_team_state(team2_entry),
      team1_alive: team_size,
      team2_alive: team_size,
      round_number: 1,
      dampening_percent: 0,
      started_at: nil,
      winner: nil,
      rating_changes: nil
    }

    Process.send_after(self(), :preparation_complete, @preparation_time_ms)

    {:ok, state}
  end

  @impl true
  def handle_call({:report_death, player_guid}, _from, state) do
    if state.match_state == @match_state_active do
      state = process_death(state, player_guid)
      state = check_victory(state)
      {:reply, :ok, state}
    else
      {:reply, {:error, :match_not_active}, state}
    end
  end

  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_info(:preparation_complete, state) do
    if state.match_state == @match_state_preparation do
      Logger.info("Arena #{state.match_id} starting!")

      state = %{state |
        match_state: @match_state_active,
        started_at: DateTime.utc_now()
      }

      # Schedule dampening check
      Process.send_after(self(), :dampening_tick, @dampening_start_ms)

      # Schedule round time limit
      Process.send_after(self(), :round_time_limit, @round_time_limit_ms)

      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  def handle_info(:dampening_tick, state) do
    if state.match_state == @match_state_active do
      new_dampening = min(100, state.dampening_percent + @dampening_per_tick)

      Logger.debug("Arena #{state.match_id} dampening now at #{new_dampening}%")

      state = %{state | dampening_percent: new_dampening}

      # Continue dampening ticks
      if new_dampening < 100 do
        Process.send_after(self(), :dampening_tick, @dampening_tick_ms)
      end

      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  def handle_info(:round_time_limit, state) do
    if state.match_state == @match_state_active do
      # Determine winner by remaining health percentage
      state = end_match_by_health(state)
      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  def handle_info(:ending_complete, state) do
    if state.match_state == @match_state_ending do
      # Calculate and apply rating changes
      rating_changes = calculate_rating_changes(state)
      apply_rating_changes(rating_changes)

      state = %{state |
        match_state: @match_state_complete,
        rating_changes: rating_changes
      }

      # Cleanup after delay
      Process.send_after(self(), :cleanup, 60_000)

      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  def handle_info(:cleanup, state) do
    {:stop, :normal, state}
  end

  # Private functions

  defp bracket_size("2v2"), do: 2
  defp bracket_size("3v3"), do: 3
  defp bracket_size("5v5"), do: 5

  defp select_arena(_bracket) do
    # TODO: Select from available arena maps
    1
  end

  defp build_team_state(entry) do
    %{
      team_id: entry.team_id,
      name: entry.team_name,
      members: Enum.map(entry.members, fn guid ->
        %{guid: guid, alive: true, damage_done: 0, healing_done: 0, kills: 0}
      end),
      rating: entry.rating
    }
  end

  defp process_death(state, player_guid) do
    cond do
      player_in_team?(state.team1, player_guid) ->
        team1 = mark_dead(state.team1, player_guid)
        %{state | team1: team1, team1_alive: count_alive(team1)}

      player_in_team?(state.team2, player_guid) ->
        team2 = mark_dead(state.team2, player_guid)
        %{state | team2: team2, team2_alive: count_alive(team2)}

      true ->
        state
    end
  end

  defp player_in_team?(team, guid) do
    Enum.any?(team.members, fn m -> m.guid == guid end)
  end

  defp mark_dead(team, guid) do
    members = Enum.map(team.members, fn m ->
      if m.guid == guid, do: %{m | alive: false}, else: m
    end)
    %{team | members: members}
  end

  defp count_alive(team) do
    Enum.count(team.members, fn m -> m.alive end)
  end

  defp check_victory(state) do
    cond do
      state.team1_alive == 0 ->
        end_match(state, :team2)

      state.team2_alive == 0 ->
        end_match(state, :team1)

      true ->
        state
    end
  end

  defp end_match(state, winner) do
    Logger.info("Arena #{state.match_id} ended - Winner: #{winner}")

    state = %{state |
      match_state: @match_state_ending,
      winner: winner
    }

    Process.send_after(self(), :ending_complete, @ending_time_ms)

    state
  end

  defp end_match_by_health(state) do
    # TODO: Calculate by remaining health percentage
    # For now, team with more alive wins
    winner = if state.team1_alive > state.team2_alive, do: :team1, else: :team2
    end_match(state, winner)
  end

  defp calculate_rating_changes(state) do
    winner_team = if state.winner == :team1, do: state.team1, else: state.team2
    loser_team = if state.winner == :team1, do: state.team2, else: state.team1

    {winner_gain, loser_loss} = BezgelorWorld.PvP.Rating.calculate_elo_change(
      winner_team.rating,
      loser_team.rating
    )

    %{
      winner: %{
        team_id: winner_team.team_id,
        old_rating: winner_team.rating,
        new_rating: winner_team.rating + winner_gain,
        change: winner_gain
      },
      loser: %{
        team_id: loser_team.team_id,
        old_rating: loser_team.rating,
        new_rating: max(0, loser_team.rating - loser_loss),
        change: -loser_loss
      }
    }
  end

  defp apply_rating_changes(changes) do
    spawn(fn ->
      ArenaTeams.update_rating(changes.winner.team_id, changes.winner.change, :win)
      ArenaTeams.update_rating(changes.loser.team_id, changes.loser.change, :loss)
    end)
  end
end
```

### G.2 Arena Handler

```elixir
defmodule BezgelorWorld.Handler.ArenaHandler do
  @moduledoc """
  Handles arena-related packets.
  """

  alias BezgelorWorld.PvP.{ArenaQueue, ArenaInstance}
  alias BezgelorDb.ArenaTeams

  # Client -> Server

  def handle_arena_queue(session, %{bracket: bracket, team_id: team_id}) do
    case ArenaQueue.join_queue(team_id, bracket) do
      {:ok, estimated_wait} ->
        send_queue_status(session, bracket, estimated_wait)

      {:error, reason} ->
        send_queue_error(session, reason)
    end
  end

  def handle_arena_queue_solo(session, %{bracket: bracket}) do
    player = session.player
    rating = get_player_rating(player.character_id, bracket)

    case ArenaQueue.join_queue_solo(player.guid, player.name, bracket, rating) do
      {:ok, estimated_wait} ->
        send_queue_status(session, bracket, estimated_wait)

      {:error, reason} ->
        send_queue_error(session, reason)
    end
  end

  def handle_arena_leave_queue(session, %{team_id: team_id}) do
    ArenaQueue.leave_queue(team_id)
    send_queue_left(session)
  end

  def handle_arena_team_create(session, %{name: name, bracket: bracket}) do
    player = session.player

    case ArenaTeams.create_team(name, bracket, player.character_id) do
      {:ok, team} ->
        send_team_created(session, team)

      {:error, reason} ->
        send_team_error(session, reason)
    end
  end

  def handle_arena_team_invite(session, %{team_id: team_id, target_name: target_name}) do
    # Find target player and send invite
    # ... implementation
  end

  def handle_arena_team_leave(session, %{team_id: team_id}) do
    player = session.player

    case ArenaTeams.remove_member(team_id, player.character_id) do
      :ok ->
        send_team_left(session)

      {:error, reason} ->
        send_team_error(session, reason)
    end
  end

  # Helper functions
  defp get_player_rating(character_id, bracket) do
    case BezgelorDb.PvP.get_rating(character_id, bracket) do
      {:ok, rating} -> rating.rating
      _ -> 1500  # Default starting rating
    end
  end

  defp send_queue_status(session, bracket, wait) do
    # Send ServerArenaQueueStatus packet
  end

  defp send_queue_error(session, reason) do
    # Send error packet
  end

  defp send_queue_left(session) do
    # Send left queue confirmation
  end

  defp send_team_created(session, team) do
    # Send ServerArenaTeamRoster
  end

  defp send_team_left(session) do
    # Send left team confirmation
  end

  defp send_team_error(session, reason) do
    # Send error packet
  end
end
```

---

## Phase H: Warplot System

### H.1 Warplot Overview

Warplots are 40v40 guild-vs-guild fortress battles with customizable defenses.

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           WARPLOT BATTLEFIELD                           │
│                                                                         │
│   ┌─────────────────────────┐           ┌─────────────────────────┐    │
│   │      TEAM 1 WARPLOT     │           │      TEAM 2 WARPLOT     │    │
│   │                         │           │                         │    │
│   │  [Plug] [Plug] [Plug]   │           │  [Plug] [Plug] [Plug]   │    │
│   │         ████            │           │         ████            │    │
│   │  [Plug] BOSS  [Plug]    │           │  [Plug] BOSS  [Plug]    │    │
│   │         ████            │           │         ████            │    │
│   │  [Plug] [Plug] [Plug]   │           │  [Plug] [Plug] [Plug]   │    │
│   │                         │           │                         │    │
│   │      GENERATOR (◎)      │           │      GENERATOR (◎)      │    │
│   │                         │           │                         │    │
│   └─────────────────────────┘           └─────────────────────────┘    │
│                                                                         │
│                        CONTESTED MIDDLE ZONE                            │
│                         [Resource Nodes]                                │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### H.2 Warplot Data Structures

```elixir
defmodule BezgelorWorld.PvP.Warplot do
  @moduledoc """
  Warplot ownership and configuration.
  """

  defstruct [
    :id,
    :guild_id,
    :name,
    :war_coins,
    :plugs,                    # Map of slot_id => plug_definition
    :boss_id,                  # Selected warplot boss
    :total_wins,
    :total_losses,
    :rating
  ]
end

defmodule BezgelorWorld.PvP.WarplotPlug do
  @moduledoc """
  A warplot plug (building/defense) installed in a slot.
  """

  @plug_types %{
    turret: %{
      cost: 500,
      health: 50_000,
      damage_per_shot: 2000,
      range: 40.0,
      fire_rate_ms: 3000
    },
    guard_post: %{
      cost: 300,
      spawns: 4,
      guard_level: 50,
      respawn_time_ms: 60_000
    },
    buff_station: %{
      cost: 400,
      buff: :warplot_power,
      buff_strength: 10,        # +10% damage
      radius: 30.0
    },
    heal_station: %{
      cost: 400,
      heal_per_tick: 500,
      tick_rate_ms: 2000,
      radius: 20.0
    },
    shield_generator: %{
      cost: 600,
      shield_amount: 100_000,
      recharge_delay_ms: 30_000,
      radius: 25.0
    },
    teleporter: %{
      cost: 350,
      destination: :configurable,
      cooldown_ms: 30_000
    }
  }

  defstruct [
    :slot_id,
    :plug_type,
    :health,
    :max_health,
    :active,
    :configuration
  ]
end
```

### H.3 WarplotManager GenServer

```elixir
defmodule BezgelorWorld.PvP.WarplotManager do
  @moduledoc """
  Manages warplot ownership, upgrades, and queue.
  """

  use GenServer

  alias BezgelorDb.Warplots

  # War coin costs
  @plug_costs %{
    turret: 500,
    guard_post: 300,
    buff_station: 400,
    heal_station: 400,
    shield_generator: 600,
    teleporter: 350
  }

  @boss_costs %{
    1 => 1000,   # Basic boss
    2 => 2000,   # Advanced boss
    3 => 5000    # Elite boss
  }

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # Client API

  def get_warplot(guild_id) do
    GenServer.call(__MODULE__, {:get_warplot, guild_id})
  end

  def create_warplot(guild_id, name) do
    GenServer.call(__MODULE__, {:create_warplot, guild_id, name})
  end

  def install_plug(guild_id, slot_id, plug_type) do
    GenServer.call(__MODULE__, {:install_plug, guild_id, slot_id, plug_type})
  end

  def remove_plug(guild_id, slot_id) do
    GenServer.call(__MODULE__, {:remove_plug, guild_id, slot_id})
  end

  def set_boss(guild_id, boss_id) do
    GenServer.call(__MODULE__, {:set_boss, guild_id, boss_id})
  end

  def add_war_coins(guild_id, amount) do
    GenServer.call(__MODULE__, {:add_war_coins, guild_id, amount})
  end

  def queue_for_battle(guild_id) do
    GenServer.call(__MODULE__, {:queue_for_battle, guild_id})
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    state = %{
      warplot_queue: [],
      active_battles: MapSet.new()
    }
    {:ok, state}
  end

  @impl true
  def handle_call({:get_warplot, guild_id}, _from, state) do
    result = Warplots.get_by_guild(guild_id)
    {:reply, result, state}
  end

  def handle_call({:create_warplot, guild_id, name}, _from, state) do
    result = Warplots.create(guild_id, name)
    {:reply, result, state}
  end

  def handle_call({:install_plug, guild_id, slot_id, plug_type}, _from, state) do
    with {:ok, warplot} <- Warplots.get_by_guild(guild_id),
         {:ok, cost} <- get_plug_cost(plug_type),
         :ok <- validate_war_coins(warplot, cost),
         {:ok, updated} <- Warplots.install_plug(warplot.id, slot_id, plug_type, cost) do
      {:reply, {:ok, updated}, state}
    else
      error -> {:reply, error, state}
    end
  end

  def handle_call({:queue_for_battle, guild_id}, _from, state) do
    with {:ok, warplot} <- Warplots.get_by_guild(guild_id),
         :ok <- validate_warplot_ready(warplot) do
      entry = %{guild_id: guild_id, warplot: warplot, queued_at: System.monotonic_time(:millisecond)}
      state = %{state | warplot_queue: state.warplot_queue ++ [entry]}

      # Check if we can start a battle
      state = maybe_start_battle(state)

      {:reply, {:ok, length(state.warplot_queue)}, state}
    else
      error -> {:reply, error, state}
    end
  end

  # Private functions

  defp get_plug_cost(plug_type) do
    case Map.get(@plug_costs, plug_type) do
      nil -> {:error, :invalid_plug_type}
      cost -> {:ok, cost}
    end
  end

  defp validate_war_coins(warplot, cost) do
    if warplot.war_coins >= cost do
      :ok
    else
      {:error, :insufficient_war_coins}
    end
  end

  defp validate_warplot_ready(warplot) do
    # Must have at least a boss and some plugs
    cond do
      is_nil(warplot.boss_id) -> {:error, :no_boss_selected}
      map_size(warplot.plugs) < 3 -> {:error, :insufficient_defenses}
      true -> :ok
    end
  end

  defp maybe_start_battle(state) do
    if length(state.warplot_queue) >= 2 do
      [team1 | [team2 | remaining]] = state.warplot_queue

      # Start warplot battle instance
      match_id = start_warplot_battle(team1, team2)

      %{state |
        warplot_queue: remaining,
        active_battles: MapSet.put(state.active_battles, match_id)
      }
    else
      state
    end
  end

  defp start_warplot_battle(team1, team2) do
    match_id = generate_match_id()

    BezgelorWorld.PvP.WarplotInstance.start_instance(
      match_id,
      team1.warplot,
      team2.warplot
    )

    match_id
  end

  defp generate_match_id do
    Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end
end
```

### H.4 Victory Conditions

```elixir
@warplot_victory_conditions %{
  # Primary: Destroy enemy generator
  generator_destruction: %{
    generator_health: 500_000,
    instant_win: true
  },

  # Secondary: Kill enemy warplot boss
  boss_kill: %{
    boss_health_multiplier: 1.0,  # Based on boss tier
    points: 1000
  },

  # Tertiary: Resource control
  resource_control: %{
    nodes: 5,
    points_per_tick: 10,
    tick_interval_ms: 5000
  },

  # Time limit
  time_limit_ms: 2_400_000,  # 40 minutes

  # Score to win (if no generator destroyed)
  score_to_win: 5000
}
```

---

## Phase I: Rating & Seasons

### I.1 ELO Rating Calculations

```elixir
defmodule BezgelorWorld.PvP.Rating do
  @moduledoc """
  ELO-based rating calculations for PvP.
  """

  # Base K-factor (how much ratings change)
  @k_factor_new 40          # First 20 games
  @k_factor_established 24  # 21-50 games
  @k_factor_veteran 16      # 50+ games

  @starting_rating 1500
  @min_rating 0
  @max_rating 5000

  @doc """
  Calculate rating change after a match.
  Returns {winner_gain, loser_loss}.
  """
  @spec calculate_elo_change(integer(), integer(), keyword()) :: {integer(), integer()}
  def calculate_elo_change(winner_rating, loser_rating, opts \\ []) do
    winner_games = Keyword.get(opts, :winner_games, 50)
    loser_games = Keyword.get(opts, :loser_games, 50)

    winner_k = k_factor(winner_games)
    loser_k = k_factor(loser_games)

    # Expected score (probability of winning)
    winner_expected = expected_score(winner_rating, loser_rating)
    loser_expected = 1.0 - winner_expected

    # Actual score (1 for win, 0 for loss)
    winner_actual = 1.0
    loser_actual = 0.0

    # Rating change
    winner_change = round(winner_k * (winner_actual - winner_expected))
    loser_change = round(loser_k * (loser_actual - loser_expected))

    # Ensure minimum gain/loss
    winner_gain = max(1, winner_change)
    loser_loss = max(1, abs(loser_change))

    {winner_gain, loser_loss}
  end

  @doc """
  Calculate expected score (probability of winning).
  """
  def expected_score(player_rating, opponent_rating) do
    1.0 / (1.0 + :math.pow(10, (opponent_rating - player_rating) / 400))
  end

  @doc """
  Get K-factor based on games played.
  """
  def k_factor(games_played) do
    cond do
      games_played < 20 -> @k_factor_new
      games_played < 50 -> @k_factor_established
      true -> @k_factor_veteran
    end
  end

  @doc """
  Calculate team rating from member ratings.
  """
  def team_rating(member_ratings) do
    case member_ratings do
      [] -> @starting_rating
      ratings -> round(Enum.sum(ratings) / length(ratings))
    end
  end
end
```

### I.2 Rating Decay

```elixir
defmodule BezgelorWorld.PvP.RatingDecay do
  @moduledoc """
  Weekly rating decay for inactive high-rated players.
  """

  @decay_threshold 2000       # Only decay above this rating
  @decay_amount 50            # Points lost per week
  @decay_floor 2000           # Don't decay below this
  @inactivity_weeks 1         # Weeks without games before decay starts
  @decay_brackets ["2v2", "3v3", "5v5", "warplot"]

  @doc """
  Process weekly decay for all players.
  Called by scheduled job.
  """
  def process_weekly_decay do
    cutoff_date = DateTime.add(DateTime.utc_now(), -7 * @inactivity_weeks, :day)

    Enum.each(@decay_brackets, fn bracket ->
      BezgelorDb.PvP.get_ratings_above(bracket, @decay_threshold)
      |> Enum.filter(fn rating ->
        DateTime.compare(rating.last_game_at, cutoff_date) == :lt
      end)
      |> Enum.each(fn rating ->
        new_rating = max(@decay_floor, rating.rating - @decay_amount)

        if new_rating < rating.rating do
          BezgelorDb.PvP.update_rating(rating.id, %{
            rating: new_rating,
            decay_applied_at: DateTime.utc_now()
          })
        end
      end)
    end)
  end

  @doc """
  Calculate decay preview for a player.
  """
  def decay_preview(rating, last_game_at) do
    weeks_inactive = div(DateTime.diff(DateTime.utc_now(), last_game_at), 7 * 24 * 3600)

    if rating >= @decay_threshold and weeks_inactive >= @inactivity_weeks do
      decay_weeks = weeks_inactive - @inactivity_weeks + 1
      total_decay = decay_weeks * @decay_amount
      new_rating = max(@decay_floor, rating - total_decay)
      {:will_decay, rating - new_rating}
    else
      {:no_decay, 0}
    end
  end
end
```

### I.3 Season Management

```elixir
defmodule BezgelorWorld.PvP.Season do
  @moduledoc """
  PvP season management and rewards.
  """

  @season_duration_weeks 12

  @rating_tiers %{
    gladiator: %{min_rating: 2400, percentile: 0.5, title: "Gladiator", mount: true},
    duelist: %{min_rating: 2100, percentile: 3.0, title: "Duelist", mount: false},
    rival: %{min_rating: 1800, percentile: 10.0, title: "Rival", mount: false},
    challenger: %{min_rating: 1600, percentile: 35.0, title: "Challenger", mount: false},
    combatant: %{min_rating: 1400, percentile: nil, title: "Combatant", mount: false}
  }

  @doc """
  Start a new PvP season.
  """
  def start_season(season_number) do
    end_date = DateTime.add(DateTime.utc_now(), @season_duration_weeks * 7, :day)

    BezgelorDb.PvP.create_season(%{
      season_number: season_number,
      start_date: DateTime.utc_now(),
      end_date: end_date,
      status: :active
    })
  end

  @doc """
  End current season and distribute rewards.
  """
  def end_season(season_id) do
    # Get final standings
    standings = calculate_final_standings(season_id)

    # Distribute rewards
    Enum.each(standings, fn {character_id, tier, rating} ->
      distribute_reward(character_id, tier, rating, season_id)
    end)

    # Reset ratings for new season
    reset_ratings_for_new_season()

    # Mark season complete
    BezgelorDb.PvP.update_season(season_id, %{status: :complete})
  end

  @doc """
  Calculate tier cutoffs based on actual population.
  """
  def calculate_tier_cutoffs(season_id) do
    total_players = BezgelorDb.PvP.count_rated_players(season_id)

    Enum.map(@rating_tiers, fn {tier, config} ->
      cutoff = case config.percentile do
        nil ->
          # Fixed rating requirement only
          config.min_rating

        percentile ->
          # Calculate based on percentile
          position = round(total_players * (percentile / 100))
          rating_at_position = BezgelorDb.PvP.rating_at_position(season_id, position)
          max(config.min_rating, rating_at_position)
      end

      {tier, cutoff}
    end)
    |> Map.new()
  end

  defp calculate_final_standings(season_id) do
    cutoffs = calculate_tier_cutoffs(season_id)

    BezgelorDb.PvP.get_all_season_ratings(season_id)
    |> Enum.map(fn rating ->
      tier = determine_tier(rating.season_high, cutoffs)
      {rating.character_id, tier, rating.season_high}
    end)
  end

  defp determine_tier(rating, cutoffs) do
    cond do
      rating >= cutoffs.gladiator -> :gladiator
      rating >= cutoffs.duelist -> :duelist
      rating >= cutoffs.rival -> :rival
      rating >= cutoffs.challenger -> :challenger
      rating >= cutoffs.combatant -> :combatant
      true -> nil
    end
  end

  defp distribute_reward(character_id, tier, _rating, season_id) do
    reward = Map.get(@rating_tiers, tier)

    if reward do
      # Grant title
      BezgelorDb.Characters.grant_title(character_id, reward.title, season_id)

      # Grant mount if applicable
      if reward.mount do
        BezgelorDb.Characters.grant_mount(character_id, "gladiator_mount_#{season_id}")
      end

      # Grant conquest currency reward
      conquest_amount = tier_conquest_reward(tier)
      BezgelorDb.Characters.add_currency(character_id, :conquest, conquest_amount)
    end
  end

  defp tier_conquest_reward(:gladiator), do: 5000
  defp tier_conquest_reward(:duelist), do: 3000
  defp tier_conquest_reward(:rival), do: 2000
  defp tier_conquest_reward(:challenger), do: 1000
  defp tier_conquest_reward(:combatant), do: 500
  defp tier_conquest_reward(_), do: 0

  defp reset_ratings_for_new_season do
    # Soft reset: new_rating = (old_rating + 1500) / 2
    BezgelorDb.PvP.soft_reset_all_ratings(1500)
  end
end
```

### I.4 Leaderboard Queries

```elixir
defmodule BezgelorDb.PvP.Leaderboard do
  @moduledoc """
  Leaderboard queries for PvP rankings.
  """

  import Ecto.Query

  alias BezgelorDb.Repo
  alias BezgelorDb.Schema.{PvPRating, ArenaTeam, Character}

  @doc """
  Get top players for a bracket.
  """
  def top_players(bracket, limit \\ 100) do
    from(r in PvPRating,
      where: r.bracket == ^bracket,
      where: r.games_played >= 10,  # Minimum games
      order_by: [desc: r.rating],
      limit: ^limit,
      join: c in Character, on: c.id == r.character_id,
      select: %{
        rank: row_number() |> over(order_by: [desc: r.rating]),
        character_id: r.character_id,
        character_name: c.name,
        rating: r.rating,
        season_high: r.season_high,
        games_played: r.games_played,
        games_won: r.games_won,
        win_rate: fragment("ROUND(? * 100.0 / NULLIF(?, 0), 1)", r.games_won, r.games_played)
      }
    )
    |> Repo.all()
  end

  @doc """
  Get top arena teams for a bracket.
  """
  def top_teams(bracket, limit \\ 100) do
    from(t in ArenaTeam,
      where: t.bracket == ^bracket,
      where: t.games_played >= 10,
      where: is_nil(t.disbanded_at),
      order_by: [desc: t.rating],
      limit: ^limit,
      select: %{
        rank: row_number() |> over(order_by: [desc: t.rating]),
        team_id: t.id,
        team_name: t.name,
        rating: t.rating,
        season_high: t.season_high,
        games_played: t.games_played,
        games_won: t.games_won,
        win_rate: fragment("ROUND(? * 100.0 / NULLIF(?, 0), 1)", t.games_won, t.games_played)
      }
    )
    |> Repo.all()
  end

  @doc """
  Get player's rank in a bracket.
  """
  def player_rank(character_id, bracket) do
    subquery = from(r in PvPRating,
      where: r.bracket == ^bracket,
      where: r.games_played >= 10,
      select: %{
        character_id: r.character_id,
        rank: row_number() |> over(order_by: [desc: r.rating])
      }
    )

    from(s in subquery(subquery),
      where: s.character_id == ^character_id,
      select: s.rank
    )
    |> Repo.one()
  end

  @doc """
  Get players around a specific rank.
  """
  def players_around_rank(bracket, target_rank, range \\ 5) do
    from(r in PvPRating,
      where: r.bracket == ^bracket,
      where: r.games_played >= 10,
      order_by: [desc: r.rating],
      offset: ^max(0, target_rank - range - 1),
      limit: ^(range * 2 + 1),
      join: c in Character, on: c.id == r.character_id,
      select: %{
        rank: row_number() |> over(order_by: [desc: r.rating]) + ^max(0, target_rank - range - 1),
        character_id: r.character_id,
        character_name: c.name,
        rating: r.rating
      }
    )
    |> Repo.all()
  end
end
```

---

## Phase J: Integration & Testing

### J.1 Test Scenarios

#### Battleground Tests

```elixir
defmodule BezgelorWorld.BattlegroundTest do
  use ExUnit.Case, async: true

  alias BezgelorWorld.PvP.{BattlegroundQueue, BattlegroundInstance}
  alias BezgelorWorld.PvP.Objectives.{WalatikiMask, ControlPoint}

  describe "Walatiki Temple mask mechanics" do
    test "mask can be picked up from center" do
      mask = %WalatikiMask{id: 1, state: :spawned, position: {0, 0, 0}}
      {:ok, mask} = WalatikiMask.pickup(mask, 1001, :exile)

      assert mask.state == :carried
      assert mask.carrier_guid == 1001
      assert mask.carrier_faction == :exile
    end

    test "mask drops on carrier death" do
      mask = %WalatikiMask{id: 1, state: :carried, carrier_guid: 1001, carrier_faction: :exile}
      {:ok, mask} = WalatikiMask.drop(mask, {50.0, 0.0, 0.0})

      assert mask.state == :dropped
      assert mask.drop_position == {50.0, 0.0, 0.0}
    end

    test "friendly player returns dropped mask" do
      mask = %WalatikiMask{
        id: 1,
        state: :dropped,
        carrier_faction: :exile,
        drop_position: {50.0, 0.0, 0.0}
      }
      {:returned, mask} = WalatikiMask.pickup(mask, 1002, :exile)

      assert mask.state == :returning
    end

    test "enemy player picks up dropped mask" do
      mask = %WalatikiMask{
        id: 1,
        state: :dropped,
        carrier_faction: :exile,
        drop_position: {50.0, 0.0, 0.0}
      }
      {:ok, mask} = WalatikiMask.pickup(mask, 2001, :dominion)

      assert mask.state == :carried
      assert mask.carrier_faction == :dominion
    end

    test "mask returns to center after timeout" do
      mask = %WalatikiMask{
        id: 1,
        state: :dropped,
        dropped_at: System.monotonic_time(:millisecond) - 15_000
      }
      {:return, mask} = WalatikiMask.check_return(mask)

      assert mask.state == :returning
    end
  end

  describe "Halls of the Bloodsworn control points" do
    test "empty point maintains state" do
      point = %ControlPoint{
        id: 1,
        owner: :neutral,
        capture_progress: 0.5,
        players_in_range: %{exile: [], dominion: []}
      }
      {:unchanged, point} = ControlPoint.tick(point)

      assert point.capture_progress == 0.5
    end

    test "single player captures point" do
      point = %ControlPoint{
        id: 1,
        owner: :neutral,
        capture_progress: 0.5,
        capturing_faction: nil,
        players_in_range: %{exile: [1001], dominion: []}
      }
      {:capturing, point} = ControlPoint.tick(point)

      assert point.capturing_faction == :exile
      assert point.capture_progress > 0.5
    end

    test "contested point freezes progress" do
      point = %ControlPoint{
        id: 1,
        owner: :neutral,
        capture_progress: 0.7,
        players_in_range: %{exile: [1001], dominion: [2001]}
      }
      {:contested, point} = ControlPoint.tick(point)

      assert point.capture_progress == 0.7
    end

    test "multiple players capture faster" do
      single = %ControlPoint{
        id: 1,
        owner: :neutral,
        capture_progress: 0.0,
        capturing_faction: nil,
        players_in_range: %{exile: [1001], dominion: []}
      }
      {:capturing, single_result} = ControlPoint.tick(single)

      multi = %ControlPoint{
        id: 1,
        owner: :neutral,
        capture_progress: 0.0,
        capturing_faction: nil,
        players_in_range: %{exile: [1001, 1002, 1003], dominion: []}
      }
      {:capturing, multi_result} = ControlPoint.tick(multi)

      assert multi_result.capture_progress > single_result.capture_progress
    end
  end

  describe "battleground queue" do
    test "player joins queue successfully" do
      {:ok, wait} = BattlegroundQueue.join_queue(1001, "TestPlayer", :exile, 50, 1, 1)
      assert is_integer(wait)
    end

    test "player cannot double queue" do
      BattlegroundQueue.join_queue(1001, "TestPlayer", :exile, 50, 1, 1)
      {:error, :already_in_queue} = BattlegroundQueue.join_queue(1001, "TestPlayer", :exile, 50, 1, 1)
    end

    test "match pops when both factions have enough players" do
      # Join 4 exile players
      for i <- 1..4 do
        BattlegroundQueue.join_queue(1000 + i, "Exile#{i}", :exile, 50, 1, 1)
      end

      # Join 4 dominion players
      for i <- 1..4 do
        BattlegroundQueue.join_queue(2000 + i, "Dom#{i}", :dominion, 50, 1, 1)
      end

      # Wait for queue check
      :timer.sleep(6_000)

      # Verify players are no longer in queue (match started)
      refute BattlegroundQueue.in_queue?(1001)
    end
  end
end
```

#### Arena Tests

```elixir
defmodule BezgelorWorld.ArenaTest do
  use ExUnit.Case, async: true

  alias BezgelorWorld.PvP.{ArenaQueue, ArenaInstance, Rating}

  describe "ELO rating calculations" do
    test "higher rated player gains less for winning" do
      {high_gain, _} = Rating.calculate_elo_change(2000, 1500)
      {low_gain, _} = Rating.calculate_elo_change(1500, 2000)

      assert low_gain > high_gain
    end

    test "minimum rating change is 1" do
      {winner_gain, loser_loss} = Rating.calculate_elo_change(2500, 1000)

      assert winner_gain >= 1
      assert loser_loss >= 1
    end

    test "expected score calculation" do
      # Equal ratings = 50% expected
      assert_in_delta Rating.expected_score(1500, 1500), 0.5, 0.01

      # 400 point advantage = ~90% expected
      assert_in_delta Rating.expected_score(1900, 1500), 0.91, 0.02
    end

    test "k-factor decreases with games played" do
      assert Rating.k_factor(5) > Rating.k_factor(30)
      assert Rating.k_factor(30) > Rating.k_factor(100)
    end
  end

  describe "arena queue" do
    test "rating window expands over time" do
      {:ok, _} = ArenaQueue.join_queue_solo(1001, "Player1", "2v2", 1500)
      {:ok, status1} = ArenaQueue.get_queue_status(-1001)

      initial_window = status1.rating_window

      # Wait for window expansion
      :timer.sleep(35_000)

      {:ok, status2} = ArenaQueue.get_queue_status(-1001)

      assert status2.rating_window > initial_window
    end

    test "teams within rating window get matched" do
      ArenaQueue.join_queue_solo(1001, "Player1", "2v2", 1500)
      ArenaQueue.join_queue_solo(1002, "Player2", "2v2", 1550)

      # Wait for match
      :timer.sleep(6_000)

      # Both should be removed from queue
      refute ArenaQueue.in_queue?(-1001)
      refute ArenaQueue.in_queue?(-1002)
    end

    test "teams with large rating gap don't match immediately" do
      ArenaQueue.join_queue_solo(1001, "Player1", "2v2", 1000)
      ArenaQueue.join_queue_solo(1002, "Player2", "2v2", 2000)

      # Initial check shouldn't match them
      :timer.sleep(6_000)

      # Should still be in queue
      assert ArenaQueue.in_queue?(-1001)
      assert ArenaQueue.in_queue?(-1002)
    end
  end

  describe "arena instance" do
    test "match ends when all players on one team die" do
      # Start a match
      team1 = %{team_id: 1, team_name: "Team1", members: [1001, 1002], rating: 1500}
      team2 = %{team_id: 2, team_name: "Team2", members: [2001, 2002], rating: 1500}

      {:ok, _pid} = ArenaInstance.start_instance("test-match", "2v2", team1, team2)

      # Wait for preparation
      :timer.sleep(31_000)

      # Kill team 2
      ArenaInstance.report_death("test-match", 2001)
      ArenaInstance.report_death("test-match", 2002)

      # Check state
      state = ArenaInstance.get_state("test-match")
      assert state.winner == :team1
    end

    test "dampening increases over time" do
      team1 = %{team_id: 1, team_name: "Team1", members: [1001], rating: 1500}
      team2 = %{team_id: 2, team_name: "Team2", members: [2001], rating: 1500}

      {:ok, _pid} = ArenaInstance.start_instance("damp-test", "2v2", team1, team2)

      # Wait for preparation + dampening start
      :timer.sleep(31_000 + 300_000 + 15_000)

      state = ArenaInstance.get_state("damp-test")
      assert state.dampening_percent > 0
    end
  end
end
```

#### Rating and Season Tests

```elixir
defmodule BezgelorWorld.PvPSeasonTest do
  use ExUnit.Case, async: true

  alias BezgelorWorld.PvP.{Season, RatingDecay}

  describe "season management" do
    test "tier cutoffs respect minimum ratings" do
      # Mock population data
      cutoffs = Season.calculate_tier_cutoffs(1)

      assert cutoffs.gladiator >= 2400
      assert cutoffs.duelist >= 2100
      assert cutoffs.rival >= 1800
    end
  end

  describe "rating decay" do
    test "decay only applies above threshold" do
      {:no_decay, 0} = RatingDecay.decay_preview(1900, DateTime.utc_now())
    end

    test "decay applies after inactivity" do
      old_date = DateTime.add(DateTime.utc_now(), -14, :day)
      {:will_decay, amount} = RatingDecay.decay_preview(2200, old_date)

      assert amount > 0
    end

    test "decay doesn't go below floor" do
      very_old_date = DateTime.add(DateTime.utc_now(), -365, :day)
      {:will_decay, amount} = RatingDecay.decay_preview(2100, very_old_date)

      # Shouldn't decay below 2000
      assert 2100 - amount >= 2000
    end
  end
end
```

### J.2 Integration Test Structure

```elixir
defmodule BezgelorWorld.PvPIntegrationTest do
  use ExUnit.Case

  @moduletag :integration

  describe "full battleground flow" do
    test "queue -> match -> scoring -> rewards" do
      # 1. Queue players
      # 2. Wait for match pop
      # 3. Verify instance created
      # 4. Simulate gameplay (kills, objectives)
      # 5. Verify scoring updates
      # 6. End match
      # 7. Verify rewards distributed
      # 8. Verify stats recorded
    end
  end

  describe "full arena flow" do
    test "team creation -> queue -> match -> rating update" do
      # 1. Create arena team
      # 2. Queue for arena
      # 3. Match with opponent
      # 4. Complete match
      # 5. Verify rating changes
      # 6. Verify season high updated
    end
  end

  describe "full warplot flow" do
    test "warplot creation -> plug installation -> battle -> rewards" do
      # 1. Create warplot for guild
      # 2. Install plugs
      # 3. Queue for battle
      # 4. Match with opponent
      # 5. Complete battle
      # 6. Verify war coin rewards
      # 7. Verify rating update
    end
  end

  describe "season lifecycle" do
    test "season start -> play -> end -> rewards" do
      # 1. Start season
      # 2. Simulate matches
      # 3. End season
      # 4. Verify tier cutoffs calculated
      # 5. Verify rewards distributed
      # 6. Verify rating reset
    end
  end
end
```

---

## Implementation Tasks Summary

### Phase F: Battleground Map Objectives
| Task | Description | Est. LOC |
|------|-------------|----------|
| F.1 | WalatikiMask module | 150 |
| F.2 | ControlPoint module | 200 |
| F.3 | Integrate objectives into BattlegroundInstance | 150 |
| F.4 | Respawn system with wave spawning | 100 |
| F.5 | Graveyard selection logic | 50 |
| F.6 | Deserter debuff handling | 75 |
| F.7 | Battleground-specific scoring | 100 |

### Phase G: Arena System
| Task | Description | Est. LOC |
|------|-------------|----------|
| G.1 | ArenaInstance GenServer | 400 |
| G.2 | Arena dampening system | 50 |
| G.3 | Arena map selection | 30 |
| G.4 | arena_handler.ex | 250 |
| G.5 | Rating change calculation integration | 50 |

### Phase H: Warplot System
| Task | Description | Est. LOC |
|------|-------------|----------|
| H.1 | WarplotManager GenServer | 300 |
| H.2 | Warplot plug system | 200 |
| H.3 | WarplotInstance GenServer | 400 |
| H.4 | warplot_handler.ex | 200 |
| H.5 | War coin rewards | 50 |

### Phase I: Rating & Seasons
| Task | Description | Est. LOC |
|------|-------------|----------|
| I.1 | Rating module (ELO calculations) | 100 |
| I.2 | RatingDecay module | 75 |
| I.3 | Season module | 200 |
| I.4 | Leaderboard queries | 150 |
| I.5 | Season scheduler (start/end) | 75 |

### Phase J: Testing
| Task | Description | Est. LOC |
|------|-------------|----------|
| J.1 | Battleground objective tests | 200 |
| J.2 | Arena queue/instance tests | 200 |
| J.3 | Rating calculation tests | 100 |
| J.4 | Season/decay tests | 100 |
| J.5 | Integration tests | 300 |

---

## File Structure

```
apps/bezgelor_world/lib/bezgelor_world/
├── pvp/
│   ├── arena_instance.ex         # NEW
│   ├── arena_queue.ex            # EXISTS
│   ├── arena_supervisor.ex       # NEW
│   ├── battleground_instance.ex  # EXISTS (needs objectives integration)
│   ├── battleground_queue.ex     # EXISTS
│   ├── battleground_supervisor.ex # EXISTS
│   ├── duel_manager.ex           # EXISTS
│   ├── rating.ex                 # NEW
│   ├── rating_decay.ex           # NEW
│   ├── season.ex                 # NEW
│   ├── warplot_instance.ex       # NEW
│   ├── warplot_manager.ex        # NEW
│   └── objectives/
│       ├── walatiki_mask.ex      # NEW
│       └── control_point.ex      # NEW
├── handler/
│   ├── arena_handler.ex          # NEW
│   ├── battleground_handler.ex   # EXISTS
│   ├── duel_handler.ex           # EXISTS
│   └── warplot_handler.ex        # NEW
└── ...

apps/bezgelor_db/lib/bezgelor_db/
├── pvp.ex                        # EXISTS
└── leaderboard.ex                # NEW

apps/bezgelor_world/test/
├── arena_test.exs                # NEW
├── battleground_test.exs         # EXISTS (needs expansion)
├── pvp_season_test.exs           # NEW
└── pvp_integration_test.exs      # NEW
```

---

## Success Criteria

1. **Battlegrounds** - Walatiki and Bloodsworn objectives work correctly with proper scoring
2. **Arenas** - ArenaInstance manages full match lifecycle with dampening
3. **Warplots** - WarplotManager handles plugs, queuing, and 40v40 battles
4. **Rating** - ELO calculations produce reasonable rating changes
5. **Seasons** - Season start/end works with proper reward distribution
6. **Decay** - Inactive high-rated players decay appropriately
7. **Leaderboards** - Queries return correct rankings
8. **Tests** - Comprehensive coverage of all new functionality
