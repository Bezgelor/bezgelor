defmodule BezgelorProtocol.Packets.World.ServerTradeskillTalentList do
  @moduledoc """
  List of allocated tradeskill talents for a profession.

  ## Wire Format
  profession_id  : uint32
  total_points   : uint16
  talent_count   : uint8
  talents[]      : talent_data (repeated)

  talent_data:
    talent_id    : uint32
    points_spent : uint8
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:profession_id, :total_points, talents: []]

  @type talent :: %{talent_id: non_neg_integer(), points_spent: non_neg_integer()}

  @type t :: %__MODULE__{
          profession_id: non_neg_integer(),
          total_points: non_neg_integer(),
          talents: [talent()]
        }

  @impl true
  def opcode, do: :server_tradeskill_talent_list

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    talents = packet.talents || []

    writer =
      writer
      |> PacketWriter.write_u32(packet.profession_id)
      |> PacketWriter.write_u16(packet.total_points || 0)
      |> PacketWriter.write_u8(length(talents))

    writer =
      Enum.reduce(talents, writer, fn talent, w ->
        w
        |> PacketWriter.write_u32(talent.talent_id)
        |> PacketWriter.write_u8(talent.points_spent)
      end)

    {:ok, writer}
  end
end
