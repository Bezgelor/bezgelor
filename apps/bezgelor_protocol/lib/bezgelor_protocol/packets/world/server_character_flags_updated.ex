defmodule BezgelorProtocol.Packets.World.ServerCharacterFlagsUpdated do
  @moduledoc """
  Server packet to update character flags (holomark settings, etc).

  This packet MUST be sent before OnAddToMap (ServerEntityCreate).
  The client UI initializes Holomark checkboxes during OnDocumentReady.

  ## Wire Format (from NexusForever)

  ```
  flags : 32 bits - CharacterFlag enum
  ```
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct flags: 0

  @type t :: %__MODULE__{
          flags: non_neg_integer()
        }

  @impl true
  def opcode, do: :server_character_flags_updated

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_bits(packet.flags, 32)
      |> PacketWriter.flush_bits()

    {:ok, writer}
  end
end
