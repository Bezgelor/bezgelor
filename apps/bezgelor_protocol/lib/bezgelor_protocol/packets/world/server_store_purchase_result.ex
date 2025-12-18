defmodule BezgelorProtocol.Packets.World.ServerStorePurchaseResult do
  @moduledoc """
  Server response for store purchase attempt.

  ## Wire Format
  result_code    : uint8 (0=success, 1=insufficient_funds, 2=not_found, 3=invalid_promo, 4=error)
  item_id        : uint32
  amount_paid    : uint32
  discount       : uint32
  currency_type  : uint8
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:result, :item_id, :amount_paid, :discount, :currency_type]

  @impl true
  def opcode, do: :server_store_purchase_result

  def success(item_id, amount_paid, discount, currency_type) do
    %__MODULE__{
      result: :success,
      item_id: item_id,
      amount_paid: amount_paid,
      discount: discount,
      currency_type: currency_type
    }
  end

  def error(reason, item_id \\ 0) do
    %__MODULE__{
      result: reason,
      item_id: item_id,
      amount_paid: 0,
      discount: 0,
      currency_type: :premium
    }
  end

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_u8(result_to_byte(packet.result))
      |> PacketWriter.write_u32(packet.item_id)
      |> PacketWriter.write_u32(packet.amount_paid)
      |> PacketWriter.write_u32(packet.discount)
      |> PacketWriter.write_u8(currency_to_byte(packet.currency_type))

    {:ok, writer}
  end

  defp result_to_byte(:success), do: 0
  defp result_to_byte(:insufficient_funds), do: 1
  defp result_to_byte(:not_found), do: 2
  defp result_to_byte(:invalid_promo), do: 3
  defp result_to_byte(:no_price), do: 4
  defp result_to_byte(_), do: 5

  defp currency_to_byte(:premium), do: 0
  defp currency_to_byte(:bonus), do: 1
  defp currency_to_byte(:gold), do: 2
  defp currency_to_byte(_), do: 0
end
