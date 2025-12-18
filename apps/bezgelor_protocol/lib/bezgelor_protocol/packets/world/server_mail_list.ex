defmodule BezgelorProtocol.Packets.World.ServerMailList do
  @moduledoc """
  Mail inbox listing.

  ## Wire Format
  mail_count    : uint16
  mails         : [MailEntry] * mail_count

  MailEntry:
    mail_id         : uint32
    sender_len      : uint8
    sender_name     : string
    subject_len     : uint8
    subject         : string
    body_len        : uint16
    body            : string
    gold_attached   : uint32
    cod_amount      : uint32
    has_attachments : uint8 (bool)
    is_read         : uint8 (bool)
    sent_time       : uint64 (unix timestamp)
    attachment_count: uint8
    attachments     : [AttachmentEntry] * attachment_count

  AttachmentEntry:
    slot_index    : uint8
    item_id       : uint32
    stack_count   : uint16
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct mails: []

  @impl true
  def opcode, do: :server_mail_list

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer = PacketWriter.write_u16(writer, length(packet.mails))

    writer =
      Enum.reduce(packet.mails, writer, fn mail, w ->
        w
        |> PacketWriter.write_u32(mail.mail_id)
        |> PacketWriter.write_u8(byte_size(mail.sender_name))
        |> PacketWriter.write_bytes_bits(mail.sender_name)
        |> PacketWriter.write_u8(byte_size(mail.subject))
        |> PacketWriter.write_bytes_bits(mail.subject)
        |> PacketWriter.write_u16(byte_size(mail.body))
        |> PacketWriter.write_bytes_bits(mail.body)
        |> PacketWriter.write_u32(mail.gold_attached)
        |> PacketWriter.write_u32(mail.cod_amount)
        |> PacketWriter.write_u8(if(mail.has_attachments, do: 1, else: 0))
        |> PacketWriter.write_u8(if(mail.is_read, do: 1, else: 0))
        |> PacketWriter.write_u64(mail.sent_time)
        |> write_attachments(mail.attachments || [])
      end)

    {:ok, writer}
  end

  defp write_attachments(writer, attachments) do
    writer = PacketWriter.write_u8(writer, length(attachments))

    Enum.reduce(attachments, writer, fn att, w ->
      w
      |> PacketWriter.write_u8(att.slot_index)
      |> PacketWriter.write_u32(att.item_id)
      |> PacketWriter.write_u16(att.stack_count)
    end)
  end
end
