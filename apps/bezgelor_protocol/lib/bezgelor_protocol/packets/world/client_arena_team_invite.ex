defmodule BezgelorProtocol.Packets.World.ClientArenaTeamInvite do
  @moduledoc """
  Invite player to arena team.

  ## Overview

  Sent when an arena team captain wants to invite another player
  to join their team.

  ## Wire Format

  ```
  team_id      : uint32  - Arena team ID
  target_name  : string  - Name of player to invite
  ```
  """

  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:team_id, :target_name]

  @type t :: %__MODULE__{
          team_id: non_neg_integer(),
          target_name: String.t()
        }

  @impl true
  def opcode, do: :client_arena_team_invite

  @impl true
  def read(reader) do
    with {:ok, team_id, reader} <- PacketReader.read_uint32(reader),
         {:ok, target_name, reader} <- PacketReader.read_string(reader) do
      {:ok,
       %__MODULE__{
         team_id: team_id,
         target_name: target_name
       }, reader}
    end
  end
end
