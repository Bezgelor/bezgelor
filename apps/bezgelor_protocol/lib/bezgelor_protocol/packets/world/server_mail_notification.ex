defmodule BezgelorProtocol.Packets.World.ServerMailNotification do
  @moduledoc """
  New mail notification.

  ## Wire Format
  unread_count  : uint16
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct unread_count: 0

  @impl true
  def opcode, do: :server_mail_notification

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer = PacketWriter.write_uint16(writer, packet.unread_count)
    {:ok, writer}
  end
end
