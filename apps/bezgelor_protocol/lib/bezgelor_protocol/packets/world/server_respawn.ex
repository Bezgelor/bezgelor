defmodule BezgelorProtocol.Packets.World.ServerRespawn do
  @moduledoc """
  Server notification of entity respawn.

  ## Overview

  Sent when an entity respawns (player or creature).
  Includes the new position and health.

  ## Wire Format

  ```
  entity_guid : uint64  - GUID of entity that respawned
  position_x  : float32 - New X coordinate
  position_y  : float32 - New Y coordinate
  position_z  : float32 - New Z coordinate
  health      : uint32  - Current health after respawn
  max_health  : uint32  - Maximum health
  ```
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:entity_guid, :position_x, :position_y, :position_z, :health, :max_health]

  @type t :: %__MODULE__{
          entity_guid: non_neg_integer(),
          position_x: float(),
          position_y: float(),
          position_z: float(),
          health: non_neg_integer(),
          max_health: non_neg_integer()
        }

  @impl true
  def opcode, do: :server_respawn

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_u64(packet.entity_guid)
      |> PacketWriter.write_f32(packet.position_x)
      |> PacketWriter.write_f32(packet.position_y)
      |> PacketWriter.write_f32(packet.position_z)
      |> PacketWriter.write_u32(packet.health)
      |> PacketWriter.write_u32(packet.max_health)

    {:ok, writer}
  end
end
