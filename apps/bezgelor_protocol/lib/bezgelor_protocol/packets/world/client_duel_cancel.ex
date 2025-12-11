defmodule BezgelorProtocol.Packets.World.ClientDuelCancel do
  @moduledoc """
  Cancel an outgoing duel request.

  ## Overview

  Sent when a player cancels their pending duel challenge
  before the target responds.

  ## Wire Format

  ```
  target_guid : uint64  - GUID of player who was challenged
  ```
  """

  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:target_guid]

  @type t :: %__MODULE__{
          target_guid: non_neg_integer()
        }

  @impl true
  def opcode, do: :client_duel_cancel

  @impl true
  def read(reader) do
    with {:ok, target_guid, reader} <- PacketReader.read_uint64(reader) do
      {:ok, %__MODULE__{target_guid: target_guid}, reader}
    end
  end
end
