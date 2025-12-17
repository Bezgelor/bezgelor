defmodule BezgelorProtocol.Packets.World.ServerPvpStats do
  @moduledoc """
  PvP statistics update.

  ## Overview

  Sent to update a player's PvP statistics including kills,
  deaths, ratings, and currency.

  ## Wire Format

  ```
  lifetime_kills       : uint32  - Total killing blows
  lifetime_deaths      : uint32  - Total deaths
  honorable_kills      : uint32  - Kills in rated PvP
  duels_won            : uint32  - Duel victories
  duels_lost           : uint32  - Duel defeats
  battlegrounds_won    : uint32  - BG victories
  battlegrounds_lost   : uint32  - BG defeats
  arenas_won           : uint32  - Arena victories
  arenas_lost          : uint32  - Arena defeats
  honor_total          : uint32  - Total honor earned
  honor_this_week      : uint32  - Honor this week
  conquest_total       : uint32  - Total conquest earned
  conquest_this_week   : uint32  - Conquest this week
  conquest_cap         : uint32  - Weekly conquest cap
  rating_count         : uint8   - Number of bracket ratings
  For each rating:
    bracket            : uint8   - Bracket (0=2v2, 1=3v3, 2=5v5, 3=rbg)
    rating             : uint16  - Current rating
    season_high        : uint16  - Season high rating
    games_played       : uint16  - Games played this season
    games_won          : uint16  - Games won this season
  ```
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [
    :lifetime_kills,
    :lifetime_deaths,
    :honorable_kills,
    :duels_won,
    :duels_lost,
    :battlegrounds_won,
    :battlegrounds_lost,
    :arenas_won,
    :arenas_lost,
    :honor_total,
    :honor_this_week,
    :conquest_total,
    :conquest_this_week,
    :conquest_cap,
    :ratings
  ]

  @type rating_entry :: %{
          bracket: :"2v2" | :"3v3" | :"5v5" | :rbg,
          rating: non_neg_integer(),
          season_high: non_neg_integer(),
          games_played: non_neg_integer(),
          games_won: non_neg_integer()
        }

  @type t :: %__MODULE__{
          lifetime_kills: non_neg_integer(),
          lifetime_deaths: non_neg_integer(),
          honorable_kills: non_neg_integer(),
          duels_won: non_neg_integer(),
          duels_lost: non_neg_integer(),
          battlegrounds_won: non_neg_integer(),
          battlegrounds_lost: non_neg_integer(),
          arenas_won: non_neg_integer(),
          arenas_lost: non_neg_integer(),
          honor_total: non_neg_integer(),
          honor_this_week: non_neg_integer(),
          conquest_total: non_neg_integer(),
          conquest_this_week: non_neg_integer(),
          conquest_cap: non_neg_integer(),
          ratings: [rating_entry()]
        }

  @impl true
  def opcode, do: :server_pvp_stats

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_u32(packet.lifetime_kills)
      |> PacketWriter.write_u32(packet.lifetime_deaths)
      |> PacketWriter.write_u32(packet.honorable_kills)
      |> PacketWriter.write_u32(packet.duels_won)
      |> PacketWriter.write_u32(packet.duels_lost)
      |> PacketWriter.write_u32(packet.battlegrounds_won)
      |> PacketWriter.write_u32(packet.battlegrounds_lost)
      |> PacketWriter.write_u32(packet.arenas_won)
      |> PacketWriter.write_u32(packet.arenas_lost)
      |> PacketWriter.write_u32(packet.honor_total)
      |> PacketWriter.write_u32(packet.honor_this_week)
      |> PacketWriter.write_u32(packet.conquest_total)
      |> PacketWriter.write_u32(packet.conquest_this_week)
      |> PacketWriter.write_u32(packet.conquest_cap)
      |> PacketWriter.write_u8(length(packet.ratings))

    # Write ratings
    writer =
      Enum.reduce(packet.ratings, writer, fn r, w ->
        bracket_byte = bracket_to_byte(r.bracket)

        w
        |> PacketWriter.write_u8(bracket_byte)
        |> PacketWriter.write_u16(r.rating)
        |> PacketWriter.write_u16(r.season_high)
        |> PacketWriter.write_u16(r.games_played)
        |> PacketWriter.write_u16(r.games_won)
      end)

    {:ok, writer}
  end

  @doc """
  Create a PvP stats packet from stats and ratings data.
  """
  @spec from_data(map(), [map()]) :: t()
  def from_data(stats, ratings) do
    rating_entries =
      Enum.map(ratings, fn r ->
        %{
          bracket: String.to_atom(r.bracket),
          rating: r.rating,
          season_high: r.season_high,
          games_played: r.games_played,
          games_won: r.games_won
        }
      end)

    %__MODULE__{
      lifetime_kills: stats.lifetime_kills,
      lifetime_deaths: stats.lifetime_deaths,
      honorable_kills: stats.honorable_kills,
      duels_won: stats.duels_won,
      duels_lost: stats.duels_lost,
      battlegrounds_won: stats.battlegrounds_won,
      battlegrounds_lost: stats.battlegrounds_lost,
      arenas_won: stats.arenas_won,
      arenas_lost: stats.arenas_lost,
      honor_total: stats.honor_total,
      honor_this_week: stats.honor_this_week,
      conquest_total: stats.conquest_total,
      conquest_this_week: stats.conquest_this_week,
      conquest_cap: stats.conquest_cap,
      ratings: rating_entries
    }
  end

  defp bracket_to_byte(:"2v2"), do: 0
  defp bracket_to_byte(:"3v3"), do: 1
  defp bracket_to_byte(:"5v5"), do: 2
  defp bracket_to_byte(:rbg), do: 3
  defp bracket_to_byte(_), do: 0
end
