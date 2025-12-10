defmodule BezgelorProtocol.Packets.World.ServerPathData do
  @moduledoc """
  Full path data sent on login.

  ## Wire Format
  path_type     : uint8 (0=Soldier, 1=Settler, 2=Scientist, 3=Explorer)
  path_level    : uint8
  path_xp       : uint32
  ability_count : uint8
  abilities     : [uint32] * ability_count
  mission_count : uint16
  missions      : [MissionEntry] * mission_count

  MissionEntry:
    mission_id   : uint32
    state        : uint8 (0=active, 1=completed, 2=failed)
    progress_len : uint16
    progress     : [ProgressEntry] * progress_len

  ProgressEntry:
    key_len : uint8
    key     : string (key_len bytes)
    value   : int32
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct path_type: 0,
            path_level: 1,
            path_xp: 0,
            unlocked_abilities: [],
            missions: []

  @impl true
  def opcode, do: :server_path_data

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_byte(packet.path_type)
      |> PacketWriter.write_byte(packet.path_level)
      |> PacketWriter.write_uint32(packet.path_xp)
      |> PacketWriter.write_byte(length(packet.unlocked_abilities))

    writer =
      Enum.reduce(packet.unlocked_abilities, writer, fn ability_id, w ->
        PacketWriter.write_uint32(w, ability_id)
      end)

    writer = PacketWriter.write_uint16(writer, length(packet.missions))

    writer =
      Enum.reduce(packet.missions, writer, fn mission, w ->
        state_byte =
          case mission.state do
            :active -> 0
            :completed -> 1
            :failed -> 2
          end

        progress_list = Map.to_list(mission.progress || %{})

        w
        |> PacketWriter.write_uint32(mission.mission_id)
        |> PacketWriter.write_byte(state_byte)
        |> PacketWriter.write_uint16(length(progress_list))
        |> write_progress_entries(progress_list)
      end)

    {:ok, writer}
  end

  defp write_progress_entries(writer, []), do: writer

  defp write_progress_entries(writer, [{key, value} | rest]) do
    key_str = to_string(key)

    writer
    |> PacketWriter.write_byte(byte_size(key_str))
    |> PacketWriter.write_bytes(key_str)
    |> PacketWriter.write_int32(value)
    |> write_progress_entries(rest)
  end
end
