defmodule BezgelorProtocol.Packets.World.ServerTradeskillList do
  @moduledoc """
  List of character's tradeskill professions.

  ## Wire Format
  count         : uint8
  professions[] : profession_data (repeated)

  profession_data:
    profession_id   : uint32
    profession_type : uint8   - 0 = crafting, 1 = gathering
    skill_level     : uint16
    skill_xp        : uint32
    is_active       : uint8   - 1 = active, 0 = inactive
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct professions: []

  @type profession :: %{
          profession_id: non_neg_integer(),
          profession_type: :crafting | :gathering,
          skill_level: non_neg_integer(),
          skill_xp: non_neg_integer(),
          is_active: boolean()
        }

  @type t :: %__MODULE__{professions: [profession()]}

  @impl true
  def opcode, do: :server_tradeskill_list

  @impl true
  def write(%__MODULE__{professions: professions}, writer) do
    writer = PacketWriter.write_u8(writer, length(professions))

    writer =
      Enum.reduce(professions, writer, fn prof, w ->
        w
        |> PacketWriter.write_u32(prof.profession_id)
        |> PacketWriter.write_u8(profession_type_to_int(prof.profession_type))
        |> PacketWriter.write_u16(prof.skill_level)
        |> PacketWriter.write_u32(prof.skill_xp)
        |> PacketWriter.write_u8(if(prof.is_active, do: 1, else: 0))
      end)

    {:ok, writer}
  end

  defp profession_type_to_int(:crafting), do: 0
  defp profession_type_to_int(:gathering), do: 1
  defp profession_type_to_int(_), do: 0
end
