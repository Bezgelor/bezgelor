defmodule BezgelorProtocol.Packets.World.ServerTitleList do
  @moduledoc """
  Full list of player's unlocked titles.

  ## Wire Format
  active_title_id : uint32 (0 if none)
  count           : uint32
  titles          : [TitleEntry] * count

  TitleEntry:
    title_id    : uint32
    unlocked_at : uint64 (unix timestamp)
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct active_title_id: nil, titles: []

  @impl true
  def opcode, do: :server_title_list

  @impl true
  def write(%__MODULE__{active_title_id: active_id, titles: titles}, writer) do
    writer =
      writer
      |> PacketWriter.write_uint32(active_id || 0)
      |> PacketWriter.write_uint32(length(titles))

    writer =
      Enum.reduce(titles, writer, fn title, w ->
        unlocked_ts =
          case title.unlocked_at do
            nil -> 0
            dt -> DateTime.to_unix(dt)
          end

        w
        |> PacketWriter.write_uint32(title.title_id)
        |> PacketWriter.write_uint64(unlocked_ts)
      end)

    {:ok, writer}
  end
end
