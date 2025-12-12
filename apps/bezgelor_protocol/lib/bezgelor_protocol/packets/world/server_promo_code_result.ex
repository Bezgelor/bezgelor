defmodule BezgelorProtocol.Packets.World.ServerPromoCodeResult do
  @moduledoc """
  Server response for promo code redemption.

  ## Wire Format
  result_code         : uint8 (0=success, 1=not_found, 2=expired, 3=already_redeemed, 4=error)
  code_type           : uint8 (0=discount, 1=item, 2=currency)
  granted_item_id     : uint32 (0 if not item grant)
  granted_currency    : uint32 (0 if not currency grant)
  currency_type       : uint8 (0=premium, 1=bonus)
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:result, :code_type, :granted_item_id, :granted_currency, :currency_type]

  @impl true
  def opcode, do: :server_promo_code_result

  @doc "Create success response for discount code."
  def success_discount do
    %__MODULE__{
      result: :success,
      code_type: :discount,
      granted_item_id: 0,
      granted_currency: 0,
      currency_type: :premium
    }
  end

  @doc "Create success response for item grant."
  def success_item(item_id) do
    %__MODULE__{
      result: :success,
      code_type: :item,
      granted_item_id: item_id,
      granted_currency: 0,
      currency_type: :premium
    }
  end

  @doc "Create success response for currency grant."
  def success_currency(amount, currency_type) do
    %__MODULE__{
      result: :success,
      code_type: :currency,
      granted_item_id: 0,
      granted_currency: amount,
      currency_type: currency_type
    }
  end

  @doc "Create error response."
  def error(reason) do
    %__MODULE__{
      result: reason,
      code_type: :discount,
      granted_item_id: 0,
      granted_currency: 0,
      currency_type: :premium
    }
  end

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_byte(result_to_byte(packet.result))
      |> PacketWriter.write_byte(code_type_to_byte(packet.code_type))
      |> PacketWriter.write_uint32(packet.granted_item_id || 0)
      |> PacketWriter.write_uint32(packet.granted_currency || 0)
      |> PacketWriter.write_byte(currency_to_byte(packet.currency_type))

    {:ok, writer}
  end

  defp result_to_byte(:success), do: 0
  defp result_to_byte(:not_found), do: 1
  defp result_to_byte(:expired), do: 2
  defp result_to_byte(:already_redeemed), do: 3
  defp result_to_byte(_), do: 4

  defp code_type_to_byte(:discount), do: 0
  defp code_type_to_byte(:item), do: 1
  defp code_type_to_byte(:currency), do: 2
  defp code_type_to_byte(_), do: 0

  defp currency_to_byte(:premium), do: 0
  defp currency_to_byte(:bonus), do: 1
  defp currency_to_byte(_), do: 0
end
