defmodule BezgelorProtocol.Packets.World.ServerPetXP do
  @moduledoc """
  Pet XP gain notification from server.

  Sent when pet gains XP from combat or other activities.

  ## Wire Format
  xp_gained  : uint32  - Amount of XP gained
  current_xp : uint32  - Total XP after gain
  level      : uint8   - Current level (may have changed)
  leveled_up : uint8   - 1 if pet leveled up, 0 otherwise
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:xp_gained, :current_xp, :level, :leveled_up]

  @type t :: %__MODULE__{
          xp_gained: non_neg_integer(),
          current_xp: non_neg_integer(),
          level: non_neg_integer(),
          leveled_up: boolean()
        }

  @impl true
  def opcode, do: :server_pet_xp

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    leveled_up_byte = if packet.leveled_up, do: 1, else: 0

    writer =
      writer
      |> PacketWriter.write_uint32(packet.xp_gained)
      |> PacketWriter.write_uint32(packet.current_xp)
      |> PacketWriter.write_byte(packet.level)
      |> PacketWriter.write_byte(leveled_up_byte)

    {:ok, writer}
  end

  def new(xp_gained, current_xp, level, leveled_up) do
    %__MODULE__{
      xp_gained: xp_gained,
      current_xp: current_xp,
      level: level,
      leveled_up: leveled_up
    }
  end
end
