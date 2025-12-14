defmodule BezgelorProtocol.Packets.World.ServerPlayerChanged do
  @moduledoc """
  Server packet sent when a player entity becomes visible to itself.

  This packet is sent after ServerEntityCreate when the entity is the player's own character.
  It signals to the client that this entity is "the player".

  ## Wire Format (from NexusForever)

  ```
  guid     : uint32 - Player entity GUID
  unknown1 : uint32 - Always 1 in NexusForever
  ```
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct guid: 0,
            unknown1: 1

  @type t :: %__MODULE__{
          guid: non_neg_integer(),
          unknown1: non_neg_integer()
        }

  @impl true
  def opcode, do: :server_player_changed

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_bits(packet.guid, 32)
      |> PacketWriter.write_bits(packet.unknown1, 32)
      |> PacketWriter.flush_bits()

    {:ok, writer}
  end
end
