defmodule BezgelorProtocol.Packets.World.ClientStoreGetDailyDeals do
  @moduledoc """
  Client request for today's daily deals.

  ## Wire Format
  (empty packet)
  """
  @behaviour BezgelorProtocol.Packet.Readable

  defstruct []

  @impl true
  def opcode, do: :client_store_get_daily_deals

  @impl true
  def read(reader) do
    {:ok, %__MODULE__{}, reader}
  end
end
