defmodule BezgelorProtocol.Packets.World.ClientPetSummon do
  @moduledoc """
  Pet summon request from client.

  ## Wire Format
  pet_id : uint32 - Pet to summon from collection
  """

  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:pet_id]

  @type t :: %__MODULE__{
          pet_id: non_neg_integer()
        }

  @impl true
  def opcode, do: :client_pet_summon

  @impl true
  def read(reader) do
    with {:ok, pet_id, reader} <- PacketReader.read_uint32(reader) do
      {:ok, %__MODULE__{pet_id: pet_id}, reader}
    end
  end
end
