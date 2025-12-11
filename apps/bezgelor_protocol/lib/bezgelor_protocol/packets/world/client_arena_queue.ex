defmodule BezgelorProtocol.Packets.World.ClientArenaQueue do
  @moduledoc """
  Queue for arena match.

  ## Overview

  Sent when a player wants to queue for an arena match
  with their team.

  ## Wire Format

  ```
  team_id : uint32  - Arena team ID
  action  : uint8   - 0=join queue, 1=leave queue
  ```
  """

  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:team_id, :action]

  @type action :: :join | :leave

  @type t :: %__MODULE__{
          team_id: non_neg_integer(),
          action: action()
        }

  @impl true
  def opcode, do: :client_arena_queue

  @impl true
  def read(reader) do
    with {:ok, team_id, reader} <- PacketReader.read_uint32(reader),
         {:ok, action_byte, reader} <- PacketReader.read_byte(reader) do
      action = if action_byte == 0, do: :join, else: :leave

      {:ok,
       %__MODULE__{
         team_id: team_id,
         action: action
       }, reader}
    end
  end
end
