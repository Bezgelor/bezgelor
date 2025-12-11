defmodule BezgelorProtocol.Packets.World.ServerBattlegroundStatus do
  @moduledoc """
  Battleground queue/match status update.

  ## Overview

  Sent to inform players about their battleground queue status
  or ongoing match state.

  ## Wire Format

  ```
  status           : uint8   - Status code
  battleground_id  : uint32  - BG type ID (0 for random)
  estimated_wait   : uint32  - Estimated wait time in seconds (queue only)
  position         : uint16  - Position in queue (queue only)
  time_remaining   : uint32  - Match time remaining in seconds (match only)
  ```

  ## Status Codes

  | Code | Name | Description |
  |------|------|-------------|
  | 0 | none | Not in queue |
  | 1 | queued | In queue waiting |
  | 2 | ready | Match found, waiting for confirmation |
  | 3 | in_progress | Match in progress |
  | 4 | ended | Match ended |
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  # Status codes
  @status_none 0
  @status_queued 1
  @status_ready 2
  @status_in_progress 3
  @status_ended 4

  defstruct [:status, :battleground_id, :estimated_wait, :position, :time_remaining]

  @type status :: :none | :queued | :ready | :in_progress | :ended

  @type t :: %__MODULE__{
          status: status(),
          battleground_id: non_neg_integer() | nil,
          estimated_wait: non_neg_integer(),
          position: non_neg_integer(),
          time_remaining: non_neg_integer()
        }

  @impl true
  def opcode, do: :server_battleground_status

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    status_byte = status_to_int(packet.status)

    writer =
      writer
      |> PacketWriter.write_byte(status_byte)
      |> PacketWriter.write_uint32(packet.battleground_id || 0)
      |> PacketWriter.write_uint32(packet.estimated_wait || 0)
      |> PacketWriter.write_uint16(packet.position || 0)
      |> PacketWriter.write_uint32(packet.time_remaining || 0)

    {:ok, writer}
  end

  @doc """
  Create a 'not in queue' status.
  """
  @spec none() :: t()
  def none do
    %__MODULE__{
      status: :none,
      battleground_id: nil,
      estimated_wait: 0,
      position: 0,
      time_remaining: 0
    }
  end

  @doc """
  Create a 'in queue' status.
  """
  @spec queued(non_neg_integer() | nil, non_neg_integer(), non_neg_integer()) :: t()
  def queued(battleground_id, estimated_wait, position) do
    %__MODULE__{
      status: :queued,
      battleground_id: battleground_id,
      estimated_wait: estimated_wait,
      position: position,
      time_remaining: 0
    }
  end

  @doc """
  Create a 'match ready' status.
  """
  @spec ready(non_neg_integer()) :: t()
  def ready(battleground_id) do
    %__MODULE__{
      status: :ready,
      battleground_id: battleground_id,
      estimated_wait: 0,
      position: 0,
      time_remaining: 0
    }
  end

  @doc """
  Create an 'in progress' status.
  """
  @spec in_progress(non_neg_integer(), non_neg_integer()) :: t()
  def in_progress(battleground_id, time_remaining) do
    %__MODULE__{
      status: :in_progress,
      battleground_id: battleground_id,
      estimated_wait: 0,
      position: 0,
      time_remaining: time_remaining
    }
  end

  @doc """
  Create a 'match ended' status.
  """
  @spec ended(non_neg_integer()) :: t()
  def ended(battleground_id) do
    %__MODULE__{
      status: :ended,
      battleground_id: battleground_id,
      estimated_wait: 0,
      position: 0,
      time_remaining: 0
    }
  end

  defp status_to_int(:none), do: @status_none
  defp status_to_int(:queued), do: @status_queued
  defp status_to_int(:ready), do: @status_ready
  defp status_to_int(:in_progress), do: @status_in_progress
  defp status_to_int(:ended), do: @status_ended
  defp status_to_int(_), do: @status_none
end
