defmodule BezgelorProtocol.Packets.World.ServerNodeSpawn do
  @moduledoc """
  Gathering node spawned in the world.

  ## Wire Format
  node_guid     : uint64
  node_type_id  : uint32
  position_x    : float32
  position_y    : float32
  position_z    : float32
  is_available  : uint8   - 1 = available, 0 = depleted/respawning
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:node_guid, :node_type_id, :position, :is_available]

  @type t :: %__MODULE__{
          node_guid: non_neg_integer(),
          node_type_id: non_neg_integer(),
          position: {float(), float(), float()},
          is_available: boolean()
        }

  @impl true
  def opcode, do: :server_node_spawn

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    {x, y, z} = packet.position

    writer =
      writer
      |> PacketWriter.write_u64(packet.node_guid)
      |> PacketWriter.write_u32(packet.node_type_id)
      |> PacketWriter.write_f32(x)
      |> PacketWriter.write_f32(y)
      |> PacketWriter.write_f32(z)
      |> PacketWriter.write_u8(if(packet.is_available, do: 1, else: 0))

    {:ok, writer}
  end
end
