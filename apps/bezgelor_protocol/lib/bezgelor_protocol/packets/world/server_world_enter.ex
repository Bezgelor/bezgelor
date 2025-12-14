defmodule BezgelorProtocol.Packets.World.ServerWorldEnter do
  @moduledoc """
  World change/entry packet (ServerChangeWorld in NexusForever).

  ## Overview

  Sent when player enters the world after character selection.
  If sent while on CharacterSelect screen, loads into the Game screen.
  If sent while Game screen is already active, reinitializes player data managers.

  ## Wire Format (from NexusForever)

  ```
  world_id   : 15 bits  - World/map ID
  position_x : float32  - X coordinate
  position_y : float32  - Y coordinate
  position_z : float32  - Z coordinate
  yaw        : float32  - Horizontal rotation
  pitch      : float32  - Vertical rotation
  ```
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [
    :world_id,
    position_x: 0.0,
    position_y: 0.0,
    position_z: 0.0,
    yaw: 0.0,
    pitch: 0.0
  ]

  @type t :: %__MODULE__{
          world_id: non_neg_integer(),
          position_x: float(),
          position_y: float(),
          position_z: float(),
          yaw: float(),
          pitch: float()
        }

  @impl true
  def opcode, do: :server_world_enter

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    # Format: world_id (15 bits), position (3 floats), yaw, pitch
    # Use write_float32_bits to maintain continuous bit stream after world_id
    writer =
      writer
      |> PacketWriter.write_bits(packet.world_id || 0, 15)
      |> PacketWriter.write_float32_bits(packet.position_x || 0.0)
      |> PacketWriter.write_float32_bits(packet.position_y || 0.0)
      |> PacketWriter.write_float32_bits(packet.position_z || 0.0)
      |> PacketWriter.write_float32_bits(packet.yaw || 0.0)
      |> PacketWriter.write_float32_bits(packet.pitch || 0.0)
      |> PacketWriter.flush_bits()

    {:ok, writer}
  end

  @doc """
  Create a world enter packet from character data.
  """
  @spec from_character(map()) :: t()
  def from_character(character) do
    %__MODULE__{
      world_id: character.world_id || 870,
      position_x: character.location_x || 0.0,
      position_y: character.location_y || 0.0,
      position_z: character.location_z || 0.0,
      yaw: character.rotation_z || 0.0,
      pitch: character.rotation_x || 0.0
    }
  end

  @doc """
  Create a world enter packet from spawn location data.

  Spawn location maps have:
  - world_id: integer
  - position: {x, y, z} tuple
  - rotation: {rx, ry, rz} tuple
  """
  @spec from_spawn(map()) :: t()
  def from_spawn(spawn) do
    {x, y, z} = spawn.position
    {_rx, _ry, rz} = spawn.rotation

    %__MODULE__{
      world_id: spawn.world_id,
      position_x: x,
      position_y: y,
      position_z: z,
      yaw: rz,
      pitch: 0.0
    }
  end
end
