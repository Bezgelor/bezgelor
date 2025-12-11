defmodule BezgelorProtocol.Packets.World.ClientGuildSetMotd do
  @moduledoc """
  Set guild message of the day.

  ## Wire Format
  motd_len    : uint16
  motd        : string
  """
  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:motd]

  @impl true
  def opcode, do: :client_guild_set_motd

  @impl true
  def read(reader) do
    with {:ok, motd_len, reader} <- PacketReader.read_uint16(reader),
         {:ok, motd, reader} <- PacketReader.read_bytes(reader, motd_len) do
      {:ok, %__MODULE__{motd: motd}, reader}
    end
  end
end
