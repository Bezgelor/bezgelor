defmodule BezgelorProtocol.Packets.World.ServerXPGain do
  @moduledoc """
  Server notification of XP gain.

  ## Overview

  Sent when a player gains experience points.
  Includes the source (kill, quest, etc.) and amount.

  ## Wire Format

  ```
  xp_amount    : uint32 - Amount of XP gained
  source_type  : uint32 - Source (0=kill, 1=quest, 2=exploration)
  source_guid  : uint64 - GUID of source entity (0 if N/A)
  current_xp   : uint32 - Current XP after gain
  xp_to_level  : uint32 - XP needed for next level
  ```

  ## Source Types

  | Type | Value | Description |
  |------|-------|-------------|
  | Kill | 0 | Creature kill |
  | Quest | 1 | Quest completion |
  | Exploration | 2 | Discovery bonus |
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  @source_kill 0
  @source_quest 1
  @source_exploration 2

  defstruct [:xp_amount, :source_type, :source_guid, :current_xp, :xp_to_level]

  @type source_type :: :kill | :quest | :exploration

  @type t :: %__MODULE__{
          xp_amount: non_neg_integer(),
          source_type: source_type(),
          source_guid: non_neg_integer(),
          current_xp: non_neg_integer(),
          xp_to_level: non_neg_integer()
        }

  @impl true
  def opcode, do: :server_xp_gain

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    source_int = source_type_to_int(packet.source_type)

    writer =
      writer
      |> PacketWriter.write_uint32(packet.xp_amount)
      |> PacketWriter.write_uint32(source_int)
      |> PacketWriter.write_uint64(packet.source_guid || 0)
      |> PacketWriter.write_uint32(packet.current_xp)
      |> PacketWriter.write_uint32(packet.xp_to_level)

    {:ok, writer}
  end

  defp source_type_to_int(:kill), do: @source_kill
  defp source_type_to_int(:quest), do: @source_quest
  defp source_type_to_int(:exploration), do: @source_exploration
  defp source_type_to_int(_), do: @source_kill
end
