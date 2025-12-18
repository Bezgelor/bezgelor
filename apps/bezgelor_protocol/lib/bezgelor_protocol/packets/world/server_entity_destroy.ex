defmodule BezgelorProtocol.Packets.World.ServerEntityDestroy do
  @moduledoc """
  Entity removal packet.

  ## Overview

  Sent to remove an entity from the world. Used when entities
  leave visibility range, die, or disconnect.

  ## Wire Format

  ```
  guid   : uint64 - Entity GUID to remove
  reason : uint32 - Removal reason code
  ```

  ## Reason Codes

  | Code | Name | Description |
  |------|------|-------------|
  | 0 | Out of range | Entity left visibility range |
  | 1 | Death | Entity died |
  | 2 | Disconnect | Player disconnected |
  | 3 | Teleport | Entity teleported away |
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  # Removal reason codes
  @reason_out_of_range 0
  @reason_death 1
  @reason_disconnect 2
  @reason_teleport 3

  defstruct [
    :guid,
    reason: :out_of_range
  ]

  @type reason :: :out_of_range | :death | :disconnect | :teleport

  @type t :: %__MODULE__{
          guid: non_neg_integer(),
          reason: reason()
        }

  @impl true
  def opcode, do: :server_entity_destroy

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    reason_code = reason_to_code(packet.reason)

    writer =
      writer
      |> PacketWriter.write_u64(packet.guid)
      |> PacketWriter.write_u32(reason_code)

    {:ok, writer}
  end

  @doc "Convert reason atom to integer code."
  @spec reason_to_code(reason()) :: non_neg_integer()
  def reason_to_code(:out_of_range), do: @reason_out_of_range
  def reason_to_code(:death), do: @reason_death
  def reason_to_code(:disconnect), do: @reason_disconnect
  def reason_to_code(:teleport), do: @reason_teleport
  def reason_to_code(_), do: @reason_out_of_range

  @doc "Convert integer code to reason atom."
  @spec code_to_reason(non_neg_integer()) :: reason()
  def code_to_reason(@reason_out_of_range), do: :out_of_range
  def code_to_reason(@reason_death), do: :death
  def code_to_reason(@reason_disconnect), do: :disconnect
  def code_to_reason(@reason_teleport), do: :teleport
  def code_to_reason(_), do: :out_of_range
end
