defmodule BezgelorProtocol.Packets.World.ClientBattlegroundLeave do
  @moduledoc """
  Leave battleground queue or instance.

  ## Overview

  Sent when a player wants to leave the battleground queue
  or exit an active battleground match.

  ## Wire Format

  ```
  leave_type : uint8  - 0=leave queue, 1=leave match
  ```
  """

  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:leave_type]

  @type leave_type :: :queue | :match

  @type t :: %__MODULE__{
          leave_type: leave_type()
        }

  @impl true
  def opcode, do: :client_battleground_leave

  @impl true
  def read(reader) do
    with {:ok, leave_byte, reader} <- PacketReader.read_byte(reader) do
      leave_type = if leave_byte == 0, do: :queue, else: :match

      {:ok, %__MODULE__{leave_type: leave_type}, reader}
    end
  end
end
