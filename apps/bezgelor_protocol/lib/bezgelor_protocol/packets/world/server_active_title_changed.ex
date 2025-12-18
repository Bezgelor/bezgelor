defmodule BezgelorProtocol.Packets.World.ServerActiveTitleChanged do
  @moduledoc """
  Confirmation of active title change.

  ## Wire Format
  title_id : uint32 (0 if cleared)
  success  : uint8 (1 = success, 0 = failure)
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:title_id, :success]

  @impl true
  def opcode, do: :server_active_title_changed

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_u32(packet.title_id || 0)
      |> PacketWriter.write_u8(if(packet.success, do: 1, else: 0))

    {:ok, writer}
  end
end
