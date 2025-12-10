defmodule BezgelorProtocol.Packets.World.ServerSocialResult do
  @moduledoc """
  Result of social operation (add/remove friend/ignore).

  ## Wire Format
  result      : uint32 - Result code
  operation   : uint32 - Operation type
  target_name : wstring - Name of target player

  ## Result Codes
  0 = success
  1 = player_not_found
  2 = already_friend
  3 = list_full
  4 = cannot_add_self
  5 = not_found (for remove operations)
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:result, :operation, :target_name]

  @impl true
  def opcode, do: :server_social_result

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    result_code = result_to_int(packet.result)
    op_code = operation_to_int(packet.operation)

    writer =
      writer
      |> PacketWriter.write_uint32(result_code)
      |> PacketWriter.write_uint32(op_code)
      |> PacketWriter.write_wide_string(packet.target_name || "")

    {:ok, writer}
  end

  defp result_to_int(:success), do: 0
  defp result_to_int(:player_not_found), do: 1
  defp result_to_int(:already_friend), do: 2
  defp result_to_int(:list_full), do: 3
  defp result_to_int(:cannot_add_self), do: 4
  defp result_to_int(:not_found), do: 5
  defp result_to_int(_), do: 255

  defp operation_to_int(:add_friend), do: 0
  defp operation_to_int(:remove_friend), do: 1
  defp operation_to_int(:add_ignore), do: 2
  defp operation_to_int(:remove_ignore), do: 3
  defp operation_to_int(_), do: 0
end
