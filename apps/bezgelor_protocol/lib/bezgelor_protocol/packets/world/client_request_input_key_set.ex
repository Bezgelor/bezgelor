defmodule BezgelorProtocol.Packets.World.ClientRequestInputKeySet do
  @moduledoc """
  Client request for keybinding data.

  Sent when the client needs keybinding configuration.
  If character_id is 0, requesting account-level keybindings.
  If character_id is non-zero, requesting character-specific keybindings.

  ## Wire Format
  character_id : uint64
  """

  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct character_id: 0

  @type t :: %__MODULE__{
          character_id: non_neg_integer()
        }

  @impl true
  def opcode, do: :client_request_input_key_set

  @impl true
  def read(reader) do
    {character_id, reader} = PacketReader.read_uint64(reader)

    packet = %__MODULE__{
      character_id: character_id
    }

    {:ok, packet, reader}
  end
end
