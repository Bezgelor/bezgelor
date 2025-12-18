defmodule BezgelorProtocol.Packets.World.ServerTitleUnlocked do
  @moduledoc """
  Notification when a new title is unlocked.

  ## Wire Format
  title_id    : uint32
  unlocked_at : uint64 (unix timestamp)
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:title_id, :unlocked_at]

  @impl true
  def opcode, do: :server_title_unlocked

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    unlocked_ts =
      case packet.unlocked_at do
        nil -> DateTime.to_unix(DateTime.utc_now())
        dt -> DateTime.to_unix(dt)
      end

    writer =
      writer
      |> PacketWriter.write_u32(packet.title_id)
      |> PacketWriter.write_u64(unlocked_ts)

    {:ok, writer}
  end
end
