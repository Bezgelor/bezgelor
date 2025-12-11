defmodule BezgelorProtocol.Packets.World.ClientLootRoll do
  @moduledoc """
  Roll on a loot item (need/greed/pass).

  ## Wire Format
  loot_id   : uint64
  roll_type : uint8  (0=pass, 1=greed, 2=need)
  """
  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:loot_id, :roll_type]

  @impl true
  def opcode, do: :client_loot_roll

  @impl true
  def read(reader) do
    with {:ok, loot_id, reader} <- PacketReader.read_uint64(reader),
         {:ok, roll_byte, reader} <- PacketReader.read_byte(reader) do
      {:ok,
       %__MODULE__{
         loot_id: loot_id,
         roll_type: int_to_roll_type(roll_byte)
       }, reader}
    end
  end

  defp int_to_roll_type(0), do: :pass
  defp int_to_roll_type(1), do: :greed
  defp int_to_roll_type(2), do: :need
  defp int_to_roll_type(_), do: :pass
end
