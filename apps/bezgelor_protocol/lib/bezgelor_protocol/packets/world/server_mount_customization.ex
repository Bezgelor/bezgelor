defmodule BezgelorProtocol.Packets.World.ServerMountCustomization do
  @moduledoc """
  Mount customization update from server.

  Sent to sync mount appearance to client.

  ## Wire Format
  entity_guid : uint64         - Entity whose mount changed
  mount_id    : uint32         - Mount ID
  dye_count   : uint8          - Number of dye channels
  dyes        : uint32[count]  - Dye IDs for each channel
  flair_count : uint8          - Number of flair items
  flairs      : string[count]  - Flair item keys
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:entity_guid, :mount_id, :dyes, :flairs]

  @type t :: %__MODULE__{
          entity_guid: non_neg_integer(),
          mount_id: non_neg_integer(),
          dyes: [non_neg_integer()],
          flairs: [String.t()]
        }

  @impl true
  def opcode, do: :server_mount_customization

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    dyes = packet.dyes || []
    flairs = packet.flairs || []

    writer =
      writer
      |> PacketWriter.write_u64(packet.entity_guid)
      |> PacketWriter.write_u32(packet.mount_id)
      |> PacketWriter.write_u8(length(dyes))
      |> write_dyes(dyes)
      |> PacketWriter.write_u8(length(flairs))
      |> write_flairs(flairs)

    {:ok, writer}
  end

  defp write_dyes(writer, []), do: writer

  defp write_dyes(writer, [dye | rest]) do
    writer
    |> PacketWriter.write_u32(dye)
    |> write_dyes(rest)
  end

  defp write_flairs(writer, []), do: writer

  defp write_flairs(writer, [flair | rest]) do
    writer
    |> PacketWriter.write_wide_string(flair)
    |> write_flairs(rest)
  end
end
