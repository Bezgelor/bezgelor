defmodule BezgelorProtocol.Packets.World.ClientBattlegroundReady do
  @moduledoc """
  Battleground ready confirmation.

  ## Overview

  Sent when a player confirms they're ready to enter a battleground
  after receiving the popup notification.

  ## Wire Format

  ```
  accepted : uint8  - 1=accept, 0=decline
  ```
  """

  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:accepted]

  @type t :: %__MODULE__{
          accepted: boolean()
        }

  @impl true
  def opcode, do: :client_battleground_ready

  @impl true
  def read(reader) do
    with {:ok, accepted_byte, reader} <- PacketReader.read_byte(reader) do
      {:ok, %__MODULE__{accepted: accepted_byte == 1}, reader}
    end
  end
end
