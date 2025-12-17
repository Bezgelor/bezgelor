defmodule BezgelorProtocol.Packets.World.ServerArenaResult do
  @moduledoc """
  Arena match result notification.

  ## Overview

  Sent to all participants when an arena match ends.
  Contains the outcome, rating changes, and final stats.

  ## Wire Format

  ```
  won              : uint8   - 1 if player's team won, 0 if lost
  team_rating_old  : uint16  - Team rating before match
  team_rating_new  : uint16  - Team rating after match
  personal_old     : uint16  - Personal rating before match
  personal_new     : uint16  - Personal rating after match
  enemy_team_name  : string  - Enemy team name
  enemy_rating     : uint16  - Enemy team rating
  match_duration   : uint16  - Match duration in seconds
  player_count     : uint8   - Number of player stats
  For each player:
    player_guid    : uint64  - Player GUID
    player_name    : string  - Player name
    team           : uint8   - 0=player's team, 1=enemy team
    kills          : uint8   - Killing blows
    deaths         : uint8   - Deaths
    damage         : uint32  - Total damage dealt
    healing        : uint32  - Total healing done
  ```
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [
    :won,
    :team_rating_old,
    :team_rating_new,
    :personal_rating_old,
    :personal_rating_new,
    :enemy_team_name,
    :enemy_rating,
    :match_duration,
    :player_stats
  ]

  @type player_stat :: %{
          player_guid: non_neg_integer(),
          player_name: String.t(),
          team: :own | :enemy,
          kills: non_neg_integer(),
          deaths: non_neg_integer(),
          damage: non_neg_integer(),
          healing: non_neg_integer()
        }

  @type t :: %__MODULE__{
          won: boolean(),
          team_rating_old: non_neg_integer(),
          team_rating_new: non_neg_integer(),
          personal_rating_old: non_neg_integer(),
          personal_rating_new: non_neg_integer(),
          enemy_team_name: String.t(),
          enemy_rating: non_neg_integer(),
          match_duration: non_neg_integer(),
          player_stats: [player_stat()]
        }

  @impl true
  def opcode, do: :server_arena_result

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    won_byte = if packet.won, do: 1, else: 0

    writer =
      writer
      |> PacketWriter.write_u8(won_byte)
      |> PacketWriter.write_u16(packet.team_rating_old)
      |> PacketWriter.write_u16(packet.team_rating_new)
      |> PacketWriter.write_u16(packet.personal_rating_old)
      |> PacketWriter.write_u16(packet.personal_rating_new)
      |> PacketWriter.write_wide_string(packet.enemy_team_name)
      |> PacketWriter.write_u16(packet.enemy_rating)
      |> PacketWriter.write_u16(packet.match_duration)
      |> PacketWriter.write_u8(length(packet.player_stats))

    # Write player stats
    writer =
      Enum.reduce(packet.player_stats, writer, fn ps, w ->
        team_byte = if ps.team == :own, do: 0, else: 1

        w
        |> PacketWriter.write_u64(ps.player_guid)
        |> PacketWriter.write_wide_string(ps.player_name)
        |> PacketWriter.write_u8(team_byte)
        |> PacketWriter.write_u8(ps.kills)
        |> PacketWriter.write_u8(ps.deaths)
        |> PacketWriter.write_u32(ps.damage)
        |> PacketWriter.write_u32(ps.healing)
      end)

    {:ok, writer}
  end

  @doc """
  Create a victory result.
  """
  @spec victory(map()) :: t()
  def victory(params) do
    %__MODULE__{
      won: true,
      team_rating_old: params[:team_rating_old],
      team_rating_new: params[:team_rating_new],
      personal_rating_old: params[:personal_rating_old],
      personal_rating_new: params[:personal_rating_new],
      enemy_team_name: params[:enemy_team_name],
      enemy_rating: params[:enemy_rating],
      match_duration: params[:match_duration],
      player_stats: params[:player_stats] || []
    }
  end

  @doc """
  Create a defeat result.
  """
  @spec defeat(map()) :: t()
  def defeat(params) do
    %__MODULE__{
      won: false,
      team_rating_old: params[:team_rating_old],
      team_rating_new: params[:team_rating_new],
      personal_rating_old: params[:personal_rating_old],
      personal_rating_new: params[:personal_rating_new],
      enemy_team_name: params[:enemy_team_name],
      enemy_rating: params[:enemy_rating],
      match_duration: params[:match_duration],
      player_stats: params[:player_stats] || []
    }
  end
end
