defmodule BezgelorProtocol.Packets.World.ClientNpcInteract do
  @moduledoc """
  Client interacts with an NPC (right-click or interact key).

  This packet triggers NPC interaction logic based on the event type:
  - 37: Dialogue/Quest NPC
  - 49: Vendor
  - 48: Taxi/Flight Master
  - 43: Tradeskill Trainer
  - 66: Bank
  - 68: Mailbox

  ## Wire Format

  ```
  npc_guid : uint32 (entity GUID of the NPC)
  event    : 7 bits (interaction event type)
  ```

  Opcode: 0x07EA
  """
  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  @type t :: %__MODULE__{
          npc_guid: non_neg_integer(),
          event: non_neg_integer()
        }

  defstruct npc_guid: 0,
            event: 0

  # Event type constants
  @event_dialogue 37
  @event_vendor 49
  @event_taxi 48
  @event_tradeskill_trainer 43
  @event_bank 66
  @event_mailbox 68

  def event_dialogue, do: @event_dialogue
  def event_vendor, do: @event_vendor
  def event_taxi, do: @event_taxi
  def event_tradeskill_trainer, do: @event_tradeskill_trainer
  def event_bank, do: @event_bank
  def event_mailbox, do: @event_mailbox

  @impl true
  def opcode, do: :client_npc_interact

  @impl true
  def read(reader) do
    with {:ok, npc_guid, reader} <- PacketReader.read_uint32(reader),
         {:ok, event, reader} <- PacketReader.read_bits(reader, 7) do
      packet = %__MODULE__{
        npc_guid: npc_guid,
        event: event
      }

      {:ok, packet, reader}
    end
  end
end
