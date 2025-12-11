defmodule BezgelorProtocol.Packets.World.ServerGuildResult do
  @moduledoc """
  Guild operation result.

  ## Wire Format
  result_code   : uint8
  operation     : uint8
  [optional context based on operation]
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  # Result codes
  @result_ok 0
  @result_error_unknown 1
  @result_error_already_in_guild 2
  @result_error_not_in_guild 3
  @result_error_guild_not_found 4
  @result_error_insufficient_rank 5
  @result_error_target_not_found 6
  @result_error_target_in_guild 7
  @result_error_name_taken 8
  @result_error_invalid_name 9
  @result_error_insufficient_funds 10

  # Operations
  @op_create 1
  @op_invite 2
  @op_accept_invite 3
  @op_decline_invite 4
  @op_leave 5
  @op_kick 6
  @op_promote 7
  @op_demote 8
  @op_set_motd 9
  @op_disband 10

  defstruct [:result, :operation, :guild_id, :guild_name, :target_name]

  @impl true
  def opcode, do: :server_guild_result

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    result_code = result_to_code(packet.result)
    op_code = operation_to_code(packet.operation)

    writer =
      writer
      |> PacketWriter.write_byte(result_code)
      |> PacketWriter.write_byte(op_code)

    writer =
      case packet.operation do
        :create when packet.result == :ok ->
          writer
          |> PacketWriter.write_uint32(packet.guild_id || 0)
          |> PacketWriter.write_byte(byte_size(packet.guild_name || ""))
          |> PacketWriter.write_bytes(packet.guild_name || "")

        :invite ->
          name = packet.target_name || ""

          writer
          |> PacketWriter.write_byte(byte_size(name))
          |> PacketWriter.write_bytes(name)

        _ ->
          writer
      end

    {:ok, writer}
  end

  defp result_to_code(:ok), do: @result_ok
  defp result_to_code(:error_unknown), do: @result_error_unknown
  defp result_to_code(:already_in_guild), do: @result_error_already_in_guild
  defp result_to_code(:not_in_guild), do: @result_error_not_in_guild
  defp result_to_code(:guild_not_found), do: @result_error_guild_not_found
  defp result_to_code(:insufficient_rank), do: @result_error_insufficient_rank
  defp result_to_code(:target_not_found), do: @result_error_target_not_found
  defp result_to_code(:target_in_guild), do: @result_error_target_in_guild
  defp result_to_code(:name_taken), do: @result_error_name_taken
  defp result_to_code(:invalid_name), do: @result_error_invalid_name
  defp result_to_code(:insufficient_funds), do: @result_error_insufficient_funds
  defp result_to_code(_), do: @result_error_unknown

  defp operation_to_code(:create), do: @op_create
  defp operation_to_code(:invite), do: @op_invite
  defp operation_to_code(:accept_invite), do: @op_accept_invite
  defp operation_to_code(:decline_invite), do: @op_decline_invite
  defp operation_to_code(:leave), do: @op_leave
  defp operation_to_code(:kick), do: @op_kick
  defp operation_to_code(:promote), do: @op_promote
  defp operation_to_code(:demote), do: @op_demote
  defp operation_to_code(:set_motd), do: @op_set_motd
  defp operation_to_code(:disband), do: @op_disband
  defp operation_to_code(_), do: 0
end
