defmodule BezgelorDb.Repo.Migrations.CreateAccounts do
  use Ecto.Migration

  def change do
    create table(:accounts, primary_key: false) do
      add :id, :serial, primary_key: true
      add :email, :string, null: false
      add :salt, :string, null: false      # Hex-encoded SRP6 salt
      add :verifier, :string, null: false  # Hex-encoded SRP6 verifier
      add :game_token, :string             # Current game session token
      add :session_key, :string            # Current session key (hex)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:accounts, [:email])
    create index(:accounts, [:game_token])
  end
end
