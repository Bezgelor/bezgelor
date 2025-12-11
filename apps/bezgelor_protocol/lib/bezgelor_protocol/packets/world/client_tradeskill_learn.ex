defmodule BezgelorProtocol.Packets.World.ClientTradeskillLearn do
  @moduledoc """
  Client request to learn a new tradeskill profession.

  ## Wire Format
  profession_id   : uint32  - ID of the profession to learn
  profession_type : uint8   - 0 = crafting, 1 = gathering
  """
  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:profession_id, :profession_type]

  @type t :: %__MODULE__{
          profession_id: non_neg_integer(),
          profession_type: :crafting | :gathering
        }

  @impl true
  def opcode, do: :client_tradeskill_learn

  @impl true
  def read(reader) do
    with {:ok, profession_id, reader} <- PacketReader.read_uint32(reader),
         {:ok, type_byte, reader} <- PacketReader.read_byte(reader) do
      packet = %__MODULE__{
        profession_id: profession_id,
        profession_type: int_to_profession_type(type_byte)
      }

      {:ok, packet, reader}
    end
  end

  defp int_to_profession_type(0), do: :crafting
  defp int_to_profession_type(1), do: :gathering
  defp int_to_profession_type(_), do: :crafting
end
