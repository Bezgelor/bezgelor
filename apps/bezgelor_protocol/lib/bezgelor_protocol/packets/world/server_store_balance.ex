defmodule BezgelorProtocol.Packets.World.ServerStoreBalance do
  @moduledoc """
  Server sends account currency balance.

  ## Wire Format
  premium_currency : uint32
  bonus_currency   : uint32
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:premium_currency, :bonus_currency]

  @impl true
  def opcode, do: :server_store_balance

  def new(premium, bonus) do
    %__MODULE__{
      premium_currency: premium,
      bonus_currency: bonus
    }
  end

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_uint32(packet.premium_currency)
      |> PacketWriter.write_uint32(packet.bonus_currency)

    {:ok, writer}
  end
end
