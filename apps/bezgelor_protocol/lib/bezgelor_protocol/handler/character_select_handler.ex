defmodule BezgelorProtocol.Handler.CharacterSelectHandler do
  @moduledoc """
  Handler for ClientCharacterSelect packets.

  Validates character ownership and initiates world entry.
  Sends ServerWorldEnter with character spawn location.

  ## Flow

  1. Validate character belongs to authenticated account
  2. Update character's last_online timestamp
  3. Get spawn location (saved position or default)
  4. Send ServerWorldEnter packet
  5. Client loads world and sends ClientEnteredWorld
  """

  @behaviour BezgelorProtocol.Handler

  alias BezgelorProtocol.Packets.World.{ClientCharacterSelect, ServerWorldEnter}
  alias BezgelorProtocol.{PacketReader, PacketWriter}
  alias BezgelorDb.Characters
  alias BezgelorCore.Zone

  require Logger

  @impl true
  def handle(payload, state) do
    reader = PacketReader.new(payload)

    case ClientCharacterSelect.read(reader) do
      {:ok, packet, _reader} ->
        select_character(packet, state)

      {:error, reason} ->
        Logger.warning("Failed to parse ClientCharacterSelect: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp select_character(packet, state) do
    account_id = state.session_data[:account_id]

    if is_nil(account_id) do
      Logger.warning("Character select attempted without authenticated account")
      {:error, :not_authenticated}
    else
      do_select(account_id, packet.character_id, state)
    end
  end

  defp do_select(account_id, character_id, state) do
    case Characters.get_character(account_id, character_id) do
      nil ->
        Logger.warning("Character #{character_id} not found or doesn't belong to account #{account_id}")
        {:error, :character_not_found}

      character ->
        # Update last login time
        {:ok, _updated} = Characters.update_last_online(character)

        # Get spawn location
        spawn = Zone.spawn_location(character)

        # Build world enter packet
        world_enter = ServerWorldEnter.from_spawn(character.id, spawn)

        # Encode packet
        writer = PacketWriter.new()
        {:ok, writer} = ServerWorldEnter.write(world_enter, writer)
        packet_data = PacketWriter.to_binary(writer)

        # Store character info in session for WorldEntryHandler
        state = put_in(state.session_data[:character_id], character.id)
        state = put_in(state.session_data[:character_name], character.name)
        state = put_in(state.session_data[:character], character)
        state = put_in(state.session_data[:spawn_location], spawn)

        Logger.info("Account #{account_id} entering world with character '#{character.name}' (ID: #{character.id})")

        {:reply, :server_world_enter, packet_data, state}
    end
  end
end
