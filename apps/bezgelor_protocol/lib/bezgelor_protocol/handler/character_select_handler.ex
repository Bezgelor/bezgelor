defmodule BezgelorProtocol.Handler.CharacterSelectHandler do
  @moduledoc """
  Handler for ClientCharacterSelect packets.

  Validates character ownership and initiates world entry.
  Sends ServerWorldEnter with character spawn location.

  ## Flow

  1. Validate character belongs to authenticated account
  2. Update character's last_online timestamp
  3. Get spawn location (saved position or default)
  4. Send ServerWorldEnter + initialization packets
  5. Client loads world and sends ClientEnteredWorld
  """

  @behaviour BezgelorProtocol.Handler
  @compile {:no_warn_undefined, [BezgelorWorld.Zone.Instance]}

  alias BezgelorProtocol.Packets.World.{
    ClientCharacterSelect,
    ServerWorldEnter,
    ServerCharacterFlagsUpdated,
    ServerEntityCreate,
    ServerSetUnitPathType,
    ServerPlayerChanged,
    ServerInstanceSettings,
    ServerHousingNeighbors,
    ServerPlayerCreate,
    ServerMovementControl,
    ServerTimeOfDay,
    ServerPathInitialise
  }

  alias BezgelorProtocol.{PacketReader, PacketWriter}
  alias BezgelorDb.{Characters, Inventory}
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

        # Debug: log appearance data
        if character.appearance do
          Logger.debug("Character appearance visuals: #{inspect(character.appearance.visuals)}")
          Logger.debug("Character appearance bones: #{inspect(character.appearance.bones)}")
        else
          Logger.warning("Character #{character.id} has no appearance data!")
        end

        # Get spawn location
        spawn = Zone.spawn_location(character)

        # Generate a unique entity GUID for this character session
        # Using character ID + high bit to distinguish player entities
        # UnitId is 32-bit in ServerMovementControl
        player_guid = character.id + 0x2000_0000

        # Build packets
        world_enter_data = encode_packet(%ServerWorldEnter{} |> struct(ServerWorldEnter.from_spawn(spawn) |> Map.from_struct()))
        character_flags_data = encode_packet(%ServerCharacterFlagsUpdated{flags: 0})
        entity_struct = ServerEntityCreate.from_character(character, spawn)
        Logger.debug("ServerEntityCreate struct - visible_items: #{inspect(entity_struct.visible_items)}, bones: #{length(entity_struct.bones)}")
        entity_create_data = encode_packet(entity_struct)
        Logger.debug("ServerEntityCreate packet size: #{byte_size(entity_create_data)} bytes")
        # NexusForever sends these after ServerEntityCreate for player entities
        path_type_data = encode_packet(%ServerSetUnitPathType{unit_id: player_guid, path: character.active_path || 0})
        player_changed_data = encode_packet(%ServerPlayerChanged{guid: player_guid, unknown1: 1})
        time_of_day_data = encode_packet(ServerTimeOfDay.now())
        housing_neighbors_data = encode_packet(%ServerHousingNeighbors{})
        instance_settings_data = encode_packet(%ServerInstanceSettings{client_entity_send_update_interval: 125})
        movement_control_data = encode_packet(%ServerMovementControl{
          ticket: 1,
          immediate: true,
          unit_id: player_guid
        })
        path_initialise_data = encode_packet(ServerPathInitialise.from_character(character))

        # Load inventory items for the character
        inventory_items = Inventory.get_items(character.id)
        inventory_maps = Enum.map(inventory_items, fn item ->
          %{
            id: item.id,
            item_id: item.item_id,
            container_type: item.container_type,
            slot: item.slot,
            quantity: item.quantity,
            durability: item.durability,
            charges: 0
          }
        end)

        # Debug: Log inventory items being sent
        equipped_items = Enum.filter(inventory_maps, &(&1.container_type == :equipped))
        Logger.info("Sending #{length(inventory_maps)} inventory items (#{length(equipped_items)} equipped)")
        for item <- equipped_items do
          # Show the EquippedItem slot name
          slot_name = case item.slot do
            0 -> "Chest"
            1 -> "Legs"
            2 -> "Head"
            3 -> "Shoulder"
            4 -> "Feet"
            5 -> "Hands"
            6 -> "WeaponTool"
            7 -> "WeaponAttachment"
            8 -> "System"
            9 -> "Augment"
            10 -> "Implant"
            11 -> "Gadget"
            15 -> "Shields"
            16 -> "WeaponPrimary"
            17 -> "Bag0"
            other -> "Unknown(#{other})"
          end
          Logger.info("  Equipped: item_id=#{item.item_id}, slot=#{item.slot} (#{slot_name})")
        end

        player_create_data = encode_packet(ServerPlayerCreate.from_character(character, inventory_maps))

        # Store character info in session for WorldEntryHandler
        state = put_in(state.session_data[:character_id], character.id)
        state = put_in(state.session_data[:character_name], character.name)
        state = put_in(state.session_data[:character], character)
        state = put_in(state.session_data[:spawn_location], spawn)
        state = put_in(state.session_data[:player_guid], player_guid)
        state = put_in(state.session_data[:zone_id], spawn.world_id)
        state = put_in(state.session_data[:instance_id], 1)

        # Set character metadata for log tracing
        Logger.metadata(char: character.name)

        Logger.info("Account #{account_id} entering world with character '#{character.name}' (ID: #{character.id})")

        # Register player entity with zone instance for visibility tracking
        # This enables creature AI processing for zones with players
        player_entity = %BezgelorCore.Entity{
          guid: player_guid,
          type: :player,
          name: character.name,
          position: spawn.position
        }
        BezgelorWorld.Zone.Instance.add_entity({spawn.world_id, 1}, player_entity)

        # Send all initialization packets (order matters!)
        # Order based on NexusForever Player.OnAddToMap() and Player.AddVisible():
        # 1. World enter (ServerChangeWorld) tells client to start loading
        # 2. Character flags - MUST come before entity create (client UI init)
        # 3. Entity create - creates the player entity
        # 4. Path type - sets player's path (Soldier/Settler/Scientist/Explorer)
        # 5. Player changed - indicates this is the player's own entity
        # 6. Time of day - game time info
        # 7. Housing neighbors (empty for non-housing zones)
        # 8. Instance settings (difficulty, etc.)
        # 9. Movement control - gives player control of their character
        # 10. Player create - full player state (inventory, currencies, etc.)
        {:reply_multi_world_encrypted, [
          {:server_world_enter, world_enter_data},
          {:server_character_flags_updated, character_flags_data},
          {:server_entity_create, entity_create_data},
          {:server_set_unit_path_type, path_type_data},
          {:server_player_changed, player_changed_data},
          {:server_path_initialise, path_initialise_data},
          {:server_time_of_day, time_of_day_data},
          {:server_housing_neighbors, housing_neighbors_data},
          {:server_instance_settings, instance_settings_data},
          {:server_movement_control, movement_control_data},
          {:server_player_create, player_create_data}
        ], state}
    end
  end

  defp encode_packet(%ServerWorldEnter{} = packet) do
    writer = PacketWriter.new()
    {:ok, writer} = ServerWorldEnter.write(packet, writer)
    PacketWriter.to_binary(writer)
  end

  defp encode_packet(%ServerCharacterFlagsUpdated{} = packet) do
    writer = PacketWriter.new()
    {:ok, writer} = ServerCharacterFlagsUpdated.write(packet, writer)
    PacketWriter.to_binary(writer)
  end

  defp encode_packet(%ServerEntityCreate{} = packet) do
    writer = PacketWriter.new()
    {:ok, writer} = ServerEntityCreate.write(packet, writer)
    PacketWriter.to_binary(writer)
  end

  defp encode_packet(%ServerSetUnitPathType{} = packet) do
    writer = PacketWriter.new()
    {:ok, writer} = ServerSetUnitPathType.write(packet, writer)
    PacketWriter.to_binary(writer)
  end

  defp encode_packet(%ServerPlayerChanged{} = packet) do
    writer = PacketWriter.new()
    {:ok, writer} = ServerPlayerChanged.write(packet, writer)
    PacketWriter.to_binary(writer)
  end

  defp encode_packet(%ServerHousingNeighbors{} = packet) do
    writer = PacketWriter.new()
    {:ok, writer} = ServerHousingNeighbors.write(packet, writer)
    PacketWriter.to_binary(writer)
  end

  defp encode_packet(%ServerInstanceSettings{} = packet) do
    writer = PacketWriter.new()
    {:ok, writer} = ServerInstanceSettings.write(packet, writer)
    PacketWriter.to_binary(writer)
  end

  defp encode_packet(%ServerMovementControl{} = packet) do
    writer = PacketWriter.new()
    {:ok, writer} = ServerMovementControl.write(packet, writer)
    PacketWriter.to_binary(writer)
  end

  defp encode_packet(%ServerPlayerCreate{} = packet) do
    writer = PacketWriter.new()
    {:ok, writer} = ServerPlayerCreate.write(packet, writer)
    PacketWriter.to_binary(writer)
  end

  defp encode_packet(%ServerTimeOfDay{} = packet) do
    writer = PacketWriter.new()
    {:ok, writer} = ServerTimeOfDay.write(packet, writer)
    PacketWriter.to_binary(writer)
  end

  defp encode_packet(%ServerPathInitialise{} = packet) do
    writer = PacketWriter.new()
    {:ok, writer} = ServerPathInitialise.write(packet, writer)
    PacketWriter.to_binary(writer)
  end
end
