defmodule BezgelorProtocol.Packets.World.ServerIgnoreList do
  @moduledoc """
  Full ignore list sent to client.

  ## Wire Format
  count   : uint32
  ignores : [IgnoreEntry] * count

  IgnoreEntry:
    character_id : uint64
    name         : wstring
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct ignores: []

  @impl true
  def opcode, do: :server_ignore_list

  @impl true
  def write(%__MODULE__{ignores: ignores}, writer) do
    writer = PacketWriter.write_u32(writer, length(ignores))

    writer = Enum.reduce(ignores, writer, fn ignore, w ->
      w
      |> PacketWriter.write_u64(ignore.character_id)
      |> PacketWriter.write_wide_string(ignore.name)
    end)

    {:ok, writer}
  end
end
