defmodule BezgelorProtocol.Packets.World.ClientRedeemCode do
  @moduledoc """
  Client request to redeem a promotional or gift code.

  ## Wire Format
  code : string (length-prefixed)
  """
  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:code]

  @impl true
  def opcode, do: :client_redeem_code

  @impl true
  def read(reader) do
    {code, reader} = PacketReader.read_string(reader)

    packet = %__MODULE__{
      code: code
    }

    {:ok, packet, reader}
  end
end
