defmodule BezgelorProtocol.Packets.World.ServerBattlegroundScore do
  @moduledoc """
  Battleground scoreboard update.

  ## Overview

  Sent periodically during a battleground match to update
  the scoreboard with team scores and individual stats.

  ## Wire Format

  ```
  team1_score     : uint32  - Team 1 score
  team2_score     : uint32  - Team 2 score
  objective_count : uint8   - Number of objective updates
  For each objective:
    objective_id  : uint8   - Objective identifier
    owner_team    : uint8   - 0=neutral, 1=team1, 2=team2
    progress      : uint8   - Progress percentage (0-100)
  player_count    : uint8   - Number of player stat entries
  For each player:
    player_guid   : uint64  - Player GUID
    kills         : uint16  - Killing blows
    deaths        : uint16  - Deaths
    damage        : uint32  - Total damage dealt
    healing       : uint32  - Total healing done
    objectives    : uint16  - Objective points
  ```
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:team1_score, :team2_score, :objectives, :player_stats]

  @type objective :: %{
          id: non_neg_integer(),
          owner_team: 0 | 1 | 2,
          progress: non_neg_integer()
        }

  @type player_stat :: %{
          player_guid: non_neg_integer(),
          kills: non_neg_integer(),
          deaths: non_neg_integer(),
          damage: non_neg_integer(),
          healing: non_neg_integer(),
          objectives: non_neg_integer()
        }

  @type t :: %__MODULE__{
          team1_score: non_neg_integer(),
          team2_score: non_neg_integer(),
          objectives: [objective()],
          player_stats: [player_stat()]
        }

  @impl true
  def opcode, do: :server_battleground_score

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_u32(packet.team1_score)
      |> PacketWriter.write_u32(packet.team2_score)
      |> PacketWriter.write_u8(length(packet.objectives))

    # Write objectives
    writer =
      Enum.reduce(packet.objectives, writer, fn obj, w ->
        w
        |> PacketWriter.write_u8(obj.id)
        |> PacketWriter.write_u8(obj.owner_team)
        |> PacketWriter.write_u8(obj.progress)
      end)

    writer = PacketWriter.write_u8(writer, length(packet.player_stats))

    # Write player stats
    writer =
      Enum.reduce(packet.player_stats, writer, fn ps, w ->
        w
        |> PacketWriter.write_u64(ps.player_guid)
        |> PacketWriter.write_u16(ps.kills)
        |> PacketWriter.write_u16(ps.deaths)
        |> PacketWriter.write_u32(ps.damage)
        |> PacketWriter.write_u32(ps.healing)
        |> PacketWriter.write_u16(ps.objectives)
      end)

    {:ok, writer}
  end

  @doc """
  Create a scoreboard update.
  """
  @spec new(non_neg_integer(), non_neg_integer(), [objective()], [player_stat()]) :: t()
  def new(team1_score, team2_score, objectives, player_stats) do
    %__MODULE__{
      team1_score: team1_score,
      team2_score: team2_score,
      objectives: objectives,
      player_stats: player_stats
    }
  end
end
