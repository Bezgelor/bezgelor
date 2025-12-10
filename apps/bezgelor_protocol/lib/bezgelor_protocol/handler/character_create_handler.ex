defmodule BezgelorProtocol.Handler.CharacterCreateHandler do
  @moduledoc """
  Handler for ClientCharacterCreate packets.

  Validates character creation parameters and creates the character
  in the database.

  ## Validation

  - Name format (3-24 characters, alphanumeric + spaces)
  - Name availability (case-insensitive)
  - Race/faction compatibility (Exile vs Dominion)
  - Character slot limit (12 per account)
  """

  @behaviour BezgelorProtocol.Handler

  alias BezgelorProtocol.Packets.World.{
    ClientCharacterCreate,
    ServerCharacterCreate
  }

  alias BezgelorProtocol.{PacketReader, PacketWriter}
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
    # Derive faction from race
    faction_id = faction_for_race(packet.race)

    character_attrs = %{
      name: packet.name,
      sex: packet.sex,
      race: packet.race,
      class: packet.class,
      faction_id: faction_id,
      world_id: @default_world_id,
      world_zone_id: @default_zone_id,
      active_path: packet.path
    }

    appearance_attrs = ClientCharacterCreate.appearance_to_map(packet.appearance)

    case Characters.create_character(account_id, character_attrs, appearance_attrs) do
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

  # Derive faction ID from race
  # Exile races (166): Human (0), Mordesh (1), Granok (3), Aurin (4)
  # Dominion races (167): Draken (2), Chua (5), Mechari (12), Cassian (13)
  defp faction_for_race(race) when race in [0, 1, 3, 4], do: 166
  defp faction_for_race(race) when race in [2, 5, 12, 13], do: 167
  defp faction_for_race(_), do: 166

  defp encode_packet(%ServerCharacterCreate{} = packet) do
    writer = PacketWriter.new()
    {:ok, writer} = ServerCharacterCreate.write(packet, writer)
    PacketWriter.to_binary(writer)
  end
end
