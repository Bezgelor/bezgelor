defmodule BezgelorProtocol.Packets.World.ServerResurrect do
  @moduledoc """
  Server confirmation of resurrection.

  ## Overview

  Sent to confirm a player has been resurrected, either from a spell
  or by respawning at their bindpoint.

  ## Wire Format

  ```
  resurrect_type : uint8 - Type of resurrection (0=spell, 1=bindpoint, 2=soulstone)
  zone_id        : uint32 - Zone to resurrect in
  position_x     : float32 - X coordinate
  position_y     : float32 - Y coordinate
  position_z     : float32 - Z coordinate
  health_percent : float32 - Health percentage restored (0-100)
  ```

  ## Resurrect Types

  - 0 = Spell resurrection (at death location)
  - 1 = Bindpoint respawn (at graveyard/bindstone)
  - 2 = Soulstone (self-resurrect consumable)
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:resurrect_type, :zone_id, :position_x, :position_y, :position_z, :health_percent]

  @type resurrect_type :: :spell | :bindpoint | :soulstone
  @type t :: %__MODULE__{
          resurrect_type: non_neg_integer(),
          zone_id: non_neg_integer(),
          position_x: float(),
          position_y: float(),
          position_z: float(),
          health_percent: float()
        }

  @doc """
  Create a new ServerResurrect packet.

  ## Parameters

  - `type` - Resurrection type atom (:spell, :bindpoint, :soulstone)
  - `zone_id` - Zone to resurrect in
  - `position` - Position tuple {x, y, z}
  - `health_percent` - Health percentage to restore (0.0 to 100.0)
  """
  @spec new(resurrect_type(), non_neg_integer(), {float(), float(), float()}, float()) :: t()
  def new(type, zone_id, {x, y, z}, health_percent) do
    type_int =
      case type do
        :spell -> 0
        :bindpoint -> 1
        :soulstone -> 2
        int when is_integer(int) -> int
      end

    %__MODULE__{
      resurrect_type: type_int,
      zone_id: zone_id,
      position_x: x,
      position_y: y,
      position_z: z,
      health_percent: health_percent
    }
  end

  @impl true
  def opcode, do: :server_resurrect

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_u8(packet.resurrect_type)
      |> PacketWriter.write_u32(packet.zone_id)
      |> PacketWriter.write_f32(packet.position_x)
      |> PacketWriter.write_f32(packet.position_y)
      |> PacketWriter.write_f32(packet.position_z)
      |> PacketWriter.write_f32(packet.health_percent)

    {:ok, writer}
  end
end
