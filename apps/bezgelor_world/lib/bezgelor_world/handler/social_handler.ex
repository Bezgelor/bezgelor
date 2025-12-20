defmodule BezgelorWorld.Handler.SocialHandler do
  @moduledoc """
  Handler for social packets (friends, ignores).

  ## Packets Handled
  - ClientAddFriend
  - ClientRemoveFriend
  - ClientAddIgnore
  - ClientRemoveIgnore
  """
  @behaviour BezgelorProtocol.Handler

  require Logger

  alias BezgelorProtocol.PacketReader
  alias BezgelorProtocol.PacketWriter

  alias BezgelorProtocol.Packets.World.{
    ClientAddFriend,
    ClientRemoveFriend,
    ClientAddIgnore,
    ClientRemoveIgnore,
    ServerFriendList,
    ServerIgnoreList,
    ServerSocialResult
  }

  alias BezgelorDb.{Characters, Social}
  alias BezgelorWorld.WorldManager

  @impl true
  def handle(payload, state) do
    reader = PacketReader.new(payload)

    # Try each packet type
    with {:error, _} <- try_add_friend(reader, state),
         {:error, _} <- try_remove_friend(reader, state),
         {:error, _} <- try_add_ignore(reader, state),
         {:error, _} <- try_remove_ignore(reader, state) do
      {:error, :unknown_social_packet}
    end
  end

  # Add friend

  defp try_add_friend(reader, state) do
    case ClientAddFriend.read(reader) do
      {:ok, packet, _} -> handle_add_friend(packet, state)
      error -> error
    end
  end

  defp handle_add_friend(packet, state) do
    character_id = state.session_data[:character_id]

    case Characters.get_character_by_name(packet.target_name) do
      nil ->
        send_result(:player_not_found, :add_friend, packet.target_name, state)

      target ->
        case Social.add_friend(character_id, target.id, packet.note || "") do
          {:ok, _} ->
            Logger.debug("Character #{character_id} added friend: #{packet.target_name}")
            send_result(:success, :add_friend, packet.target_name, state)

          {:error, :friend_list_full} ->
            send_result(:list_full, :add_friend, packet.target_name, state)

          {:error, :cannot_friend_self} ->
            send_result(:cannot_add_self, :add_friend, packet.target_name, state)

          {:error, _} ->
            send_result(:already_friend, :add_friend, packet.target_name, state)
        end
    end
  end

  # Remove friend

  defp try_remove_friend(reader, state) do
    case ClientRemoveFriend.read(reader) do
      {:ok, packet, _} -> handle_remove_friend(packet, state)
      error -> error
    end
  end

  defp handle_remove_friend(packet, state) do
    character_id = state.session_data[:character_id]

    case Social.remove_friend(character_id, packet.friend_id) do
      {:ok, _} ->
        Logger.debug("Character #{character_id} removed friend: #{packet.friend_id}")
        send_result(:success, :remove_friend, "", state)

      {:error, :not_found} ->
        send_result(:not_found, :remove_friend, "", state)
    end
  end

  # Add ignore

  defp try_add_ignore(reader, state) do
    case ClientAddIgnore.read(reader) do
      {:ok, packet, _} -> handle_add_ignore(packet, state)
      error -> error
    end
  end

  defp handle_add_ignore(packet, state) do
    character_id = state.session_data[:character_id]

    case Characters.get_character_by_name(packet.target_name) do
      nil ->
        send_result(:player_not_found, :add_ignore, packet.target_name, state)

      target ->
        case Social.add_ignore(character_id, target.id) do
          {:ok, _} ->
            Logger.debug("Character #{character_id} added ignore: #{packet.target_name}")
            send_result(:success, :add_ignore, packet.target_name, state)

          {:error, :ignore_list_full} ->
            send_result(:list_full, :add_ignore, packet.target_name, state)

          {:error, :cannot_ignore_self} ->
            send_result(:cannot_add_self, :add_ignore, packet.target_name, state)

          {:error, _} ->
            send_result(:already_friend, :add_ignore, packet.target_name, state)
        end
    end
  end

  # Remove ignore

  defp try_remove_ignore(reader, state) do
    case ClientRemoveIgnore.read(reader) do
      {:ok, packet, _} -> handle_remove_ignore(packet, state)
      error -> error
    end
  end

  defp handle_remove_ignore(packet, state) do
    character_id = state.session_data[:character_id]

    case Social.remove_ignore(character_id, packet.ignore_id) do
      {:ok, _} ->
        Logger.debug("Character #{character_id} removed ignore: #{packet.ignore_id}")
        send_result(:success, :remove_ignore, "", state)

      {:error, :not_found} ->
        send_result(:not_found, :remove_ignore, "", state)
    end
  end

  # Helper to send friend list on login

  @doc "Send friend list to a character. Called on world entry."
  def send_friend_list(character_id, state) do
    friends = Social.list_friends(character_id)

    friend_data =
      Enum.map(friends, fn friend ->
        char = friend.friend_character
        online_session = WorldManager.get_session_by_character(char.id)

        %{
          character_id: char.id,
          name: char.name,
          level: char.level,
          class: char.class,
          online: online_session != nil,
          zone_id: if(online_session, do: online_session.zone_id, else: 0),
          note: friend.note
        }
      end)

    packet = %ServerFriendList{friends: friend_data}
    writer = PacketWriter.new()
    {:ok, writer} = ServerFriendList.write(packet, writer)
    packet_data = PacketWriter.to_binary(writer)

    {:reply, :server_friend_list, packet_data, state}
  end

  @doc "Send ignore list to a character. Called on world entry."
  def send_ignore_list(character_id, state) do
    ignores = Social.list_ignores(character_id)

    ignore_data =
      Enum.map(ignores, fn ignore ->
        char = ignore.ignored_character

        %{
          character_id: char.id,
          name: char.name
        }
      end)

    packet = %ServerIgnoreList{ignores: ignore_data}
    writer = PacketWriter.new()
    {:ok, writer} = ServerIgnoreList.write(packet, writer)
    packet_data = PacketWriter.to_binary(writer)

    {:reply, :server_ignore_list, packet_data, state}
  end

  # Private helpers

  defp send_result(result, operation, target_name, state) do
    packet = %ServerSocialResult{
      result: result,
      operation: operation,
      target_name: target_name
    }

    writer = PacketWriter.new()
    {:ok, writer} = ServerSocialResult.write(packet, writer)
    packet_data = PacketWriter.to_binary(writer)

    {:reply, :server_social_result, packet_data, state}
  end
end
