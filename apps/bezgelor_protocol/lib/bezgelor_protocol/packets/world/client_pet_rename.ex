defmodule BezgelorProtocol.Packets.World.ClientPetRename do
  @moduledoc """
  Pet rename request from client.

  ## Wire Format
  nickname : wstring - New pet nickname (max 20 chars)
  """

  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:nickname]

  @type t :: %__MODULE__{
          nickname: String.t()
        }

  @impl true
  def opcode, do: :client_pet_rename

  @impl true
  def read(reader) do
    with {:ok, nickname, reader} <- PacketReader.read_wide_string(reader) do
      {:ok, %__MODULE__{nickname: nickname}, reader}
    end
  end
end
