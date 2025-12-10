defmodule BezgelorDb.Schema.Mail do
  @moduledoc """
  Schema for in-game mail messages.

  ## Mail Features

  - Text messages between characters
  - Item attachments (up to 12 items)
  - Currency attachments (gold)
  - Cash on Delivery (COD) - recipient pays to receive
  - System mail from NPCs/quests/events

  ## Mail States

  - `:unread` - New mail not yet opened
  - `:read` - Opened but not deleted
  - `:returned` - Mail returned to sender

  ## Expiration

  Mail expires after 30 days by default.
  Returned mail expires after 7 days.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @default_expiry_days 30
  @return_expiry_days 7

  schema "mails" do
    # Sender (nil for system mail)
    field :sender_id, :integer
    field :sender_name, :string

    # Recipient
    belongs_to :recipient, BezgelorDb.Schema.Character

    # Content
    field :subject, :string
    field :body, :string, default: ""

    # State
    field :state, Ecto.Enum, values: [:unread, :read, :returned], default: :unread

    # Currency
    field :gold_attached, :integer, default: 0
    field :cod_amount, :integer, default: 0  # Cash on delivery

    # Flags
    field :is_system_mail, :boolean, default: false
    field :has_attachments, :boolean, default: false

    # Expiration
    field :expires_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(mail, attrs) do
    default_expiry = DateTime.utc_now()
                     |> DateTime.add(@default_expiry_days * 24 * 60 * 60, :second)
                     |> DateTime.truncate(:second)

    mail
    |> cast(attrs, [:sender_id, :sender_name, :recipient_id, :subject, :body, :state,
                    :gold_attached, :cod_amount, :is_system_mail, :has_attachments, :expires_at])
    |> validate_required([:recipient_id, :subject])
    |> validate_length(:subject, min: 1, max: 100)
    |> validate_length(:body, max: 2000)
    |> validate_number(:gold_attached, greater_than_or_equal_to: 0)
    |> validate_number(:cod_amount, greater_than_or_equal_to: 0)
    |> put_default_expiry(default_expiry)
    |> foreign_key_constraint(:recipient_id)
  end

  def read_changeset(mail) do
    mail
    |> change(state: :read)
  end

  def return_changeset(mail) do
    return_expiry = DateTime.utc_now()
                    |> DateTime.add(@return_expiry_days * 24 * 60 * 60, :second)
                    |> DateTime.truncate(:second)

    mail
    |> change(state: :returned, expires_at: return_expiry)
  end

  def take_gold_changeset(mail) do
    mail
    |> change(gold_attached: 0)
  end

  def take_attachments_changeset(mail) do
    mail
    |> change(has_attachments: false)
  end

  defp put_default_expiry(changeset, default) do
    case get_field(changeset, :expires_at) do
      nil -> put_change(changeset, :expires_at, default)
      _ -> changeset
    end
  end

  def default_expiry_days, do: @default_expiry_days
  def return_expiry_days, do: @return_expiry_days
end
