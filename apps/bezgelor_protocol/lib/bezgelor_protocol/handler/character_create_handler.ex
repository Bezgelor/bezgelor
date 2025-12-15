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
  alias BezgelorDb.{Characters, Inventory}
  alias BezgelorCore.Zone

  require Logger

  @impl true
  def handle(payload, state) do
    reader = PacketReader.new(payload)

    case ClientCharacterCreate.read(reader) do
      {:ok, packet, _reader} ->
        create_character(packet, state)

      {:error, reason} ->
        Logger.warning("Failed to parse ClientCharacterCreate: #{inspect(reason)}")
        response = ServerCharacterCreate.failure(:server_error)
        {:reply_world_encrypted, :server_character_create, encode_packet(response), state}
    end
  end

  defp create_character(packet, state) do
    account_id = state.session_data[:account_id]

    if is_nil(account_id) do
      Logger.warning("Character create attempted without authenticated account")
      response = ServerCharacterCreate.failure(:server_error)
      {:reply_world_encrypted, :server_character_create, encode_packet(response), state}
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
        {:reply_world_encrypted, :server_character_create, encode_packet(response), state}
    end
  end

  defp create_from_template(account_id, packet, creation_entry, state) do
    # Extract race, class, sex, faction from the creation template
    # The JSON uses string keys like "raceId", "classId", etc.
    race = Map.get(creation_entry, "raceId") || Map.get(creation_entry, :raceId)
    class = Map.get(creation_entry, "classId") || Map.get(creation_entry, :classId)
    sex = Map.get(creation_entry, "sex") || Map.get(creation_entry, :sex)
    faction_id = Map.get(creation_entry, "factionId") || Map.get(creation_entry, :factionId)

    # Get creation start type (0=Arkship, 3=Nexus/Veteran, 4=PreTutorial/Novice, 5=Level50)
    creation_start =
      Map.get(creation_entry, "characterCreationStartEnum") ||
        Map.get(creation_entry, :characterCreationStartEnum) ||
        4

    # Get starting location based on creation type and faction
    spawn = Zone.starting_location(creation_start, faction_id)

    # Get current realm ID
    realm_id = Application.get_env(:bezgelor_realm, :realm_id, 1)

    Logger.debug(
      "Creating character from template: race=#{race}, class=#{class}, sex=#{sex}, " <>
        "faction=#{faction_id}, creation_start=#{creation_start}, world_id=#{spawn.world_id}, realm_id=#{realm_id}"
    )

    character_attrs = %{
      name: packet.name,
      sex: sex,
      race: race,
      class: class,
      faction_id: faction_id,
      realm_id: realm_id,
      world_id: spawn.world_id,
      world_zone_id: spawn.zone_id,
      location_x: elem(spawn.position, 0),
      location_y: elem(spawn.position, 1),
      location_z: elem(spawn.position, 2),
      rotation_x: elem(spawn.rotation, 0),
      rotation_y: elem(spawn.rotation, 1),
      rotation_z: elem(spawn.rotation, 2),
      active_path: packet.path
    }

    # Convert customization data
    customization_attrs = ClientCharacterCreate.customization_to_map(packet)

    # Compute appearance visuals from labels/values using CharacterCustomization table
    # This converts the customization options to actual body slot/displayId pairs
    visuals = compute_visuals(race, sex, packet.labels, packet.values)
    customization_attrs = Map.put(customization_attrs, :visuals, visuals)

    case Characters.create_character(account_id, character_attrs, customization_attrs) do
      {:ok, character} ->
        Logger.info("Created character '#{character.name}' (ID: #{character.id}) for account #{account_id} in world #{character.world_id}")

        # Initialize inventory bags and add starting gear
        Inventory.init_bags(character.id)
        add_starting_gear(character.id, creation_entry)

        response = ServerCharacterCreate.success(character.id, character.world_id)
        {:reply_world_encrypted, :server_character_create, encode_packet(response), state}

      {:error, :name_taken} ->
        response = ServerCharacterCreate.failure(:name_taken)
        {:reply_world_encrypted, :server_character_create, encode_packet(response), state}

      {:error, :invalid_name} ->
        response = ServerCharacterCreate.failure(:invalid_name)
        {:reply_world_encrypted, :server_character_create, encode_packet(response), state}

      {:error, :max_characters} ->
        response = ServerCharacterCreate.failure(:max_characters)
        {:reply_world_encrypted, :server_character_create, encode_packet(response), state}

      {:error, :invalid_faction} ->
        response = ServerCharacterCreate.failure(:invalid_faction)
        {:reply_world_encrypted, :server_character_create, encode_packet(response), state}

      {:error, reason} ->
        Logger.error("Character creation failed: #{inspect(reason)}")
        response = ServerCharacterCreate.failure(:server_error)
        {:reply_world_encrypted, :server_character_create, encode_packet(response), state}
    end
  end

  defp encode_packet(%ServerCharacterCreate{} = packet) do
    writer = PacketWriter.new()
    {:ok, writer} = ServerCharacterCreate.write(packet, writer)
    PacketWriter.to_binary(writer)
  end

  # Compute ItemVisual entries from customization labels/values
  defp compute_visuals(race, sex, labels, values) do
    customizations = Enum.zip(labels, values)
    Store.get_item_visuals(race, sex, customizations)
  end

  # Add starting gear from the character creation template
  defp add_starting_gear(character_id, creation_entry) do
    # CharacterCreation has itemId0 through itemId015
    item_keys = for i <- 0..15, do: item_key(i)

    item_keys
    |> Enum.map(fn key -> get_item_id(creation_entry, key) end)
    |> Enum.filter(&(&1 > 0))
    |> Enum.each(fn item_id -> add_equipped_item(character_id, item_id) end)
  end

  # Generate the key for itemId fields (itemId0, itemId01, itemId02, etc.)
  defp item_key(0), do: "itemId0"
  defp item_key(n) when n < 10, do: "itemId0#{n}"
  defp item_key(n), do: "itemId0#{n}"

  defp get_item_id(entry, key) do
    Map.get(entry, key) || Map.get(entry, String.to_atom(key)) || 0
  end

  # Add a single item to the character's equipped container
  defp add_equipped_item(character_id, item_id) do
    case Store.get_item_slot(item_id) do
      nil ->
        Logger.debug("Item #{item_id} has no slot, skipping")

      slot when slot > 0 ->
        # Add item to equipped container at the correct slot
        attrs = %{
          character_id: character_id,
          item_id: item_id,
          container_type: :equipped,
          bag_index: 0,
          slot: slot,
          quantity: 1,
          max_stack: 1
        }

        case BezgelorDb.Repo.insert(BezgelorDb.Schema.InventoryItem.changeset(%BezgelorDb.Schema.InventoryItem{}, attrs)) do
          {:ok, _item} ->
            Logger.debug("Added starting item #{item_id} to slot #{slot}")

          {:error, changeset} ->
            Logger.warning("Failed to add starting item #{item_id}: #{inspect(changeset.errors)}")
        end

      _ ->
        :ok
    end
  end
end
