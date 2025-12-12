defmodule BezgelorDb.Repo.Migrations.CreateAdminAuditLog do
  use Ecto.Migration

  def change do
    create table(:admin_audit_log) do
      add :admin_account_id, references(:accounts, on_delete: :nilify_all)
      add :action, :string, null: false
      add :target_type, :string
      add :target_id, :bigint
      add :details, :map
      add :ip_address, :inet

      timestamps(updated_at: false)
    end

    create index(:admin_audit_log, [:admin_account_id])
    create index(:admin_audit_log, [:action])
    create index(:admin_audit_log, [:inserted_at])
    create index(:admin_audit_log, [:target_type, :target_id])
  end
end
