defmodule BezgelorProtocol.Packets.World.ServerSpellStart do
  @moduledoc """
  Spell cast started notification.

  ## Overview

  Sent when a spell cast begins. Used to show the cast bar on clients.
  Instant spells (cast_time = 0) skip this and go directly to finish.

  ## Wire Format

  ```
  caster_guid  : uint64  - Entity casting the spell
  spell_id     : uint32  - Spell being cast
  cast_time    : uint32  - Duration in milliseconds
  target_guid  : uint64  - Target entity (0 for self/ground)
  ```
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:caster_guid, :spell_id, :cast_time, :target_guid]

  @type t :: %__MODULE__{
          caster_guid: non_neg_integer(),
          spell_id: non_neg_integer(),
          cast_time: non_neg_integer(),
          target_guid: non_neg_integer()
        }

  @impl true
  def opcode, do: :server_spell_start

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_uint64(packet.caster_guid)
      |> PacketWriter.write_uint32(packet.spell_id)
      |> PacketWriter.write_uint32(packet.cast_time)
      |> PacketWriter.write_uint64(packet.target_guid || 0)

    {:ok, writer}
  end

  @doc """
  Create a spell start packet.
  """
  @spec new(non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer() | nil) ::
          t()
  def new(caster_guid, spell_id, cast_time, target_guid \\ nil) do
    %__MODULE__{
      caster_guid: caster_guid,
      spell_id: spell_id,
      cast_time: cast_time,
      target_guid: target_guid || 0
    }
  end
end
