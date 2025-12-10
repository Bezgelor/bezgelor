defmodule BezgelorProtocol.Packets.World.ServerEntityDeath do
  @moduledoc """
  Server notification of entity death.

  ## Overview

  Sent when an entity (player or creature) dies.
  Includes the killer's GUID if applicable.

  ## Wire Format

  ```
  entity_guid : uint64 - GUID of entity that died
  killer_guid : uint64 - GUID of killer (0 if none/environment)
  ```
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:entity_guid, :killer_guid]

  @type t :: %__MODULE__{
          entity_guid: non_neg_integer(),
          killer_guid: non_neg_integer()
        }

  @impl true
  def opcode, do: :server_entity_death

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_uint64(packet.entity_guid)
      |> PacketWriter.write_uint64(packet.killer_guid || 0)

    {:ok, writer}
  end
end
