defmodule BezgelorDb.Repo.Migrations.CreateRealms do
  use Ecto.Migration

  def change do
    create table(:realms) do
      add :name, :string, null: false
      add :address, :string, null: false
      add :port, :integer, null: false
      add :type, :string, null: false, default: "pve"
      add :flags, :integer, default: 0
      add :online, :boolean, default: false
      add :note_text_id, :integer, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:realms, [:name])
  end
end
