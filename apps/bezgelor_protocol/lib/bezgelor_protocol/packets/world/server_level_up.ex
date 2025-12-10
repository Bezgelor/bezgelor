defmodule BezgelorProtocol.Packets.World.ServerLevelUp do
  @moduledoc """
  Server notification of level up.

  ## Overview

  Sent when a player levels up.
  Includes the new level and updated stats.

  ## Wire Format

  ```
  entity_guid  : uint64 - GUID of entity that leveled up
  new_level    : uint32 - New level
  max_health   : uint32 - New max health
  current_xp   : uint32 - Current XP after level up
  xp_to_level  : uint32 - XP needed for next level
  ```
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:entity_guid, :new_level, :max_health, :current_xp, :xp_to_level]

  @type t :: %__MODULE__{
          entity_guid: non_neg_integer(),
          new_level: non_neg_integer(),
          max_health: non_neg_integer(),
          current_xp: non_neg_integer(),
          xp_to_level: non_neg_integer()
        }

  @impl true
  def opcode, do: :server_level_up

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_uint64(packet.entity_guid)
      |> PacketWriter.write_uint32(packet.new_level)
      |> PacketWriter.write_uint32(packet.max_health)
      |> PacketWriter.write_uint32(packet.current_xp)
      |> PacketWriter.write_uint32(packet.xp_to_level)

    {:ok, writer}
  end
end
