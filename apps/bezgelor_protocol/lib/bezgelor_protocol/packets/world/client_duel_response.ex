defmodule BezgelorProtocol.Packets.World.ClientDuelResponse do
  @moduledoc """
  Duel challenge response from client.

  ## Overview

  Sent when a player accepts or declines a duel challenge.

  ## Wire Format

  ```
  challenger_guid : uint64  - GUID of the challenger
  accepted        : uint8   - 1 = accept, 0 = decline
  ```
  """

  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:challenger_guid, :accepted]

  @type t :: %__MODULE__{
          challenger_guid: non_neg_integer(),
          accepted: boolean()
        }

  @impl true
  def opcode, do: :client_duel_response

  @impl true
  def read(reader) do
    with {:ok, challenger_guid, reader} <- PacketReader.read_uint64(reader),
         {:ok, accepted_byte, reader} <- PacketReader.read_byte(reader) do
      {:ok,
       %__MODULE__{
         challenger_guid: challenger_guid,
         accepted: accepted_byte == 1
       }, reader}
    end
  end
end
