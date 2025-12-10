defmodule BezgelorProtocol.Packets.Realm.ServerRealmMessages do
  @moduledoc """
  Server broadcast messages shown to player.

  Can contain multiple indexed messages for server announcements.

  ## Packet Structure

  | Field | Type | Description |
  |-------|------|-------------|
  | count | uint32 | Number of messages |
  | messages[] | array | Array of messages |

  Each message:
  | Field | Type | Description |
  |-------|------|-------------|
  | index | uint32 | Message index |
  | message | wide_string | Message content |
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defmodule Message do
    @moduledoc "A single realm message."
    defstruct [:index, :message]

    @type t :: %__MODULE__{
            index: non_neg_integer(),
            message: String.t()
          }
  end

  defstruct messages: []

  @type t :: %__MODULE__{
          messages: [Message.t()]
        }

  @impl true
  def opcode, do: :server_realm_messages

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    writer = PacketWriter.write_uint32(writer, length(packet.messages))

    writer =
      Enum.reduce(packet.messages, writer, fn msg, w ->
        w
        |> PacketWriter.write_uint32(msg.index)
        |> PacketWriter.write_wide_string(msg.message)
      end)

    {:ok, writer}
  end
end
