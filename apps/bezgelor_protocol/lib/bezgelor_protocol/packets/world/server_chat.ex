defmodule BezgelorProtocol.Packets.World.ServerChat do
  @moduledoc """
  Chat message broadcast to clients.

  ## Overview

  Sent by server to deliver chat messages to players.
  Used for say, yell, whisper, emote, system messages, etc.

  ## Wire Format

  ```
  channel      : uint32  - Chat channel type
  sender_guid  : uint64  - Sender entity GUID (0 for system)
  sender_len   : uint32  - Sender name length
  sender       : wstring - Sender name (UTF-16LE)
  message_len  : uint32  - Message length
  message      : wstring - Message text (UTF-16LE)
  ```

  ## System Messages

  For system messages (channel = 3), sender_guid is 0 and
  sender name can be empty or a system identifier.
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter
  alias BezgelorCore.Chat

  defstruct [:channel, :sender_guid, :sender_name, :message]

  @type t :: %__MODULE__{
          channel: Chat.channel(),
          sender_guid: non_neg_integer(),
          sender_name: String.t(),
          message: String.t()
        }

  @impl true
  def opcode, do: :server_chat

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    channel_int = Chat.channel_to_int(packet.channel)

    writer =
      writer
      |> PacketWriter.write_u32(channel_int)
      |> PacketWriter.write_u64(packet.sender_guid || 0)
      |> PacketWriter.write_wide_string(packet.sender_name || "")
      |> PacketWriter.write_wide_string(packet.message || "")

    {:ok, writer}
  end

  @doc """
  Create a say message.
  """
  @spec say(non_neg_integer(), String.t(), String.t()) :: t()
  def say(sender_guid, sender_name, message) do
    %__MODULE__{
      channel: :say,
      sender_guid: sender_guid,
      sender_name: sender_name,
      message: message
    }
  end

  @doc """
  Create a yell message.
  """
  @spec yell(non_neg_integer(), String.t(), String.t()) :: t()
  def yell(sender_guid, sender_name, message) do
    %__MODULE__{
      channel: :yell,
      sender_guid: sender_guid,
      sender_name: sender_name,
      message: message
    }
  end

  @doc """
  Create a whisper message.
  """
  @spec whisper(non_neg_integer(), String.t(), String.t()) :: t()
  def whisper(sender_guid, sender_name, message) do
    %__MODULE__{
      channel: :whisper,
      sender_guid: sender_guid,
      sender_name: sender_name,
      message: message
    }
  end

  @doc """
  Create a system message.
  """
  @spec system(String.t()) :: t()
  def system(message) do
    %__MODULE__{
      channel: :system,
      sender_guid: 0,
      sender_name: "System",
      message: message
    }
  end

  @doc """
  Create an emote message.
  """
  @spec emote(non_neg_integer(), String.t(), String.t()) :: t()
  def emote(sender_guid, sender_name, message) do
    %__MODULE__{
      channel: :emote,
      sender_guid: sender_guid,
      sender_name: sender_name,
      message: message
    }
  end
end
