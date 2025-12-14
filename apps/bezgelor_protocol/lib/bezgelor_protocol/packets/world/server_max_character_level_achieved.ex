defmodule BezgelorProtocol.Packets.World.ServerMaxCharacterLevelAchieved do
  @moduledoc """
  Server packet indicating the highest character level achieved on the account.

  ## Overview

  Sent before the character list to inform the client of the maximum
  level any character has reached. Used for UI/features that unlock at
  certain account-wide level thresholds.

  ## Packet Structure

  ```
  level : uint32 - Highest character level achieved
  ```
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct level: 1

  @type t :: %__MODULE__{
          level: non_neg_integer()
        }

  @impl true
  def opcode, do: :server_max_character_level_achieved

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    writer = PacketWriter.write_uint32(writer, packet.level)
    {:ok, writer}
  end
end
