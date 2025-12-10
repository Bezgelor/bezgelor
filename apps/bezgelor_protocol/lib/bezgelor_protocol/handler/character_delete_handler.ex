defmodule BezgelorProtocol.Handler.CharacterDeleteHandler do
  @moduledoc """
  Handler for ClientCharacterDelete packets.

  Soft-deletes a character (marks deleted, frees name).

  ## Validation

  - Character must belong to the authenticated account
  - Character will be soft-deleted (can be restored by admin)
  - Name is freed for reuse immediately
  """

  @behaviour BezgelorProtocol.Handler

  alias BezgelorProtocol.Packets.World.{
    ClientCharacterDelete,
    ServerCharacterList
  }

  alias BezgelorProtocol.{PacketReader, PacketWriter}
  alias BezgelorDb.Characters

  require Logger

  @impl true
  def handle(payload, state) do
    reader = PacketReader.new(payload)

    case ClientCharacterDelete.read(reader) do
      {:ok, packet, _reader} ->
        delete_character(packet, state)

      {:error, reason} ->
        Logger.warning("Failed to parse ClientCharacterDelete: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp delete_character(packet, state) do
    account_id = state.session_data[:account_id]

    if is_nil(account_id) do
      Logger.warning("Character delete attempted without authenticated account")
      {:error, :not_authenticated}
    else
      do_delete(account_id, packet.character_id, state)
    end
  end

  defp do_delete(account_id, character_id, state) do
    case Characters.delete_character(account_id, character_id) do
      {:ok, deleted_char} ->
        Logger.info("Deleted character '#{deleted_char.original_name}' (ID: #{character_id}) for account #{account_id}")

        # Send updated character list
        characters = Characters.list_characters(account_id)
        response = ServerCharacterList.from_characters(characters)

        {:reply, :server_character_list, encode_packet(response), state}

      {:error, :not_found} ->
        Logger.warning("Attempted to delete non-existent character #{character_id} for account #{account_id}")
        {:error, :character_not_found}

      {:error, reason} ->
        Logger.error("Character deletion failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp encode_packet(%ServerCharacterList{} = packet) do
    writer = PacketWriter.new()
    {:ok, writer} = ServerCharacterList.write(packet, writer)
    PacketWriter.to_binary(writer)
  end
end
