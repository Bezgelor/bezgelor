defmodule BezgelorProtocol.Packets.World.ClientMailSend do
  @moduledoc """
  Send a mail to another character.

  ## Wire Format
  recipient_len   : uint8
  recipient       : string
  subject_len     : uint8
  subject         : string
  body_len        : uint16
  body            : string
  gold_attached   : uint32
  cod_amount      : uint32
  attachment_count: uint8
  attachments     : [AttachmentEntry] * attachment_count

  AttachmentEntry:
    bag_slot      : uint8
    slot_index    : uint8
  """
  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:recipient_name, :subject, :body, :gold_attached, :cod_amount, :attachments]

  @impl true
  def opcode, do: :client_mail_send

  @impl true
  def read(reader) do
    with {:ok, recipient_len, reader} <- PacketReader.read_byte(reader),
         {:ok, recipient_name, reader} <- PacketReader.read_bytes(reader, recipient_len),
         {:ok, subject_len, reader} <- PacketReader.read_byte(reader),
         {:ok, subject, reader} <- PacketReader.read_bytes(reader, subject_len),
         {:ok, body_len, reader} <- PacketReader.read_uint16(reader),
         {:ok, body, reader} <- PacketReader.read_bytes(reader, body_len),
         {:ok, gold_attached, reader} <- PacketReader.read_uint32(reader),
         {:ok, cod_amount, reader} <- PacketReader.read_uint32(reader),
         {:ok, attachment_count, reader} <- PacketReader.read_byte(reader),
         {:ok, attachments, reader} <- read_attachments(reader, attachment_count) do
      {:ok,
       %__MODULE__{
         recipient_name: recipient_name,
         subject: subject,
         body: body,
         gold_attached: gold_attached,
         cod_amount: cod_amount,
         attachments: attachments
       }, reader}
    end
  end

  defp read_attachments(reader, 0), do: {:ok, [], reader}

  defp read_attachments(reader, count) do
    Enum.reduce_while(1..count, {:ok, [], reader}, fn _, {:ok, attachments, r} ->
      with {:ok, bag_slot, r} <- PacketReader.read_byte(r),
           {:ok, slot_index, r} <- PacketReader.read_byte(r) do
        attachment = %{bag_slot: bag_slot, slot_index: slot_index}
        {:cont, {:ok, [attachment | attachments], r}}
      else
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, attachments, reader} -> {:ok, Enum.reverse(attachments), reader}
      error -> error
    end
  end
end
