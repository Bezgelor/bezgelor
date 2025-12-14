defmodule BezgelorProtocol.Handler.CharacterCreateHandler do
  @moduledoc """
  Handler for ClientCharacterCreate packets.

  Validates character creation parameters and creates the character
  in the database.

  ## Overview

  The client sends a CharacterCreationId which references the CharacterCreation
  game table. This table contains the race, class, sex, faction, and starting
  items for the character template. Customizations are applied on top.

  ## Validation

  - Name format (3-24 characters, alphanumeric + spaces)
  - Name availability (case-insensitive)
  - Valid character creation template
  - Character slot limit (12 per account)
  """

  @behaviour BezgelorProtocol.Handler

  alias BezgelorProtocol.Packets.World.{
    ClientCharacterCreate,
    ServerCharacterCreate
  }

  alias BezgelorProtocol.{PacketReader, PacketWriter}
  alias BezgelorData.Store
  alias BezgelorDb.Characters

  require Logger

  # Starting location (default spawn point)
  @default_world_id 870
  @default_zone_id 1

  @impl true
  def handle(payload, state) do
    reader = PacketReader.new(payload)

    case ClientCharacterCreate.read(reader) do
      {:ok, packet, _reader} ->
        create_character(packet, state)

      {:error, reason} ->
        Logger.warning("Failed to parse ClientCharacterCreate: #{inspect(reason)}")
        response = ServerCharacterCreate.failure(:server_error)
        {:reply, :server_character_create, encode_packet(response), state}
    end
  end

  defp create_character(packet, state) do
    account_id = state.session_data[:account_id]

    if is_nil(account_id) do
      Logger.warning("Character create attempted without authenticated account")
      response = ServerCharacterCreate.failure(:server_error)
      {:reply, :server_character_create, encode_packet(response), state}
    else
      do_create(account_id, packet, state)
    end
  end

  defp do_create(account_id, packet, state) do
    # Look up the character creation template
    case Store.get_character_creation(packet.character_creation_id) do
      {:ok, creation_entry} ->
        create_from_template(account_id, packet, creation_entry, state)

      :error ->
        Logger.warning("Invalid character creation ID: #{packet.character_creation_id}")
        response = ServerCharacterCreate.failure(:server_error)
        {:reply, :server_character_create, encode_packet(response), state}
    end
  end

  defp create_from_template(account_id, packet, creation_entry, state) do
    # Extract race, class, sex, faction from the creation template
    # The JSON uses string keys like "raceId", "classId", etc.
    race = Map.get(creation_entry, "raceId") || Map.get(creation_entry, :raceId)
    class = Map.get(creation_entry, "classId") || Map.get(creation_entry, :classId)
    sex = Map.get(creation_entry, "sex") || Map.get(creation_entry, :sex)
    faction_id = Map.get(creation_entry, "factionId") || Map.get(creation_entry, :factionId)

    Logger.debug("Creating character from template: race=#{race}, class=#{class}, sex=#{sex}, faction=#{faction_id}")

    character_attrs = %{
      name: packet.name,
      sex: sex,
      race: race,
      class: class,
      faction_id: faction_id,
      world_id: @default_world_id,
      world_zone_id: @default_zone_id,
      active_path: packet.path
    }

    # Convert customization data
    customization_attrs = ClientCharacterCreate.customization_to_map(packet)

    case Characters.create_character(account_id, character_attrs, customization_attrs) do
      {:ok, character} ->
        Logger.info("Created character '#{character.name}' (ID: #{character.id}) for account #{account_id}")
        response = ServerCharacterCreate.success(character.id)
        {:reply, :server_character_create, encode_packet(response), state}

      {:error, :name_taken} ->
        response = ServerCharacterCreate.failure(:name_taken)
        {:reply, :server_character_create, encode_packet(response), state}

      {:error, :invalid_name} ->
        response = ServerCharacterCreate.failure(:invalid_name)
        {:reply, :server_character_create, encode_packet(response), state}

      {:error, :max_characters} ->
        response = ServerCharacterCreate.failure(:max_characters)
        {:reply, :server_character_create, encode_packet(response), state}

      {:error, :invalid_faction} ->
        response = ServerCharacterCreate.failure(:invalid_faction)
        {:reply, :server_character_create, encode_packet(response), state}

      {:error, reason} ->
        Logger.error("Character creation failed: #{inspect(reason)}")
        response = ServerCharacterCreate.failure(:server_error)
        {:reply, :server_character_create, encode_packet(response), state}
    end
  end

  defp encode_packet(%ServerCharacterCreate{} = packet) do
    writer = PacketWriter.new()
    {:ok, writer} = ServerCharacterCreate.write(packet, writer)
    PacketWriter.to_binary(writer)
  end
end
