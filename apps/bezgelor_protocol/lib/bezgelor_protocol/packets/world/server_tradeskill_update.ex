defmodule BezgelorProtocol.Packets.World.ServerTradeskillUpdate do
  @moduledoc """
  Update to a single tradeskill profession.

  ## Wire Format
  profession_id   : uint32
  profession_type : uint8
  skill_level     : uint16
  skill_xp        : uint32
  is_active       : uint8
  levels_gained   : uint8   - Number of levels gained (for notification)
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [
    :profession_id,
    :profession_type,
    :skill_level,
    :skill_xp,
    :is_active,
    levels_gained: 0
  ]

  @type t :: %__MODULE__{
          profession_id: non_neg_integer(),
          profession_type: :crafting | :gathering,
          skill_level: non_neg_integer(),
          skill_xp: non_neg_integer(),
          is_active: boolean(),
          levels_gained: non_neg_integer()
        }

  @impl true
  def opcode, do: :server_tradeskill_update

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_u32(packet.profession_id)
      |> PacketWriter.write_u8(profession_type_to_int(packet.profession_type))
      |> PacketWriter.write_u16(packet.skill_level)
      |> PacketWriter.write_u32(packet.skill_xp)
      |> PacketWriter.write_u8(if(packet.is_active, do: 1, else: 0))
      |> PacketWriter.write_u8(packet.levels_gained)

    {:ok, writer}
  end

  defp profession_type_to_int(:crafting), do: 0
  defp profession_type_to_int(:gathering), do: 1
  defp profession_type_to_int(_), do: 0
end
