defmodule BezgelorProtocol.Packets.World.ClientResurrectAccept do
  @moduledoc """
  Client response to a resurrection offer.

  ## Overview

  Sent by the client when the player accepts or declines a pending
  resurrection offer from another player.

  ## Wire Format

  ```
  accept : uint8 - 1 to accept, 0 to decline
  ```
  """

  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct accept: false

  @type t :: %__MODULE__{
          accept: boolean()
        }

  @impl true
  def opcode, do: :client_resurrect_accept

  @impl true
  def read(reader) do
    with {:ok, accept_int, reader} <- PacketReader.read_byte(reader) do
      {:ok,
       %__MODULE__{
         accept: accept_int != 0
       }, reader}
    end
  end
end
