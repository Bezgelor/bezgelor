defmodule BezgelorProtocol.Packets.World.ServerMovement do
  @moduledoc """
  Server broadcasts entity movement to nearby players.

  ## Overview

  Sent by server to update other players about an entity's
  position and movement state.

  ## Wire Format

  ```
  guid            : uint64  - Entity GUID that moved
  position_x      : float32 - X coordinate
  position_y      : float32 - Y coordinate
  position_z      : float32 - Z coordinate
  rotation_x      : float32 - X rotation
  rotation_y      : float32 - Y rotation
  rotation_z      : float32 - Z rotation
  velocity_x      : float32 - X velocity
  velocity_y      : float32 - Y velocity
  velocity_z      : float32 - Z velocity
  movement_flags  : uint32  - Movement state flags
  timestamp       : uint32  - Server timestamp
  ```
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [
    :guid,
    :position_x,
    :position_y,
    :position_z,
    rotation_x: 0.0,
    rotation_y: 0.0,
    rotation_z: 0.0,
    velocity_x: 0.0,
    velocity_y: 0.0,
    velocity_z: 0.0,
    movement_flags: 0,
    timestamp: 0
  ]

  @type t :: %__MODULE__{
          guid: non_neg_integer(),
          position_x: float(),
          position_y: float(),
          position_z: float(),
          rotation_x: float(),
          rotation_y: float(),
          rotation_z: float(),
          velocity_x: float(),
          velocity_y: float(),
          velocity_z: float(),
          movement_flags: non_neg_integer(),
          timestamp: non_neg_integer()
        }

  @impl true
  def opcode, do: :server_movement

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_u64(packet.guid)
      |> PacketWriter.write_f32(packet.position_x)
      |> PacketWriter.write_f32(packet.position_y)
      |> PacketWriter.write_f32(packet.position_z)
      |> PacketWriter.write_f32(packet.rotation_x || 0.0)
      |> PacketWriter.write_f32(packet.rotation_y || 0.0)
      |> PacketWriter.write_f32(packet.rotation_z || 0.0)
      |> PacketWriter.write_f32(packet.velocity_x || 0.0)
      |> PacketWriter.write_f32(packet.velocity_y || 0.0)
      |> PacketWriter.write_f32(packet.velocity_z || 0.0)
      |> PacketWriter.write_u32(packet.movement_flags || 0)
      |> PacketWriter.write_u32(packet.timestamp || 0)

    {:ok, writer}
  end

  @doc """
  Create server movement packet from client movement.
  """
  @spec from_client_movement(non_neg_integer(), map()) :: t()
  def from_client_movement(guid, client_movement) do
    %__MODULE__{
      guid: guid,
      position_x: client_movement.position_x,
      position_y: client_movement.position_y,
      position_z: client_movement.position_z,
      rotation_x: client_movement.rotation_x,
      rotation_y: client_movement.rotation_y,
      rotation_z: client_movement.rotation_z,
      velocity_x: client_movement.velocity_x,
      velocity_y: client_movement.velocity_y,
      velocity_z: client_movement.velocity_z,
      movement_flags: client_movement.movement_flags,
      timestamp: client_movement.timestamp
    }
  end
end
