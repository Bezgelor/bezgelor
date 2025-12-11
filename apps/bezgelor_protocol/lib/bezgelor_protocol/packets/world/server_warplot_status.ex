defmodule BezgelorProtocol.Packets.World.ServerWarplotStatus do
  @moduledoc """
  Warplot queue and battle status.

  ## Overview

  Sent to inform guild members about their warplot's current
  queue or battle status.

  ## Wire Format

  ```
  status         : uint8   - Status code
  warplot_id     : uint32  - Warplot ID
  warplot_name   : string  - Warplot name
  rating         : uint16  - Warplot rating
  energy         : uint16  - Current energy
  war_coins      : uint32  - Available war coins
  queue_time     : uint32  - Time in queue (seconds, if queued)
  match_time     : uint32  - Match time remaining (seconds, if in battle)
  team1_score    : uint32  - Own team score (if in battle)
  team2_score    : uint32  - Enemy score (if in battle)
  ```

  ## Status Codes

  | Code | Name | Description |
  |------|------|-------------|
  | 0 | idle | Not queued |
  | 1 | queued | In queue |
  | 2 | in_battle | Battle in progress |
  | 3 | ended | Battle ended |
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  @status_idle 0
  @status_queued 1
  @status_in_battle 2
  @status_ended 3

  defstruct [
    :status,
    :warplot_id,
    :warplot_name,
    :rating,
    :energy,
    :war_coins,
    :queue_time,
    :match_time,
    :team1_score,
    :team2_score
  ]

  @type status :: :idle | :queued | :in_battle | :ended

  @type t :: %__MODULE__{
          status: status(),
          warplot_id: non_neg_integer(),
          warplot_name: String.t(),
          rating: non_neg_integer(),
          energy: non_neg_integer(),
          war_coins: non_neg_integer(),
          queue_time: non_neg_integer(),
          match_time: non_neg_integer(),
          team1_score: non_neg_integer(),
          team2_score: non_neg_integer()
        }

  @impl true
  def opcode, do: :server_warplot_status

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    status_byte = status_to_int(packet.status)

    writer =
      writer
      |> PacketWriter.write_byte(status_byte)
      |> PacketWriter.write_uint32(packet.warplot_id)
      |> PacketWriter.write_wide_string(packet.warplot_name)
      |> PacketWriter.write_uint16(packet.rating)
      |> PacketWriter.write_uint16(packet.energy)
      |> PacketWriter.write_uint32(packet.war_coins)
      |> PacketWriter.write_uint32(packet.queue_time)
      |> PacketWriter.write_uint32(packet.match_time)
      |> PacketWriter.write_uint32(packet.team1_score)
      |> PacketWriter.write_uint32(packet.team2_score)

    {:ok, writer}
  end

  @doc """
  Create an idle status.
  """
  @spec idle(map()) :: t()
  def idle(warplot) do
    %__MODULE__{
      status: :idle,
      warplot_id: warplot.id,
      warplot_name: warplot.name,
      rating: warplot.rating,
      energy: warplot.energy,
      war_coins: warplot.war_coins,
      queue_time: 0,
      match_time: 0,
      team1_score: 0,
      team2_score: 0
    }
  end

  @doc """
  Create a queued status.
  """
  @spec queued(map(), non_neg_integer()) :: t()
  def queued(warplot, queue_time) do
    %__MODULE__{
      status: :queued,
      warplot_id: warplot.id,
      warplot_name: warplot.name,
      rating: warplot.rating,
      energy: warplot.energy,
      war_coins: warplot.war_coins,
      queue_time: queue_time,
      match_time: 0,
      team1_score: 0,
      team2_score: 0
    }
  end

  @doc """
  Create an in-battle status.
  """
  @spec in_battle(map(), non_neg_integer(), non_neg_integer(), non_neg_integer()) :: t()
  def in_battle(warplot, match_time, team1_score, team2_score) do
    %__MODULE__{
      status: :in_battle,
      warplot_id: warplot.id,
      warplot_name: warplot.name,
      rating: warplot.rating,
      energy: warplot.energy,
      war_coins: warplot.war_coins,
      queue_time: 0,
      match_time: match_time,
      team1_score: team1_score,
      team2_score: team2_score
    }
  end

  defp status_to_int(:idle), do: @status_idle
  defp status_to_int(:queued), do: @status_queued
  defp status_to_int(:in_battle), do: @status_in_battle
  defp status_to_int(:ended), do: @status_ended
  defp status_to_int(_), do: @status_idle
end
