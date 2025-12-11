defmodule BezgelorProtocol.Packets.World.ClientMythicKeystoneActivate do
  @moduledoc """
  Activate a keystone to start a Mythic+ run.

  ## Wire Format
  keystone_id : uint64  (the player's keystone database ID)
  """
  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:keystone_id]

  @impl true
  def opcode, do: :client_mythic_keystone_activate

  @impl true
  def read(reader) do
    with {:ok, keystone_id, reader} <- PacketReader.read_uint64(reader) do
      {:ok, %__MODULE__{keystone_id: keystone_id}, reader}
    end
  end
end
