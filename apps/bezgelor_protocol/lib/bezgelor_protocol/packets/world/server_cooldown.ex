defmodule BezgelorProtocol.Packets.World.ServerCooldown do
  @moduledoc """
  Spell cooldown update notification.

  ## Overview

  Sent to update the client about a spell's cooldown status.
  Used when a spell is cast or when cooldowns need to be synced.

  ## Wire Format

  ```
  spell_id     : uint32  - Spell with cooldown
  remaining    : uint32  - Milliseconds remaining
  ```
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:spell_id, :remaining]

  @type t :: %__MODULE__{
          spell_id: non_neg_integer(),
          remaining: non_neg_integer()
        }

  @impl true
  def opcode, do: :server_cooldown

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_u32(packet.spell_id)
      |> PacketWriter.write_u32(packet.remaining)

    {:ok, writer}
  end

  @doc """
  Create a cooldown packet.
  """
  @spec new(non_neg_integer(), non_neg_integer()) :: t()
  def new(spell_id, remaining) do
    %__MODULE__{
      spell_id: spell_id,
      remaining: remaining
    }
  end
end
