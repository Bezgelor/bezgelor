defmodule BezgelorProtocol.Packets.World.ClientCastSpellContinuous do
  @moduledoc """
  Continuous cast request from client.

  Used when the player enables continuous casting in settings.
  """

  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:bag_index, :guid, :button_pressed]

  @type t :: %__MODULE__{
          bag_index: non_neg_integer(),
          guid: non_neg_integer(),
          button_pressed: boolean()
        }

  @impl true
  def opcode, do: :client_cast_spell_continuous

  @impl true
  def read(reader) do
    with {:ok, bag_index, reader} <- PacketReader.read_uint16(reader),
         {:ok, guid, reader} <- PacketReader.read_uint32(reader),
         {:ok, button_pressed, reader} <- PacketReader.read_bit(reader) do
      {:ok,
       %__MODULE__{
         bag_index: bag_index,
         guid: guid,
         button_pressed: button_pressed == 1
       }, reader}
    end
  end
end
