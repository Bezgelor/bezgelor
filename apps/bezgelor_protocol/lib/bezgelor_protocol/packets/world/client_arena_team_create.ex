defmodule BezgelorProtocol.Packets.World.ClientArenaTeamCreate do
  @moduledoc """
  Create arena team request.

  ## Overview

  Sent when a player wants to create a new arena team
  for a specific bracket (2v2, 3v3, or 5v5).

  ## Wire Format

  ```
  bracket   : uint8   - 0=2v2, 1=3v3, 2=5v5
  name_len  : uint16  - Length of team name
  name      : string  - Team name (UTF-8)
  ```
  """

  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:bracket, :name]

  @type bracket :: :"2v2" | :"3v3" | :"5v5"

  @type t :: %__MODULE__{
          bracket: bracket(),
          name: String.t()
        }

  @impl true
  def opcode, do: :client_arena_team_create

  @impl true
  def read(reader) do
    with {:ok, bracket_byte, reader} <- PacketReader.read_byte(reader),
         {:ok, name, reader} <- PacketReader.read_string(reader) do
      bracket = byte_to_bracket(bracket_byte)

      {:ok,
       %__MODULE__{
         bracket: bracket,
         name: name
       }, reader}
    end
  end

  defp byte_to_bracket(0), do: :"2v2"
  defp byte_to_bracket(1), do: :"3v3"
  defp byte_to_bracket(2), do: :"5v5"
  defp byte_to_bracket(_), do: :"2v2"
end
