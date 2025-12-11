defmodule BezgelorProtocol.Packets.World.ClientDuelRequest do
  @moduledoc """
  Duel challenge request from client.

  ## Overview

  Sent when a player challenges another player to a duel.
  The target must be nearby and not already in a duel.

  ## Wire Format

  ```
  target_guid  : uint64  - GUID of player to challenge
  ```
  """

  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:target_guid]

  @type t :: %__MODULE__{
          target_guid: non_neg_integer()
        }

  @impl true
  def opcode, do: :client_duel_request

  @impl true
  def read(reader) do
    with {:ok, target_guid, reader} <- PacketReader.read_uint64(reader) do
      {:ok, %__MODULE__{target_guid: target_guid}, reader}
    end
  end
end
