defmodule BezgelorProtocol.Packets.World.ClientChat do
  @moduledoc """
  Chat message from client.

  ## Overview

  Sent when a player sends a chat message or command.
  The target field is only used for whisper messages.

  ## Wire Format

  ```
  channel      : uint32  - Chat channel type
  target_len   : uint32  - Target name length (for whisper)
  target       : wstring - Target player name (UTF-16LE)
  message_len  : uint32  - Message length
  message      : wstring - Message text (UTF-16LE)
  ```

  ## Channel Types

  | Channel | Value | Description |
  |---------|-------|-------------|
  | Say | 0 | Local chat |
  | Yell | 1 | Loud local chat |
  | Whisper | 2 | Private message |
  | Emote | 4 | Character emotes |
  | Zone | 7 | Zone-wide chat |
  """

  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader
  alias BezgelorCore.Chat

  defstruct [:channel, :target, :message]

  @type t :: %__MODULE__{
          channel: Chat.channel(),
          target: String.t() | nil,
          message: String.t()
        }

  @impl true
  def opcode, do: :client_chat

  @impl true
  def read(reader) do
    with {:ok, channel_int, reader} <- PacketReader.read_uint32(reader),
         {:ok, target, reader} <- PacketReader.read_wide_string(reader),
         {:ok, message, reader} <- PacketReader.read_wide_string(reader) do
      channel = Chat.int_to_channel(channel_int)
      target = if target == "", do: nil, else: target

      {:ok,
       %__MODULE__{
         channel: channel,
         target: target,
         message: message
       }, reader}
    end
  end
end
