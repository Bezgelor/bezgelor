defmodule BezgelorProtocol.Packets.World.ClientTradeskillTalentReset do
  @moduledoc """
  Client request to reset all talents for a profession.

  ## Wire Format
  profession_id : uint32  - Profession to reset talents for
  """
  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:profession_id]

  @type t :: %__MODULE__{
          profession_id: non_neg_integer()
        }

  @impl true
  def opcode, do: :client_tradeskill_talent_reset

  @impl true
  def read(reader) do
    with {:ok, profession_id, reader} <- PacketReader.read_uint32(reader) do
      {:ok, %__MODULE__{profession_id: profession_id}, reader}
    end
  end
end
