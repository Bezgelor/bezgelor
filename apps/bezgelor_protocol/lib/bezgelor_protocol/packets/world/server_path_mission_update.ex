defmodule BezgelorProtocol.Packets.World.ServerPathMissionUpdate do
  @moduledoc """
  Path mission progress update.

  ## Wire Format
  mission_id   : uint32
  progress_len : uint16
  progress     : [ProgressEntry] * progress_len

  ProgressEntry:
    key_len : uint8
    key     : string
    value   : int32
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:mission_id, progress: %{}]

  @impl true
  def opcode, do: :server_path_mission_update

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    progress_list = Map.to_list(packet.progress || %{})

    writer =
      writer
      |> PacketWriter.write_u32(packet.mission_id)
      |> PacketWriter.write_u16(length(progress_list))

    writer = write_progress_entries(writer, progress_list)

    {:ok, writer}
  end

  defp write_progress_entries(writer, []), do: writer

  defp write_progress_entries(writer, [{key, value} | rest]) do
    key_str = to_string(key)

    writer
    |> PacketWriter.write_u8(byte_size(key_str))
    |> PacketWriter.write_bytes_bits(key_str)
    |> PacketWriter.write_i32(value)
    |> write_progress_entries(rest)
  end
end
