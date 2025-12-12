defmodule BezgelorDb.Repo.Migrations.AddSessionKeyTimestamp do
  @moduledoc """
  Add session_key_created_at timestamp for session expiration validation.

  This enables the system to reject stale session keys, preventing
  session hijacking attacks with old keys.
  """

  use Ecto.Migration

  def change do
    alter table(:accounts) do
      add :session_key_created_at, :utc_datetime
    end

    # Create index for efficient expired session cleanup queries
    create index(:accounts, [:session_key_created_at],
      where: "session_key IS NOT NULL",
      name: :accounts_session_key_created_at_index
    )
  end
end
