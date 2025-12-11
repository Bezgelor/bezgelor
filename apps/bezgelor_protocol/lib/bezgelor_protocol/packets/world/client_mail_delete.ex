defmodule BezgelorProtocol.Packets.World.ClientMailDelete do
  @moduledoc """
  Delete a mail.

  ## Wire Format
  mail_id       : uint32
  """
  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:mail_id]

  @impl true
  def opcode, do: :client_mail_delete

  @impl true
  def read(reader) do
    with {:ok, mail_id, reader} <- PacketReader.read_uint32(reader) do
      {:ok, %__MODULE__{mail_id: mail_id}, reader}
    end
  end
end
