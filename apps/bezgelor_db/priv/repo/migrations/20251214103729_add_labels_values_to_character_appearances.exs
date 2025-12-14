defmodule BezgelorDb.Repo.Migrations.AddLabelsValuesToCharacterAppearances do
  use Ecto.Migration

  def change do
    alter table(:character_appearances) do
      add :labels, {:array, :integer}, default: []
      add :values, {:array, :integer}, default: []
    end
  end
end
