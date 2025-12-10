defmodule BezgelorProtocol.Packets.World.ServerAchievementList do
  @moduledoc """
  Full achievement list sent to client on login.

  ## Wire Format
  total_points : uint32
  count        : uint16
  achievements : [AchievementEntry] * count

  AchievementEntry:
    achievement_id : uint32
    progress       : uint32
    completed      : uint8 (bool)
    completed_at   : uint64 (unix timestamp, 0 if not completed)
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct total_points: 0, achievements: []

  @impl true
  def opcode, do: :server_achievement_list

  @impl true
  def write(%__MODULE__{total_points: total_points, achievements: achievements}, writer) do
    writer =
      writer
      |> PacketWriter.write_uint32(total_points)
      |> PacketWriter.write_uint16(length(achievements))

    writer =
      Enum.reduce(achievements, writer, fn ach, w ->
        completed_ts =
          case ach.completed_at do
            nil -> 0
            dt -> DateTime.to_unix(dt)
          end

        w
        |> PacketWriter.write_uint32(ach.achievement_id)
        |> PacketWriter.write_uint32(ach.progress)
        |> PacketWriter.write_byte(if(ach.completed, do: 1, else: 0))
        |> PacketWriter.write_uint64(completed_ts)
      end)

    {:ok, writer}
  end
end
