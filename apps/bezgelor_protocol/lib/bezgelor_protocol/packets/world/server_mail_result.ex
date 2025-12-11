defmodule BezgelorProtocol.Packets.World.ServerMailResult do
  @moduledoc """
  Mail operation result.

  ## Wire Format
  result_code   : uint8
  operation     : uint8
  mail_id       : uint32 (optional, for send success)
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  # Result codes
  @result_ok 0
  @result_error_unknown 1
  @result_error_recipient_not_found 2
  @result_error_inbox_full 3
  @result_error_not_found 4
  @result_error_not_owner 5
  @result_error_has_attachments 6
  @result_error_has_gold 7
  @result_error_cod_required 8
  @result_error_cannot_return 9
  @result_error_insufficient_funds 10

  # Operations
  @op_send 1
  @op_read 2
  @op_take_attachments 3
  @op_take_gold 4
  @op_delete 5
  @op_return 6

  defstruct [:result, :operation, :mail_id]

  @impl true
  def opcode, do: :server_mail_result

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    result_code = result_to_code(packet.result)
    op_code = operation_to_code(packet.operation)

    writer =
      writer
      |> PacketWriter.write_byte(result_code)
      |> PacketWriter.write_byte(op_code)
      |> PacketWriter.write_uint32(packet.mail_id || 0)

    {:ok, writer}
  end

  defp result_to_code(:ok), do: @result_ok
  defp result_to_code(:error_unknown), do: @result_error_unknown
  defp result_to_code(:recipient_not_found), do: @result_error_recipient_not_found
  defp result_to_code(:inbox_full), do: @result_error_inbox_full
  defp result_to_code(:not_found), do: @result_error_not_found
  defp result_to_code(:not_owner), do: @result_error_not_owner
  defp result_to_code(:has_attachments), do: @result_error_has_attachments
  defp result_to_code(:has_gold), do: @result_error_has_gold
  defp result_to_code(:cod_required), do: @result_error_cod_required
  defp result_to_code(:cannot_return), do: @result_error_cannot_return
  defp result_to_code(:insufficient_funds), do: @result_error_insufficient_funds
  defp result_to_code(_), do: @result_error_unknown

  defp operation_to_code(:send), do: @op_send
  defp operation_to_code(:read), do: @op_read
  defp operation_to_code(:take_attachments), do: @op_take_attachments
  defp operation_to_code(:take_gold), do: @op_take_gold
  defp operation_to_code(:delete), do: @op_delete
  defp operation_to_code(:return), do: @op_return
  defp operation_to_code(_), do: 0
end
