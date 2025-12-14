defmodule BezgelorDb.Repo.Migrations.AddVisualsToCharacterAppearances do
  use Ecto.Migration

  def change do
    alter table(:character_appearances) do
      add :visuals, {:array, :map}, default: []
    end
  end
end
