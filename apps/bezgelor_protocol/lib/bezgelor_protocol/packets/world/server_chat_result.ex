defmodule BezgelorProtocol.Packets.World.ServerChatResult do
  @moduledoc """
  Chat operation result/error packet.

  ## Overview

  Sent to inform the client about the result of a chat operation,
  typically used for error conditions like player not found for whisper.

  ## Wire Format

  ```
  result   : uint32 - Result code
  channel  : uint32 - Chat channel
  ```

  ## Result Codes

  | Code | Name | Description |
  |------|------|-------------|
  | 0 | success | Message sent successfully |
  | 1 | player_not_found | Whisper target not found |
  | 2 | player_offline | Target player is offline |
  | 3 | muted | Sender is muted |
  | 4 | channel_unavailable | Channel not available |
  | 5 | message_too_long | Message exceeds max length |
  | 6 | rate_limited | Too many messages |
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter
  alias BezgelorCore.Chat

  # Result codes
  @result_success 0
  @result_player_not_found 1
  @result_player_offline 2
  @result_muted 3
  @result_channel_unavailable 4
  @result_message_too_long 5
  @result_rate_limited 6

  defstruct [:result, :channel]

  @type result ::
          :success
          | :player_not_found
          | :player_offline
          | :muted
          | :channel_unavailable
          | :message_too_long
          | :rate_limited

  @type t :: %__MODULE__{
          result: result(),
          channel: Chat.channel()
        }

  @impl true
  def opcode, do: :server_chat_result

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    result_code = result_to_code(packet.result)
    channel_int = Chat.channel_to_int(packet.channel)

    writer =
      writer
      |> PacketWriter.write_uint32(result_code)
      |> PacketWriter.write_uint32(channel_int)

    {:ok, writer}
  end

  @doc "Convert result atom to integer code."
  @spec result_to_code(result()) :: non_neg_integer()
  def result_to_code(:success), do: @result_success
  def result_to_code(:player_not_found), do: @result_player_not_found
  def result_to_code(:player_offline), do: @result_player_offline
  def result_to_code(:muted), do: @result_muted
  def result_to_code(:channel_unavailable), do: @result_channel_unavailable
  def result_to_code(:message_too_long), do: @result_message_too_long
  def result_to_code(:rate_limited), do: @result_rate_limited
  def result_to_code(_), do: @result_success

  @doc "Convert integer code to result atom."
  @spec code_to_result(non_neg_integer()) :: result()
  def code_to_result(@result_success), do: :success
  def code_to_result(@result_player_not_found), do: :player_not_found
  def code_to_result(@result_player_offline), do: :player_offline
  def code_to_result(@result_muted), do: :muted
  def code_to_result(@result_channel_unavailable), do: :channel_unavailable
  def code_to_result(@result_message_too_long), do: :message_too_long
  def code_to_result(@result_rate_limited), do: :rate_limited
  def code_to_result(_), do: :success

  @doc "Create a success result."
  @spec success(Chat.channel()) :: t()
  def success(channel) do
    %__MODULE__{result: :success, channel: channel}
  end

  @doc "Create a player not found result."
  @spec player_not_found() :: t()
  def player_not_found do
    %__MODULE__{result: :player_not_found, channel: :whisper}
  end

  @doc "Create a channel unavailable result."
  @spec channel_unavailable(Chat.channel()) :: t()
  def channel_unavailable(channel) do
    %__MODULE__{result: :channel_unavailable, channel: channel}
  end
end
