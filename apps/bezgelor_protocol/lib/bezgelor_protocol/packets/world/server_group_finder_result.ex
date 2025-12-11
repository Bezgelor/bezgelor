defmodule BezgelorProtocol.Packets.World.ServerGroupFinderResult do
  @moduledoc """
  Group finder result - group formed, disbanded, or error.

  ## Wire Format
  result       : uint8   (0=formed, 1=disbanded_decline, 2=disbanded_timeout, 3=disbanded_left, 4=error)
  group_id     : uint64
  instance_id  : uint32
  zone_id      : uint32  (only for result=formed)
  teleport_pos : Vector3 (only for result=formed)
  error_code   : uint8   (only for result=error)
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:result, :group_id, :instance_id, :error_code, zone_id: 0, teleport_pos: {0.0, 0.0, 0.0}]

  @impl true
  def opcode, do: 0x0B03

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_byte(result_to_int(packet.result))

    case packet.result do
      :error ->
        writer = PacketWriter.write_byte(writer, error_code_to_int(packet.error_code))
        {:ok, writer}

      _ ->
        {x, y, z} = packet.teleport_pos || {0.0, 0.0, 0.0}

        writer =
          writer
          |> PacketWriter.write_uint64(packet.group_id || 0)
          |> PacketWriter.write_uint32(packet.instance_id || 0)
          |> PacketWriter.write_uint32(packet.zone_id)
          |> PacketWriter.write_float32(x)
          |> PacketWriter.write_float32(y)
          |> PacketWriter.write_float32(z)

        {:ok, writer}
    end
  end

  defp result_to_int(:formed), do: 0
  defp result_to_int(:disbanded_decline), do: 1
  defp result_to_int(:disbanded_timeout), do: 2
  defp result_to_int(:disbanded_left), do: 3
  defp result_to_int(:error), do: 4
  defp result_to_int(_), do: 0

  defp error_code_to_int(:already_queued), do: 1
  defp error_code_to_int(:queue_error), do: 2
  defp error_code_to_int(:not_eligible), do: 3
  defp error_code_to_int(:instance_unavailable), do: 4
  defp error_code_to_int(_), do: 0
end
