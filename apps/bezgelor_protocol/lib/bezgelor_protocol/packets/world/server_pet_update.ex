defmodule BezgelorProtocol.Packets.World.ServerPetUpdate do
  @moduledoc """
  Pet state update from server.

  Sent when a player's pet status changes (summoned/dismissed/leveled).

  ## Wire Format
  entity_guid : uint64  - Entity whose pet changed
  pet_id      : uint32  - Pet ID (0 = dismissed)
  level       : uint8   - Pet level (1-25)
  xp          : uint32  - Current XP
  nickname    : wstring - Pet nickname (empty if none)
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:entity_guid, :pet_id, :level, :xp, :nickname]

  @type t :: %__MODULE__{
          entity_guid: non_neg_integer(),
          pet_id: non_neg_integer(),
          level: non_neg_integer(),
          xp: non_neg_integer(),
          nickname: String.t() | nil
        }

  @impl true
  def opcode, do: :server_pet_update

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_u64(packet.entity_guid)
      |> PacketWriter.write_u32(packet.pet_id || 0)
      |> PacketWriter.write_u8(packet.level || 1)
      |> PacketWriter.write_u32(packet.xp || 0)
      |> PacketWriter.write_wide_string(packet.nickname || "")

    {:ok, writer}
  end

  # Constructors for common states
  def summoned(entity_guid, pet_id, level, xp, nickname) do
    %__MODULE__{
      entity_guid: entity_guid,
      pet_id: pet_id,
      level: level,
      xp: xp,
      nickname: nickname
    }
  end

  def dismissed(entity_guid) do
    %__MODULE__{
      entity_guid: entity_guid,
      pet_id: 0,
      level: 1,
      xp: 0,
      nickname: nil
    }
  end
end
