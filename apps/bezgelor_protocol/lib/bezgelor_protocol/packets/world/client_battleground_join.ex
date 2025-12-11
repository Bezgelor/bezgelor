defmodule BezgelorProtocol.Packets.World.ClientBattlegroundJoin do
  @moduledoc """
  Join battleground queue request.

  ## Overview

  Sent when a player wants to join a battleground queue.
  Can queue for a specific battleground or random.

  ## Wire Format

  ```
  battleground_id : uint32  - Specific BG ID, or 0 for random
  queue_type      : uint8   - 0=solo, 1=group
  ```
  """

  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:battleground_id, :queue_as_group]

  @type t :: %__MODULE__{
          battleground_id: non_neg_integer() | nil,
          queue_as_group: boolean()
        }

  @impl true
  def opcode, do: :client_battleground_join

  @impl true
  def read(reader) do
    with {:ok, bg_id, reader} <- PacketReader.read_uint32(reader),
         {:ok, queue_type, reader} <- PacketReader.read_byte(reader) do
      {:ok,
       %__MODULE__{
         battleground_id: if(bg_id == 0, do: nil, else: bg_id),
         queue_as_group: queue_type == 1
       }, reader}
    end
  end
end
