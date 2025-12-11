defmodule BezgelorProtocol.Packets.World.ClientTradeskillTalentAllocate do
  @moduledoc """
  Client request to allocate a tech tree talent point.

  ## Wire Format
  profession_id : uint32  - Profession to allocate for
  talent_id     : uint32  - Talent node to invest in
  """
  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:profession_id, :talent_id]

  @type t :: %__MODULE__{
          profession_id: non_neg_integer(),
          talent_id: non_neg_integer()
        }

  @impl true
  def opcode, do: :client_tradeskill_talent_allocate

  @impl true
  def read(reader) do
    with {:ok, profession_id, reader} <- PacketReader.read_uint32(reader),
         {:ok, talent_id, reader} <- PacketReader.read_uint32(reader) do
      packet = %__MODULE__{
        profession_id: profession_id,
        talent_id: talent_id
      }

      {:ok, packet, reader}
    end
  end
end
