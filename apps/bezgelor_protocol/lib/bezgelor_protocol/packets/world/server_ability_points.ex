defmodule BezgelorProtocol.Packets.World.ServerAbilityPoints do
  @moduledoc """
  ServerAbilityPoints packet (0x0169).

  Sends the player's available and total ability points (tier points).
  These points are used to upgrade spell tiers in the Limited Action Set.

  ## Packet Structure (from NexusForever)

      u32 ability_points       # Current available points
      u32 total_ability_points # Maximum points (42 at max level)

  ## Usage

      packet = %ServerAbilityPoints{
        ability_points: 42,
        total_ability_points: 42
      }
  """

  alias BezgelorProtocol.PacketWriter

  @behaviour BezgelorProtocol.Packet.Writable

  defstruct ability_points: 42, total_ability_points: 42

  @type t :: %__MODULE__{
          ability_points: non_neg_integer(),
          total_ability_points: non_neg_integer()
        }

  @impl true
  def opcode, do: :server_ability_points

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_u32(packet.ability_points)
      |> PacketWriter.write_u32(packet.total_ability_points)
      |> PacketWriter.flush_bits()

    {:ok, writer}
  end
end
