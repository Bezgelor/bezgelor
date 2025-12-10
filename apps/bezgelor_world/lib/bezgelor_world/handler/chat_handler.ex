defmodule BezgelorWorld.Handler.ChatHandler do
  @moduledoc """
  Handler for ClientChat packets.

  ## Overview

  Processes chat messages, parses commands, and routes messages
  to appropriate channels/recipients.

  ## Flow

  1. Parse ClientChat packet
  2. Validate player is in world
  3. Check for commands (starting with /)
  4. Process based on channel type
  5. Broadcast to recipients or return error

  ## Commands

  Messages starting with "/" are parsed as commands:
  - /say, /yell, /whisper, /emote
  - /who, /loc
  """

  @behaviour BezgelorProtocol.Handler

  alias BezgelorProtocol.Packets.World.{ClientChat, ServerChat, ServerChatResult}
  alias BezgelorProtocol.{PacketReader, PacketWriter}
  alias BezgelorCore.{Chat, ChatCommand}
  alias BezgelorWorld.WorldManager

  require Logger

  @impl true
  def handle(payload, state) do
    reader = PacketReader.new(payload)

    case ClientChat.read(reader) do
      {:ok, packet, _reader} ->
        process_chat(packet, state)

      {:error, reason} ->
        Logger.warning("Failed to parse ClientChat: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp process_chat(packet, state) do
    unless state.session_data[:in_world] do
      Logger.warning("Chat received before player entered world")
      {:error, :not_in_world}
    else
      # Check if it's a command
      case ChatCommand.parse(packet.message) do
        {:chat, channel, message} ->
          handle_chat(channel, message, state)

        {:whisper, target, message} ->
          handle_whisper(target, message, state)

        {:action, action, args} ->
          handle_action(action, args, state)

        {:error, reason} ->
          send_error(reason, state)
      end
    end
  end

  # Handle say/yell/emote chat
  defp handle_chat(channel, message, state) do
    unless Chat.available?(channel) do
      send_chat_result(:channel_unavailable, channel, state)
    else
      if String.length(message) > Chat.max_message_length() do
        send_chat_result(:message_too_long, channel, state)
      else
        do_broadcast_chat(channel, message, state)
      end
    end
  end

  defp do_broadcast_chat(channel, message, state) do
    sender_guid = state.session_data[:entity_guid]
    sender_name = state.session_data[:character_name]
    entity = state.session_data[:entity]

    Logger.info("[#{channel}] #{sender_name}: #{message}")

    # Broadcast via WorldManager
    case channel do
      :whisper ->
        # Whisper is handled separately
        {:ok, state}

      _ ->
        # Local or zone chat - broadcast to nearby
        position = if entity, do: entity.position, else: {0.0, 0.0, 0.0}
        WorldManager.broadcast_chat(sender_guid, sender_name, channel, message, position)

        # Echo back to sender
        chat_packet = %ServerChat{
          channel: channel,
          sender_guid: sender_guid,
          sender_name: sender_name,
          message: message
        }

        send_packet(:server_chat, chat_packet, state)
    end
  end

  # Handle whisper
  defp handle_whisper(target, message, state) do
    sender_guid = state.session_data[:entity_guid]
    sender_name = state.session_data[:character_name]

    Logger.info("[whisper] #{sender_name} -> #{target}: #{message}")

    case WorldManager.send_whisper(sender_guid, sender_name, target, message) do
      :ok ->
        # Echo whisper back to sender (so they see it in chat)
        chat_packet = %ServerChat{
          channel: :whisper,
          sender_guid: sender_guid,
          sender_name: "To #{target}",
          message: message
        }

        send_packet(:server_chat, chat_packet, state)

      {:error, :player_not_found} ->
        send_chat_result(:player_not_found, :whisper, state)

      {:error, :player_offline} ->
        send_chat_result(:player_offline, :whisper, state)
    end
  end

  # Handle action commands
  defp handle_action(:who, _args, state) do
    # List nearby players
    sessions = WorldManager.list_sessions()
    count = map_size(sessions)

    system_msg = ServerChat.system("#{count} player(s) online")
    send_packet(:server_chat, system_msg, state)
  end

  defp handle_action(:location, _args, state) do
    entity = state.session_data[:entity]

    if entity do
      {x, y, z} = entity.position
      msg = "Location: World #{entity.world_id}, Zone #{entity.zone_id} at (#{Float.round(x, 1)}, #{Float.round(y, 1)}, #{Float.round(z, 1)})"
      system_msg = ServerChat.system(msg)
      send_packet(:server_chat, system_msg, state)
    else
      system_msg = ServerChat.system("Location unavailable")
      send_packet(:server_chat, system_msg, state)
    end
  end

  defp handle_action(action, _args, state) do
    system_msg = ServerChat.system("Unknown command: /#{action}")
    send_packet(:server_chat, system_msg, state)
  end

  # Send error for unknown command
  defp send_error({:unknown_command, cmd}, state) do
    system_msg = ServerChat.system("Unknown command: /#{cmd}")
    send_packet(:server_chat, system_msg, state)
  end

  defp send_error(:whisper_no_target, state) do
    system_msg = ServerChat.system("Usage: /whisper <player> <message>")
    send_packet(:server_chat, system_msg, state)
  end

  defp send_error(:whisper_no_message, state) do
    system_msg = ServerChat.system("Usage: /whisper <player> <message>")
    send_packet(:server_chat, system_msg, state)
  end

  defp send_error(_reason, state) do
    send_chat_result(:channel_unavailable, :say, state)
  end

  # Send chat result
  defp send_chat_result(result, channel, state) do
    result_packet = %ServerChatResult{result: result, channel: channel}
    send_packet(:server_chat_result, result_packet, state)
  end

  # Helper to encode and send packet
  defp send_packet(opcode, packet, state) do
    writer = PacketWriter.new()

    {:ok, writer} =
      case opcode do
        :server_chat -> ServerChat.write(packet, writer)
        :server_chat_result -> ServerChatResult.write(packet, writer)
      end

    packet_data = PacketWriter.to_binary(writer)
    {:reply, opcode, packet_data, state}
  end
end
