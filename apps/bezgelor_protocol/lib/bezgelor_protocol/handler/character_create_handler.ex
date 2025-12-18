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

  # Character name validation: 3-24 characters, letters, numbers, spaces, apostrophes
  # Must start with a letter, no consecutive spaces
  @name_min_length 3
  @name_max_length 24
  @name_regex ~r/^[A-Za-z][A-Za-z0-9' ]*$/

  # Customization limits to prevent abuse
  @max_customization_count 100
  @max_bone_count 200
  @max_bone_value 10.0
  @min_bone_value -10.0

  @impl true
  def handle(payload, state) do
    Logger.info("CharacterCreateHandler.handle called (v2), payload size: #{byte_size(payload)}")
    reader = PacketReader.new(payload)
    Logger.info("CharacterCreateHandler: calling ClientCharacterCreate.read")

    result = ClientCharacterCreate.read(reader)
    Logger.info("CharacterCreateHandler: read result type: #{elem(result, 0)}")

    case result do
      {:ok, packet, _reader} ->
        Logger.info("CharacterCreateHandler: packet parsed, name=#{inspect(packet.name)}, creation_id=#{packet.character_creation_id}")
        create_character(packet, state)

      {:error, reason} ->
        Logger.warning("Failed to parse ClientCharacterCreate: #{inspect(reason)}")
        response = ServerCharacterCreate.failure(:server_error)
        {:reply_world_encrypted, :server_character_create, encode_packet(response), state}
    end
  end

  defp create_character(packet, state) do
    account_id = state.session_data[:account_id]
    Logger.info("create_character: account_id=#{inspect(account_id)}, name=#{inspect(packet.name)}")

    cond do
      is_nil(account_id) ->
        Logger.warning("Character create attempted without authenticated account")
        response = ServerCharacterCreate.failure(:server_error)
        {:reply_world_encrypted, :server_character_create, encode_packet(response), state}

      not valid_name?(packet.name) ->
        Logger.warning("Invalid character name rejected: #{inspect(packet.name)}")
        response = ServerCharacterCreate.failure(:invalid_name)
        {:reply_world_encrypted, :server_character_create, encode_packet(response), state}

      not valid_customization?(packet) ->
        Logger.warning("Invalid customization data rejected: labels=#{length(packet.labels)}, bones=#{length(packet.bones)}")
        response = ServerCharacterCreate.failure(:server_error)
        {:reply_world_encrypted, :server_character_create, encode_packet(response), state}

      true ->
        Logger.info("Validation passed, calling do_create")
        do_create(account_id, packet, state)
    end
  end

  # Validate character name format
  defp valid_name?(name) when is_binary(name) do
    len = String.length(name)
    trimmed = String.trim(name)

    len >= @name_min_length and
      len <= @name_max_length and
      trimmed == name and
      not String.contains?(name, "  ") and
      Regex.match?(@name_regex, name)
  end

  defp valid_name?(_), do: false

  # Validate customization data to prevent abuse
  defp valid_customization?(packet) do
    labels_count = length(packet.labels)
    values_count = length(packet.values)
    bones_count = length(packet.bones)

    # Labels and values must match in count
    labels_count == values_count and
      # Limit customization count to prevent abuse
      labels_count <= @max_customization_count and
      # Limit bone count
      bones_count <= @max_bone_count and
      # Validate bone values are within reasonable range
      Enum.all?(packet.bones, &valid_bone_value?/1)
  end

  # Validate bone value is within acceptable range
  defp valid_bone_value?(bone) when is_float(bone) do
    bone >= @min_bone_value and bone <= @max_bone_value
  end

  defp valid_bone_value?(_), do: false

  defp do_create(account_id, packet, state) do
    Logger.info("do_create: looking up creation template #{packet.character_creation_id}")
    # Look up the character creation template
    case Store.get_character_creation(packet.character_creation_id) do
      {:ok, creation_entry} ->
        # Keys are atoms from JSON loading
        race = Map.get(creation_entry, :raceId)
        class = Map.get(creation_entry, :classId)
        Logger.info("do_create: found creation template, race=#{inspect(race)}, class=#{inspect(class)}, keys=#{inspect(Map.keys(creation_entry) |> Enum.take(5))}")
        create_from_template(account_id, packet, creation_entry, state)

      :error ->
        Logger.warning("Invalid character creation ID: #{packet.character_creation_id}")
        response = ServerCharacterCreate.failure(:server_error)
        {:reply_world_encrypted, :server_character_create, encode_packet(response), state}
    end
  end

  defp create_from_template(account_id, packet, creation_entry, state) do
    # Extract race, class, sex, faction from the creation template
    # JSON is loaded with keys: :atoms, so keys are atoms
    race = Map.get(creation_entry, :raceId)
    class = Map.get(creation_entry, :classId)
    sex = Map.get(creation_entry, :sex)
    faction_id = Map.get(creation_entry, :factionId)

    # Get creation start type (0=Arkship, 3=Nexus/Veteran, 4=PreTutorial/Novice, 5=Level50)
    creation_start = Map.get(creation_entry, :characterCreationStartEnum) || 4

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

    Logger.info("create_from_template: calling Characters.create_character for account #{account_id}")
    Logger.info("create_from_template: character_attrs=#{inspect(character_attrs)}")
    result = Characters.create_character(account_id, character_attrs, customization_attrs)
    Logger.info("create_from_template: Characters.create_character returned: #{inspect(result)}")

    case result do
      {:ok, character} ->
        Logger.info("Created character '#{character.name}' (ID: #{character.id}) for account #{account_id} in world #{character.world_id}")

        # Initialize inventory bags and add starting gear
        try do
          Inventory.init_bags(character.id)
          add_starting_gear(character.id, creation_entry)
        rescue
          e ->
            Logger.error("Failed to add starting gear: #{inspect(e)}")
            Logger.error(Exception.format_stacktrace(__STACKTRACE__))
        end

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

    item_ids = item_keys
    |> Enum.map(fn key -> {key, get_item_id(creation_entry, key)} end)
    |> Enum.filter(fn {_key, id} -> id > 0 end)

    Logger.info("Starting gear for character #{character_id}: #{inspect(item_ids)}")

    Enum.each(item_ids, fn {_key, item_id} -> add_equipped_item(character_id, item_id) end)
  end

  # Generate the key for itemId fields (itemId0, itemId01, itemId02, etc.)
  defp item_key(0), do: "itemId0"
  defp item_key(n) when n < 10, do: "itemId0#{n}"
  defp item_key(n), do: "itemId0#{n}"

  defp get_item_id(entry, key) when is_binary(key) do
    # Keys are atoms from JSON loading
    Map.get(entry, String.to_atom(key), 0)
  end

  # ItemSlot (from Item2Type.itemSlotId) to EquippedItem (network protocol) mapping
  @item_slot_to_equipped %{
    1 => 0,    # ArmorChest -> Chest
    2 => 1,    # ArmorLegs -> Legs
    3 => 2,    # ArmorHead -> Head
    4 => 3,    # ArmorShoulder -> Shoulder
    5 => 4,    # ArmorFeet -> Feet
    6 => 5,    # ArmorHands -> Hands
    7 => 6,    # WeaponTool -> WeaponTool
    20 => 16,  # WeaponPrimary -> WeaponPrimary
    43 => 15,  # ArmorShields -> Shields
    46 => 11,  # ArmorGadget -> Gadget
    57 => 7,   # ArmorWeaponAttachment -> WeaponAttachment
    58 => 8,   # ArmorSystem -> System
    59 => 9,   # ArmorAugment -> Augment
    60 => 10   # ArmorImplant -> Implant
  }

  # Add a single item to the character's equipped container
  defp add_equipped_item(character_id, item_id) do
    Logger.info("add_equipped_item called: character=#{character_id}, item=#{item_id}")
    item_slot = Store.get_item_slot(item_id)
    Logger.info("  Store.get_item_slot(#{item_id}) returned: #{inspect(item_slot)}")

    # Get ItemSlot from Item2Type, then convert to EquippedItem
    case item_slot do
      nil ->
        Logger.info("  Item #{item_id} has no slot (nil), skipping")

      item_slot when item_slot > 0 ->
        # Convert ItemSlot to EquippedItem
        case Map.get(@item_slot_to_equipped, item_slot) do
          nil ->
            Logger.debug("Item #{item_id} has unmapped ItemSlot #{item_slot}, skipping")

          equipped_slot ->
            Logger.info("Item #{item_id}: ItemSlot #{item_slot} -> EquippedItem #{equipped_slot}")

            attrs = %{
              character_id: character_id,
              item_id: item_id,
              container_type: :equipped,
              bag_index: 0,
              slot: equipped_slot,
              quantity: 1,
              max_stack: 1,
              durability: 100,
              max_durability: 100
            }

            case BezgelorDb.Repo.insert(BezgelorDb.Schema.InventoryItem.changeset(%BezgelorDb.Schema.InventoryItem{}, attrs)) do
              {:ok, _item} ->
                Logger.info("  Added item #{item_id} to EquippedItem slot #{equipped_slot}")

              {:error, changeset} ->
                Logger.warning("  Failed to add item #{item_id}: #{inspect(changeset.errors)}")
            end
        end

      _ ->
        :ok
    end
  end
end
