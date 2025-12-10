defmodule BezgelorDb.Repo.Migrations.CreateMailTables do
  use Ecto.Migration

  def change do
    # Mail messages
    create table(:mails) do
      # Sender (nullable for system mail)
      add :sender_id, :integer
      add :sender_name, :string

      # Recipient
      add :recipient_id, references(:characters, on_delete: :delete_all), null: false

      # Content
      add :subject, :string, null: false
      add :body, :text, default: ""

      # State
      add :state, :string, default: "unread"

      # Currency
      add :gold_attached, :integer, default: 0
      add :cod_amount, :integer, default: 0  # Cash on delivery

      # Flags
      add :is_system_mail, :boolean, default: false
      add :has_attachments, :boolean, default: false

      # Expiration
      add :expires_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:mails, [:recipient_id])
    create index(:mails, [:sender_id])
    create index(:mails, [:state])
    create index(:mails, [:expires_at])

    # Mail attachments
    create table(:mail_attachments) do
      add :mail_id, references(:mails, on_delete: :delete_all), null: false
      add :slot_index, :integer, null: false
      add :item_id, :integer, null: false
      add :stack_count, :integer, default: 1
      add :item_data, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:mail_attachments, [:mail_id, :slot_index])
    create index(:mail_attachments, [:mail_id])
  end
end
