defmodule BezgelorProtocol.Packets.World.ServerPlayerDeath do
  @moduledoc """
  Server notification of player death.

  ## Overview

  Sent when a player dies. Includes death type for UI display
  (combat, fall, drown, environment).

  ## Wire Format

  ```
  player_guid : uint64 - GUID of player that died
  killer_guid : uint64 - GUID of killer (0 if environmental)
  death_type  : uint32 - Type of death (0=combat, 1=fall, 2=drown, 3=environment)
  ```

  ## Death Types

  - 0 = Combat death (killed by entity)
  - 1 = Fall damage
  - 2 = Drowning
  - 3 = Environmental hazard (lava, etc.)
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:player_guid, :killer_guid, :death_type]

  @type t :: %__MODULE__{
          player_guid: non_neg_integer(),
          killer_guid: non_neg_integer() | nil,
          death_type: non_neg_integer()
        }

  @doc """
  Create a new ServerPlayerDeath packet.

  ## Parameters

  - `player_guid` - GUID of the player who died
  - `killer_guid` - GUID of the killer (nil for environmental deaths)
  - `death_type` - Atom or integer: :combat (0), :fall (1), :drown (2), :environment (3)
  """
  @spec new(non_neg_integer(), non_neg_integer() | nil, atom() | non_neg_integer()) :: t()
  def new(player_guid, killer_guid, death_type) do
    death_type_int =
      case death_type do
        :combat -> 0
        :fall -> 1
        :drown -> 2
        :environment -> 3
        int when is_integer(int) -> int
      end

    %__MODULE__{
      player_guid: player_guid,
      killer_guid: killer_guid,
      death_type: death_type_int
    }
  end

  @impl true
  def opcode, do: :server_player_death

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_u64(packet.player_guid)
      |> PacketWriter.write_u64(packet.killer_guid || 0)
      |> PacketWriter.write_u32(packet.death_type)

    {:ok, writer}
  end
end
