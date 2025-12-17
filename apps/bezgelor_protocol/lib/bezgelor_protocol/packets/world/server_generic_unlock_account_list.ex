defmodule BezgelorProtocol.Packets.World.ServerGenericUnlockAccountList do
  @moduledoc """
  Server packet containing account generic unlocks.

  ## Overview

  Sent before the character list to inform the client of the account's
  generic unlocks (mounts, pets, costumes, etc. that are account-wide).

  ## Packet Structure

  ```
  count      : uint32    - Number of unlocks
  unlock_ids : uint32[]  - Array of unlock entry IDs
  ```
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct unlock_ids: []

  @type t :: %__MODULE__{
          unlock_ids: [non_neg_integer()]
        }

  @impl true
  def opcode, do: :server_generic_unlock_account_list

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    unlock_ids = packet.unlock_ids || []

    # Write count
    writer = PacketWriter.write_u32(writer, length(unlock_ids))

    # Write each unlock ID
    writer =
      Enum.reduce(unlock_ids, writer, fn id, w ->
        PacketWriter.write_u32(w, id)
      end)

    {:ok, writer}
  end
end
