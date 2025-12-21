defmodule BezgelorProtocol.Packets.World.ServerActionSetClearCache do
  @moduledoc """
  ServerActionSetClearCache packet (0x00B2).

  Sent before ServerActionSet when applying LAS changes.
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct generate_chat_log_message: true

  @type t :: %__MODULE__{
          generate_chat_log_message: boolean()
        }

  @impl true
  def opcode, do: :server_action_set_clear_cache

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_bits(if(packet.generate_chat_log_message, do: 1, else: 0), 1)
      |> PacketWriter.flush_bits()

    {:ok, writer}
  end
end
