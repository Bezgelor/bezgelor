defmodule BezgelorProtocol.Packets.World.ServerArenaTeamRoster do
  @moduledoc """
  Arena team roster information.

  ## Overview

  Sent to show the full roster of an arena team including
  member stats and ratings.

  ## Wire Format

  ```
  team_id          : uint32  - Arena team ID
  team_name        : string  - Team name
  bracket          : uint8   - 0=2v2, 1=3v3, 2=5v5
  rating           : uint16  - Team rating
  season_high      : uint16  - Season high rating
  games_played     : uint16  - Total games played
  games_won        : uint16  - Total games won
  member_count     : uint8   - Number of members
  For each member:
    character_id   : uint64  - Character ID
    character_name : string  - Character name
    role           : uint8   - 0=member, 1=captain
    personal_rating: uint16  - Personal rating
    games_played   : uint16  - Games played
    games_won      : uint16  - Games won
    online         : uint8   - 1 if online, 0 if offline
  ```
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [
    :team_id,
    :team_name,
    :bracket,
    :rating,
    :season_high,
    :games_played,
    :games_won,
    :members
  ]

  @type member :: %{
          character_id: non_neg_integer(),
          character_name: String.t(),
          role: :member | :captain,
          personal_rating: non_neg_integer(),
          games_played: non_neg_integer(),
          games_won: non_neg_integer(),
          online: boolean()
        }

  @type t :: %__MODULE__{
          team_id: non_neg_integer(),
          team_name: String.t(),
          bracket: :"2v2" | :"3v3" | :"5v5",
          rating: non_neg_integer(),
          season_high: non_neg_integer(),
          games_played: non_neg_integer(),
          games_won: non_neg_integer(),
          members: [member()]
        }

  @impl true
  def opcode, do: :server_arena_team_roster

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    bracket_byte = bracket_to_byte(packet.bracket)

    writer =
      writer
      |> PacketWriter.write_uint32(packet.team_id)
      |> PacketWriter.write_wide_string(packet.team_name)
      |> PacketWriter.write_byte(bracket_byte)
      |> PacketWriter.write_uint16(packet.rating)
      |> PacketWriter.write_uint16(packet.season_high)
      |> PacketWriter.write_uint16(packet.games_played)
      |> PacketWriter.write_uint16(packet.games_won)
      |> PacketWriter.write_byte(length(packet.members))

    # Write members
    writer =
      Enum.reduce(packet.members, writer, fn member, w ->
        role_byte = if member.role == :captain, do: 1, else: 0
        online_byte = if member.online, do: 1, else: 0

        w
        |> PacketWriter.write_uint64(member.character_id)
        |> PacketWriter.write_wide_string(member.character_name)
        |> PacketWriter.write_byte(role_byte)
        |> PacketWriter.write_uint16(member.personal_rating)
        |> PacketWriter.write_uint16(member.games_played)
        |> PacketWriter.write_uint16(member.games_won)
        |> PacketWriter.write_byte(online_byte)
      end)

    {:ok, writer}
  end

  defp bracket_to_byte(:"2v2"), do: 0
  defp bracket_to_byte(:"3v3"), do: 1
  defp bracket_to_byte(:"5v5"), do: 2
  defp bracket_to_byte(_), do: 0
end
