defmodule BezgelorDb.Repo.Migrations.ExtendAccountsForPortal do
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      add :email_verified_at, :utc_datetime
      add :totp_secret_encrypted, :binary
      add :totp_enabled_at, :utc_datetime
      add :backup_codes_hashed, {:array, :string}
      add :discord_id, :string
      add :discord_username, :string
      add :discord_linked_at, :utc_datetime
    end

    create index(:accounts, [:discord_id])
  end
end
