defmodule BezgelorDb.Repo.Migrations.AddPvpTables do
  use Ecto.Migration

  def change do
    # PvP Stats - Character lifetime PvP statistics
    create table(:pvp_stats) do
      add :character_id, references(:characters, on_delete: :delete_all), null: false

      # Kill statistics
      add :honorable_kills, :integer, default: 0, null: false
      add :deaths, :integer, default: 0, null: false
      add :killing_blows, :integer, default: 0, null: false
      add :assists, :integer, default: 0, null: false
      add :damage_done, :bigint, default: 0, null: false
      add :healing_done, :bigint, default: 0, null: false

      # Battleground stats
      add :battlegrounds_played, :integer, default: 0, null: false
      add :battlegrounds_won, :integer, default: 0, null: false

      # Arena stats
      add :arenas_played, :integer, default: 0, null: false
      add :arenas_won, :integer, default: 0, null: false

      # Duel stats
      add :duels_won, :integer, default: 0, null: false
      add :duels_lost, :integer, default: 0, null: false

      # Warplot stats
      add :warplots_played, :integer, default: 0, null: false
      add :warplots_won, :integer, default: 0, null: false

      # Highest ratings (lifetime)
      add :highest_arena_2v2, :integer, default: 0, null: false
      add :highest_arena_3v3, :integer, default: 0, null: false
      add :highest_arena_5v5, :integer, default: 0, null: false
      add :highest_rbg_rating, :integer, default: 0, null: false

      # Currency totals
      add :conquest_earned_total, :integer, default: 0, null: false
      add :honor_earned_total, :integer, default: 0, null: false
      add :conquest_this_week, :integer, default: 0, null: false
      add :honor_this_week, :integer, default: 0, null: false

      timestamps()
    end

    create unique_index(:pvp_stats, [:character_id])

    # PvP Ratings - Per-bracket rating information
    create table(:pvp_ratings) do
      add :character_id, references(:characters, on_delete: :delete_all), null: false
      add :bracket, :string, null: false  # "2v2", "3v3", "5v5", "rbg", "warplot"
      add :rating, :integer, default: 0, null: false
      add :season_high, :integer, default: 0, null: false
      add :games_played, :integer, default: 0, null: false
      add :games_won, :integer, default: 0, null: false
      add :win_streak, :integer, default: 0, null: false
      add :loss_streak, :integer, default: 0, null: false
      add :mmr, :integer, default: 1500, null: false
      add :last_game_at, :utc_datetime
      add :last_decay_at, :utc_datetime

      timestamps()
    end

    create unique_index(:pvp_ratings, [:character_id, :bracket])
    create index(:pvp_ratings, [:bracket, :rating])

    # Arena Teams
    create table(:arena_teams) do
      add :name, :string, null: false
      add :bracket, :string, null: false  # "2v2", "3v3", "5v5"
      add :rating, :integer, default: 0, null: false
      add :season_high, :integer, default: 0, null: false
      add :games_played, :integer, default: 0, null: false
      add :games_won, :integer, default: 0, null: false
      add :captain_id, :integer, null: false
      add :faction_id, :integer, null: false
      add :created_at, :utc_datetime, null: false
      add :disbanded_at, :utc_datetime

      timestamps()
    end

    create unique_index(:arena_teams, [:name])
    create index(:arena_teams, [:bracket, :rating])
    create index(:arena_teams, [:faction_id])

    # Arena Team Members
    create table(:arena_team_members) do
      add :team_id, references(:arena_teams, on_delete: :delete_all), null: false
      add :character_id, references(:characters, on_delete: :delete_all), null: false
      add :personal_rating, :integer, default: 0, null: false
      add :games_played, :integer, default: 0, null: false
      add :games_won, :integer, default: 0, null: false
      add :season_games, :integer, default: 0, null: false
      add :season_wins, :integer, default: 0, null: false
      add :joined_at, :utc_datetime, null: false
      add :role, :string, default: "member", null: false

      timestamps()
    end

    create unique_index(:arena_team_members, [:team_id, :character_id])
    create index(:arena_team_members, [:character_id])

    # Warplots
    create table(:warplots) do
      add :guild_id, references(:guilds, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :war_coins, :integer, default: 0, null: false
      add :rating, :integer, default: 0, null: false
      add :season_high, :integer, default: 0, null: false
      add :battles_played, :integer, default: 0, null: false
      add :battles_won, :integer, default: 0, null: false
      add :energy, :integer, default: 500, null: false
      add :max_energy, :integer, default: 1000, null: false
      add :layout_id, :integer, default: 1, null: false
      add :created_at, :utc_datetime, null: false

      timestamps()
    end

    create unique_index(:warplots, [:guild_id])
    create index(:warplots, [:rating])

    # Warplot Plugs
    create table(:warplot_plugs) do
      add :warplot_id, references(:warplots, on_delete: :delete_all), null: false
      add :plug_id, :integer, null: false
      add :socket_id, :integer, null: false
      add :tier, :integer, default: 1, null: false
      add :health_percent, :integer, default: 100, null: false
      add :installed_at, :utc_datetime, null: false

      timestamps()
    end

    create unique_index(:warplot_plugs, [:warplot_id, :socket_id])

    # Battleground Queue
    create table(:battleground_queue) do
      add :character_id, references(:characters, on_delete: :delete_all), null: false
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :queue_type, :string, null: false  # "random", "specific", "rated"
      add :battleground_id, :integer
      add :is_rated, :boolean, default: false, null: false
      add :group_id, :string
      add :group_size, :integer, default: 1, null: false
      add :role, :string, default: "any", null: false
      add :mmr, :integer, default: 1500, null: false
      add :queued_at, :utc_datetime, null: false
      add :estimated_wait_seconds, :integer

      timestamps()
    end

    create unique_index(:battleground_queue, [:character_id])
    create index(:battleground_queue, [:queue_type, :queued_at])
    create index(:battleground_queue, [:group_id])

    # PvP Seasons
    create table(:pvp_seasons) do
      add :season_number, :integer, null: false
      add :name, :string, null: false
      add :starts_at, :utc_datetime, null: false
      add :ends_at, :utc_datetime, null: false
      add :is_active, :boolean, default: false, null: false

      # Rating cutoffs
      add :gladiator_cutoff, :integer, default: 2400, null: false
      add :duelist_cutoff, :integer, default: 2100, null: false
      add :rival_cutoff, :integer, default: 1800, null: false
      add :challenger_cutoff, :integer, default: 1500, null: false

      # Reward IDs
      add :gladiator_title_id, :integer
      add :gladiator_mount_id, :integer
      add :duelist_title_id, :integer
      add :rival_title_id, :integer
      add :challenger_title_id, :integer

      # Weekly caps
      add :conquest_cap, :integer, default: 1800, null: false

      timestamps()
    end

    create unique_index(:pvp_seasons, [:season_number])
    create index(:pvp_seasons, [:is_active])
  end
end
