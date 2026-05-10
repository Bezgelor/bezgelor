defmodule BezgelorProtocol.Packets.World.ServerEntityHealthUpdate do
  @moduledoc """
  Server notification of entity health change.

  ## Overview

  Sent when an entity's health changes (typically from damage or healing).
  This forces a refresh on the client's health bar display for the target entity.

  IMPORTANT: This packet must be sent after damage is applied for health bars
  to update on the client.

  ## Wire Format (per NexusForever)

  ```
  unit_id  : uint32 - Lower 32 bits of entity GUID
  health   : uint32 - Current health value
  unknown0 : bool   - Unknown flag (usually false)
  ```
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:unit_id, :health, unknown0: false]

  @type t :: %__MODULE__{
          unit_id: non_neg_integer(),
          health: non_neg_integer(),
          unknown0: boolean()
        }

  @impl true
  def opcode, do: :server_entity_health_update

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_u32(packet.unit_id)
      |> PacketWriter.write_u32(packet.health)
      |> PacketWriter.write_bits(if(packet.unknown0, do: 1, else: 0), 1)
      |> PacketWriter.flush_bits()

    {:ok, writer}
  end

  @doc """
  Create a health update packet for an entity.

  ## Parameters

  - entity_guid: Full 64-bit GUID of the entity (unit_id extracted automatically)
  - health: Current health value after change
  """
  @spec new(non_neg_integer(), non_neg_integer()) :: t()
  def new(entity_guid, health) do
    import Bitwise

    %__MODULE__{
      unit_id: entity_guid &&& 0xFFFFFFFF,
      health: health
    }
  end
end
