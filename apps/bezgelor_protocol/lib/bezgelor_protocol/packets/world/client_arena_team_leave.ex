defmodule BezgelorProtocol.Packets.World.ClientArenaTeamLeave do
  @moduledoc """
  Leave arena team request.

  ## Overview

  Sent when a player wants to leave their arena team.
  Captains must transfer leadership before leaving.

  ## Wire Format

  ```
  team_id : uint32  - Arena team ID to leave
  ```
  """

  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:team_id]

  @type t :: %__MODULE__{
          team_id: non_neg_integer()
        }

  @impl true
  def opcode, do: :client_arena_team_leave

  @impl true
  def read(reader) do
    with {:ok, team_id, reader} <- PacketReader.read_uint32(reader) do
      {:ok, %__MODULE__{team_id: team_id}, reader}
    end
  end
end
