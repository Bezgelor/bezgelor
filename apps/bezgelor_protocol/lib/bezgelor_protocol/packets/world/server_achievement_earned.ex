defmodule BezgelorProtocol.Packets.World.ServerAchievementEarned do
  @moduledoc """
  Achievement completed notification.

  ## Wire Format
  achievement_id : uint32
  points         : uint32
  completed_at   : uint64 (unix timestamp)
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:achievement_id, :points, :completed_at]

  @impl true
  def opcode, do: :server_achievement_earned

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    completed_ts =
      case packet.completed_at do
        nil -> DateTime.to_unix(DateTime.utc_now())
        dt -> DateTime.to_unix(dt)
      end

    writer =
      writer
      |> PacketWriter.write_u32(packet.achievement_id)
      |> PacketWriter.write_u32(packet.points)
      |> PacketWriter.write_u64(completed_ts)

    {:ok, writer}
  end
end
