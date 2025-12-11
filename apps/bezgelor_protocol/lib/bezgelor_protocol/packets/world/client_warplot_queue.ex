defmodule BezgelorProtocol.Packets.World.ClientWarplotQueue do
  @moduledoc """
  Queue for warplot battle.

  ## Overview

  Sent when a guild warplot leader wants to queue for
  a 40v40 warplot battle.

  ## Wire Format

  ```
  warplot_id : uint32  - Warplot ID
  action     : uint8   - 0=join queue, 1=leave queue
  ```
  """

  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:warplot_id, :action]

  @type action :: :join | :leave

  @type t :: %__MODULE__{
          warplot_id: non_neg_integer(),
          action: action()
        }

  @impl true
  def opcode, do: :client_warplot_queue

  @impl true
  def read(reader) do
    with {:ok, warplot_id, reader} <- PacketReader.read_uint32(reader),
         {:ok, action_byte, reader} <- PacketReader.read_byte(reader) do
      action = if action_byte == 0, do: :join, else: :leave

      {:ok,
       %__MODULE__{
         warplot_id: warplot_id,
         action: action
       }, reader}
    end
  end
end
