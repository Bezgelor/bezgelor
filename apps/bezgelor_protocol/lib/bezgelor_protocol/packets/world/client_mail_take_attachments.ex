defmodule BezgelorProtocol.Packets.World.ClientMailTakeAttachments do
  @moduledoc """
  Take attachments from a mail.

  ## Wire Format
  mail_id       : uint32
  """
  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:mail_id]

  @impl true
  def opcode, do: :client_mail_take_attachments

  @impl true
  def read(reader) do
    with {:ok, mail_id, reader} <- PacketReader.read_uint32(reader) do
      {:ok, %__MODULE__{mail_id: mail_id}, reader}
    end
  end
end
