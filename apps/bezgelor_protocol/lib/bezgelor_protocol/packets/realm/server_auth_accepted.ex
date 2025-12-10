defmodule BezgelorProtocol.Packets.Realm.ServerAuthAccepted do
  @moduledoc """
  Server acceptance of game token (port 23115).

  Sent after validating client's game token from STS.
  Followed by ServerRealmMessages and ServerRealmInfo.

  ## Packet Structure

  | Field | Type | Description |
  |-------|------|-------------|
  | disconnected_for_lag | uint32 | Lag disconnect flag (usually 0) |
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct disconnected_for_lag: 0

  @type t :: %__MODULE__{
          disconnected_for_lag: non_neg_integer()
        }

  @impl true
  def opcode, do: :server_auth_accepted_realm

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    writer = PacketWriter.write_uint32(writer, packet.disconnected_for_lag)
    {:ok, writer}
  end
end
