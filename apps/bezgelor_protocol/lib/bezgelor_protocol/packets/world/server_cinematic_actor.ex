defmodule BezgelorProtocol.Packets.World.ServerCinematicActor do
  @moduledoc """
  Spawn an actor entity for a cinematic.

  ## Wire Format

  ```
  delay           : uint32 - delay in ms before spawning
  flags           : uint16 - actor flags
  unknown0        : uint16 - unknown
  spawn_handle    : uint32 - unique handle for this actor
  creature_type   : uint32 - creature type ID from Creature2.tbl
  movement_mode   : uint32 - movement mode
  position        : Position - initial position (x, y, z float + rotation quaternion)
  active_prop_id  : uint64 - associated prop ID (0 if none)
  socket_id       : uint32 - socket attachment point
  ```

  Opcode: 0x0228
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  @type position :: %{
          x: float(),
          y: float(),
          z: float(),
          rx: float(),
          ry: float(),
          rz: float(),
          rw: float()
        }

  @type t :: %__MODULE__{
          delay: non_neg_integer(),
          flags: non_neg_integer(),
          unknown0: non_neg_integer(),
          spawn_handle: non_neg_integer(),
          creature_type: non_neg_integer(),
          movement_mode: non_neg_integer(),
          position: position(),
          active_prop_id: non_neg_integer(),
          socket_id: non_neg_integer()
        }

  defstruct delay: 0,
            flags: 0,
            unknown0: 0,
            spawn_handle: 0,
            creature_type: 0,
            movement_mode: 0,
            position: %{x: 0.0, y: 0.0, z: 0.0, rx: 0.0, ry: 0.0, rz: 0.0, rw: 1.0},
            active_prop_id: 0,
            socket_id: 0

  @impl true
  def opcode, do: :server_cinematic_actor

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    pos = packet.position

    writer =
      writer
      |> PacketWriter.write_uint32(packet.delay)
      |> PacketWriter.write_uint16(packet.flags)
      |> PacketWriter.write_uint16(packet.unknown0)
      |> PacketWriter.write_uint32(packet.spawn_handle)
      |> PacketWriter.write_uint32(packet.creature_type)
      |> PacketWriter.write_uint32(packet.movement_mode)
      # Position
      |> PacketWriter.write_float32(pos.x)
      |> PacketWriter.write_float32(pos.y)
      |> PacketWriter.write_float32(pos.z)
      # Rotation quaternion
      |> PacketWriter.write_float32(pos.rx)
      |> PacketWriter.write_float32(pos.ry)
      |> PacketWriter.write_float32(pos.rz)
      |> PacketWriter.write_float32(pos.rw)
      |> PacketWriter.write_uint64(packet.active_prop_id)
      |> PacketWriter.write_uint32(packet.socket_id)

    {:ok, writer}
  end
end
