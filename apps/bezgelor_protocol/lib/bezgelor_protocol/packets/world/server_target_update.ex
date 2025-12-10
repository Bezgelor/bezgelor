defmodule BezgelorProtocol.Packets.World.ServerTargetUpdate do
  @moduledoc """
  Server notification of target change.

  ## Overview

  Sent to client when their target changes, or to others when
  an entity's target changes.

  ## Wire Format

  ```
  entity_guid : uint64 - GUID of entity whose target changed
  target_guid : uint64 - GUID of new target (0 for no target)
  ```
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:entity_guid, :target_guid]

  @type t :: %__MODULE__{
          entity_guid: non_neg_integer(),
          target_guid: non_neg_integer()
        }

  @impl true
  def opcode, do: :server_target_update

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_uint64(packet.entity_guid)
      |> PacketWriter.write_uint64(packet.target_guid || 0)

    {:ok, writer}
  end
end
