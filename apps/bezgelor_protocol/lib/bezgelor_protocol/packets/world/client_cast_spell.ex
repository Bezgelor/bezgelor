defmodule BezgelorProtocol.Packets.World.ClientCastSpell do
  @moduledoc """
  Spell cast request from client.

  ## Overview

  Sent when a player initiates a spell cast. Contains the spell ID,
  target entity (if any), and ground target position (for AoE spells).

  ## Wire Format

  ```
  spell_id     : uint32  - Spell to cast
  target_guid  : uint64  - Target entity (0 for ground/self)
  target_x     : float32 - Ground target X coordinate
  target_y     : float32 - Ground target Y coordinate
  target_z     : float32 - Ground target Z coordinate
  ```
  """

  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:spell_id, :target_guid, :target_position]

  @type t :: %__MODULE__{
          spell_id: non_neg_integer(),
          target_guid: non_neg_integer(),
          target_position: {float(), float(), float()}
        }

  @impl true
  def opcode, do: :client_cast_spell

  @impl true
  def read(reader) do
    with {:ok, spell_id, reader} <- PacketReader.read_uint32(reader),
         {:ok, target_guid, reader} <- PacketReader.read_uint64(reader),
         {:ok, x, reader} <- PacketReader.read_float32(reader),
         {:ok, y, reader} <- PacketReader.read_float32(reader),
         {:ok, z, reader} <- PacketReader.read_float32(reader) do
      {:ok,
       %__MODULE__{
         spell_id: spell_id,
         target_guid: target_guid,
         target_position: {x, y, z}
       }, reader}
    end
  end
end
