defmodule BezgelorProtocol.Packets.World.ClientGroupFinderReady do
  @moduledoc """
  Response to a group finder ready check.

  ## Wire Format
  group_id : uint64
  accepted : uint8  (0=declined, 1=accepted)
  """
  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:group_id, :accepted]

  @impl true
  def opcode, do: :client_group_finder_ready

  @impl true
  def read(reader) do
    with {:ok, group_id, reader} <- PacketReader.read_uint64(reader),
         {:ok, accepted_byte, reader} <- PacketReader.read_byte(reader) do
      {:ok,
       %__MODULE__{
         group_id: group_id,
         accepted: accepted_byte == 1
       }, reader}
    end
  end
end
