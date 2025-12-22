defmodule BezgelorDb.Repo.Migrations.CreateEconomyAlerts do
  use Ecto.Migration

  def change do
    create table(:economy_alerts) do
      add :character_id, references(:characters, on_delete: :nilify_all)
      add :alert_type, :string, null: false
      add :severity, :string, null: false
      add :description, :text, null: false
      add :data, :map
      add :acknowledged, :boolean, default: false, null: false
      add :acknowledged_by, :string
      add :acknowledged_at, :utc_datetime

      timestamps()
    end

    create index(:economy_alerts, [:alert_type])
    create index(:economy_alerts, [:severity])
    create index(:economy_alerts, [:acknowledged])
    create index(:economy_alerts, [:character_id])
    create index(:economy_alerts, [:inserted_at])
  end
end
