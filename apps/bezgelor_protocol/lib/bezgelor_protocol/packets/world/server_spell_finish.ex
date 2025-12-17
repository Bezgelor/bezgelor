defmodule BezgelorProtocol.Packets.World.ServerSpellFinish do
  @moduledoc """
  Spell cast finished notification.

  ## Overview

  Sent when a spell cast completes successfully. The spell effects
  are applied and sent separately via ServerSpellEffect.

  ## Wire Format

  ```
  caster_guid  : uint64  - Entity that cast the spell
  spell_id     : uint32  - Spell that finished
  ```
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:caster_guid, :spell_id]

  @type t :: %__MODULE__{
          caster_guid: non_neg_integer(),
          spell_id: non_neg_integer()
        }

  @impl true
  def opcode, do: :server_spell_finish

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_u64(packet.caster_guid)
      |> PacketWriter.write_u32(packet.spell_id)

    {:ok, writer}
  end

  @doc """
  Create a spell finish packet.
  """
  @spec new(non_neg_integer(), non_neg_integer()) :: t()
  def new(caster_guid, spell_id) do
    %__MODULE__{
      caster_guid: caster_guid,
      spell_id: spell_id
    }
  end
end
