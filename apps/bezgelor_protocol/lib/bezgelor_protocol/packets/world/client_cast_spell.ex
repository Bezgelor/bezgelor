defmodule BezgelorProtocol.Packets.World.ClientCastSpell do
  @moduledoc """
  Spell cast request from client.

  ## Overview

  Sent when a player initiates a spell cast from their action bar.
  The bag_index refers to a slot in the player's ability inventory
  which must be resolved to get the actual spell ID.

  ## Wire Format (per NexusForever)

  ```
  client_unique_id : uint32  - Client-assigned unique ID for this cast
  bag_index        : uint16  - Ability bag slot index
  caster_id        : uint32  - Entity ID of the caster
  button_pressed   : 1 bit   - Whether the ability button is pressed
  ```

  ## Usage

  The handler should:
  1. Look up the spell ID from the character's ability bag using bag_index
  2. Validate the spell can be cast
  3. Initiate the spell casting process
  """

  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:client_unique_id, :bag_index, :caster_id, :button_pressed]

  @type t :: %__MODULE__{
          client_unique_id: non_neg_integer(),
          bag_index: non_neg_integer(),
          caster_id: non_neg_integer(),
          button_pressed: boolean()
        }

  @impl true
  def opcode, do: :client_cast_spell

  @impl true
  def read(reader) do
    with {:ok, client_unique_id, reader} <- PacketReader.read_uint32(reader),
         {:ok, bag_index, reader} <- PacketReader.read_uint16(reader),
         {:ok, caster_id, reader} <- PacketReader.read_uint32(reader),
         {:ok, button_pressed, reader} <- PacketReader.read_bit(reader) do
      {:ok,
       %__MODULE__{
         client_unique_id: client_unique_id,
         bag_index: bag_index,
         caster_id: caster_id,
         button_pressed: button_pressed == 1
       }, reader}
    end
  end
end
