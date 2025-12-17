defmodule BezgelorProtocol.Packets.World.ServerChatNpc do
  @moduledoc """
  Server packet for NPC chat using localized text IDs.

  ## Overview

  More efficient than ServerChat for NPC dialogue since the client
  resolves text locally without sending strings over the network.

  ## Wire Format (bit-packed)

  ```
  channel_type       : 14 bits - ChatChannelType (NPCSay=24, NPCYell=25, NPCWhisper=26)
  chat_id            : 64 bits - always 0
  unit_name_text_id  : 21 bits - localizedTextIdName from creature data
  message_text_id    : 21 bits - localizedTextId from gossip entry
  ```

  Opcode: 0x01C6
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  # Chat channel types for NPCs
  @npc_say 24
  @npc_yell 25
  @npc_whisper 26

  @type t :: %__MODULE__{
          channel_type: non_neg_integer(),
          chat_id: non_neg_integer(),
          unit_name_text_id: non_neg_integer(),
          message_text_id: non_neg_integer()
        }

  defstruct channel_type: @npc_say,
            chat_id: 0,
            unit_name_text_id: 0,
            message_text_id: 0

  def npc_say, do: @npc_say
  def npc_yell, do: @npc_yell
  def npc_whisper, do: @npc_whisper

  @impl true
  def opcode, do: :server_chat_npc

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_bits(packet.channel_type, 14)
      |> PacketWriter.write_u64(packet.chat_id)
      |> PacketWriter.write_bits(packet.unit_name_text_id, 21)
      |> PacketWriter.write_bits(packet.message_text_id, 21)
      |> PacketWriter.flush_bits()

    {:ok, writer}
  end
end
