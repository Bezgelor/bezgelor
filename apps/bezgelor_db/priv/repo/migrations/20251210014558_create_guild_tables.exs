defmodule BezgelorDb.Repo.Migrations.CreateGuildTables do
  use Ecto.Migration

  def change do
    # Guilds
    create table(:guilds) do
      add :name, :string, null: false
      add :tag, :string, size: 4, null: false  # 4-char abbreviation
      add :motd, :text, default: ""
      add :influence, :integer, default: 0
      add :leader_id, :integer, null: false  # Character ID of leader
      add :bank_tabs_unlocked, :integer, default: 1

      timestamps(type: :utc_datetime)
    end

    create unique_index(:guilds, [:name])
    create unique_index(:guilds, [:tag])
    create index(:guilds, [:leader_id])

    # Guild ranks
    create table(:guild_ranks) do
      add :guild_id, references(:guilds, on_delete: :delete_all), null: false
      add :rank_index, :integer, null: false  # 0 = GM, higher = lower rank
      add :name, :string, null: false
      add :permissions, :integer, default: 0  # Bitfield

      timestamps(type: :utc_datetime)
    end

    create unique_index(:guild_ranks, [:guild_id, :rank_index])

    # Guild members
    create table(:guild_members) do
      add :guild_id, references(:guilds, on_delete: :delete_all), null: false
      add :character_id, references(:characters, on_delete: :delete_all), null: false
      add :rank_index, :integer, default: 4  # Default to lowest rank
      add :officer_note, :string, default: ""
      add :public_note, :string, default: ""
      add :total_influence, :integer, default: 0

      timestamps(type: :utc_datetime)
    end

    # One guild per character
    create unique_index(:guild_members, [:character_id])
    create index(:guild_members, [:guild_id])

    # Guild bank items
    create table(:guild_bank_items) do
      add :guild_id, references(:guilds, on_delete: :delete_all), null: false
      add :tab_index, :integer, null: false
      add :slot_index, :integer, null: false
      add :item_id, :integer, null: false
      add :stack_count, :integer, default: 1
      add :item_data, :map, default: %{}
      add :depositor_id, :integer  # Character who deposited

      timestamps(type: :utc_datetime)
    end

    create unique_index(:guild_bank_items, [:guild_id, :tab_index, :slot_index])
    create index(:guild_bank_items, [:guild_id, :tab_index])
  end
end
