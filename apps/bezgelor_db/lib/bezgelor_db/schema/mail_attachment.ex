defmodule BezgelorDb.Schema.MailAttachment do
  @moduledoc """
  Schema for mail item attachments.

  ## Attachment Limits

  Each mail can have up to 12 item attachments.
  Attachments are transferred from sender's inventory when sending.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @max_attachments 12

  schema "mail_attachments" do
    belongs_to :mail, BezgelorDb.Schema.Mail

    # Slot index (0-11)
    field :slot_index, :integer

    # Item data
    field :item_id, :integer
    field :stack_count, :integer, default: 1
    field :item_data, :map, default: %{}  # Extended item properties

    timestamps(type: :utc_datetime)
  end

  def changeset(attachment, attrs) do
    attachment
    |> cast(attrs, [:mail_id, :slot_index, :item_id, :stack_count, :item_data])
    |> validate_required([:mail_id, :slot_index, :item_id])
    |> validate_number(:slot_index, greater_than_or_equal_to: 0, less_than: @max_attachments)
    |> validate_number(:stack_count, greater_than: 0)
    |> foreign_key_constraint(:mail_id)
    |> unique_constraint([:mail_id, :slot_index], name: :mail_attachments_mail_id_slot_index_index)
  end

  def max_attachments, do: @max_attachments
end
