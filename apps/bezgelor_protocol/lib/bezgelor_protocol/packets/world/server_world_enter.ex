defmodule BezgelorProtocol.Packets.World.ServerWorldEnter do
  @moduledoc """
  World entry initialization packet.

  ## Overview

  Sent when player enters the world after character selection.
  Contains character data and initial spawn position.

  ## Wire Format

  ```
  character_id : uint64  - Character database ID
  world_id     : uint32  - World/map ID
  zone_id      : uint32  - Zone within world
  position_x   : float32 - X coordinate
  position_y   : float32 - Y coordinate
  position_z   : float32 - Z coordinate
  rotation_x   : float32 - X rotation
  rotation_y   : float32 - Y rotation
  rotation_z   : float32 - Z rotation
  time_of_day  : uint32  - Current time in game
  weather      : uint32  - Weather state
  ```
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [
    :character_id,
    :world_id,
    :zone_id,
    :position_x,
    :position_y,
    :position_z,
    rotation_x: 0.0,
    rotation_y: 0.0,
    rotation_z: 0.0,
    time_of_day: 0,
    weather: 0
  ]

  @type t :: %__MODULE__{
          character_id: non_neg_integer(),
          world_id: non_neg_integer(),
          zone_id: non_neg_integer(),
          position_x: float(),
          position_y: float(),
          position_z: float(),
          rotation_x: float(),
          rotation_y: float(),
          rotation_z: float(),
          time_of_day: non_neg_integer(),
          weather: non_neg_integer()
        }

  @impl true
  def opcode, do: :server_world_enter

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_uint64(packet.character_id)
      |> PacketWriter.write_uint32(packet.world_id)
      |> PacketWriter.write_uint32(packet.zone_id)
      |> PacketWriter.write_float32(packet.position_x)
      |> PacketWriter.write_float32(packet.position_y)
      |> PacketWriter.write_float32(packet.position_z)
      |> PacketWriter.write_float32(packet.rotation_x || 0.0)
      |> PacketWriter.write_float32(packet.rotation_y || 0.0)
      |> PacketWriter.write_float32(packet.rotation_z || 0.0)
      |> PacketWriter.write_uint32(packet.time_of_day || 0)
      |> PacketWriter.write_uint32(packet.weather || 0)

    {:ok, writer}
  end

  @doc """
  Create a world enter packet from a spawn location.
  """
  @spec from_spawn(non_neg_integer(), map()) :: t()
  def from_spawn(character_id, spawn) do
    {pos_x, pos_y, pos_z} = spawn.position
    {rot_x, rot_y, rot_z} = spawn.rotation

    %__MODULE__{
      character_id: character_id,
      world_id: spawn.world_id,
      zone_id: spawn.zone_id,
      position_x: pos_x,
      position_y: pos_y,
      position_z: pos_z,
      rotation_x: rot_x,
      rotation_y: rot_y,
      rotation_z: rot_z
    }
  end
end
