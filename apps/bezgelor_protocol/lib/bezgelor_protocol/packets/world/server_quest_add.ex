defmodule BezgelorProtocol.Packets.World.ServerQuestAdd do
  @moduledoc """
  New quest added to log.

  ## Wire Format
  quest_id        : uint32
  objective_count : uint8
  objectives      : [ObjectiveEntry] * objective_count

  ObjectiveEntry:
    target : uint16
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:quest_id, objectives: []]

  @impl true
  def opcode, do: :server_quest_add

  @impl true
  def write(%__MODULE__{quest_id: quest_id, objectives: objectives}, writer) do
    writer =
      writer
      |> PacketWriter.write_uint32(quest_id)
      |> PacketWriter.write_byte(length(objectives))

    writer =
      Enum.reduce(objectives, writer, fn obj, w ->
        PacketWriter.write_uint16(w, obj["target"] || obj[:target] || 1)
      end)

    {:ok, writer}
  end
end
