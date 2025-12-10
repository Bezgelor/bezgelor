defmodule BezgelorProtocol.Packets.World.ClientSetTarget do
  @moduledoc """
  Client request to target an entity.

  ## Overview

  Sent when the player selects a target (player, creature, NPC).
  A target_guid of 0 means clearing the target.

  ## Wire Format

  ```
  target_guid : uint64 - GUID of entity to target (0 to clear)
  ```
  """

  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:target_guid]

  @type t :: %__MODULE__{
          target_guid: non_neg_integer()
        }

  @impl true
  def opcode, do: :client_set_target

  @impl true
  def read(reader) do
    with {:ok, target_guid, reader} <- PacketReader.read_uint64(reader) do
      {:ok,
       %__MODULE__{
         target_guid: target_guid
       }, reader}
    end
  end
end
