defmodule BezgelorProtocol.Packets.World.ServerEntityCreate do
  @moduledoc """
  Server packet to create an entity in the game world.

  This packet is sent when an entity becomes visible to a player, including
  when the player first enters the world (player becomes visible to themselves).

  ## Wire Format (from NexusForever)

  ```
  guid                : uint32
  type                : 6 bits (EntityType enum)
  entity_model        : varies by type (PlayerEntityModel for players)
  create_flags        : 8 bits
  stats_count         : 5 bits
  stats[]             : StatValueInitial structs
  time                : uint32 (movement time)
  commands_count      : 5 bits
  commands[]          : EntityCommand (id 5 bits + model data)
  properties_count    : 8 bits
  properties[]        : PropertyValue structs
  visible_items_count : 7 bits
  visible_items[]     : ItemVisual structs
  spell_init_count    : 9 bits
  spell_init[]        : SpellInit structs
  current_spell_id    : uint32
  faction1            : 14 bits
  faction2            : 14 bits
  unit_tag_owner      : uint32
  group_tag_owner     : uint64
  unknown_a8          : type 2 bits + data
  world_placement     : type 2 bits + data
  unknown_c8          : type 2 bits + data
  minimap_marker      : 14 bits
  display_info        : 17 bits
  outfit_info         : 15 bits
  ```

  ## PlayerEntityModel Format

  ```
  id                  : uint64 (character ID)
  realm_id            : 14 bits
  name                : wide string (bit-packed)
  race                : 5 bits
  class               : 5 bits
  sex                 : 2 bits
  group_id            : uint64
  pet_ids_count       : 8 bits
  pet_ids[]           : uint32 each
  guild_name          : wide string
  guild_type          : 4 bits
  guild_ids_count     : 5 bits
  guild_ids[]         : uint64 each
  bones_count         : 6 bits
  bones[]             : float32 each
  pvp_flag            : 3 bits
  unknown_4c          : 8 bits
  title               : 14 bits
  ```
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  # EntityType values (from NexusForever)
  @entity_type_player 20

  # EntityCommand values
  @cmd_set_platform 1
  @cmd_set_position 2
  @cmd_set_velocity 8
  @cmd_set_move 11
  @cmd_set_rotation 14
  @cmd_set_scale 22
  @cmd_set_state 24
  @cmd_set_mode 27

  defstruct guid: 0,
            entity_type: @entity_type_player,
            # Player entity model fields
            character_id: 0,
            realm_id: 1,
            name: "",
            race: 1,
            class: 1,
            sex: 0,
            group_id: 0,
            bones: [],
            title: 0,
            # Entity fields
            create_flags: 0,
            time: 0,
            faction1: 166,
            faction2: 166,
            display_info: 0,
            outfit_info: 0,
            # Position/rotation for commands
            position: {0.0, 0.0, 0.0},
            rotation: {0.0, 0.0, 0.0}

  @type t :: %__MODULE__{
          guid: non_neg_integer(),
          entity_type: non_neg_integer(),
          character_id: non_neg_integer(),
          realm_id: non_neg_integer(),
          name: String.t(),
          race: non_neg_integer(),
          class: non_neg_integer(),
          sex: non_neg_integer(),
          group_id: non_neg_integer(),
          bones: [float()],
          title: non_neg_integer(),
          create_flags: non_neg_integer(),
          time: non_neg_integer(),
          faction1: non_neg_integer(),
          faction2: non_neg_integer(),
          display_info: non_neg_integer(),
          outfit_info: non_neg_integer(),
          position: {float(), float(), float()},
          rotation: {float(), float(), float()}
        }

  @impl true
  def opcode, do: :server_entity_create

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      # Guid
      |> PacketWriter.write_bits(packet.guid, 32)
      # EntityType (6 bits) - Player = 20
      |> PacketWriter.write_bits(packet.entity_type, 6)
      # PlayerEntityModel
      |> write_player_entity_model(packet)
      # CreateFlags (8 bits)
      |> PacketWriter.write_bits(packet.create_flags, 8)
      # Stats - empty for now
      |> PacketWriter.write_bits(0, 5)
      # Time
      |> PacketWriter.write_bits(packet.time, 32)
      # Commands (8 default commands)
      |> write_default_commands(packet)
      # Properties - empty
      |> PacketWriter.write_bits(0, 8)
      # VisibleItems - empty
      |> PacketWriter.write_bits(0, 7)
      # SpellInitData - empty
      |> PacketWriter.write_bits(0, 9)
      # CurrentSpellUniqueId
      |> PacketWriter.write_bits(0, 32)
      # Faction1 (14 bits)
      |> PacketWriter.write_bits(packet.faction1, 14)
      # Faction2 (14 bits)
      |> PacketWriter.write_bits(packet.faction2, 14)
      # UnitTagOwner
      |> PacketWriter.write_bits(0, 32)
      # GroupTagOwner (uint64)
      |> PacketWriter.write_bits(0, 64)
      # UnknownA8: type=0, bool=false
      |> PacketWriter.write_bits(0, 2)
      |> PacketWriter.write_bits(0, 1)
      # WorldPlacement: type=0, bool=false
      |> PacketWriter.write_bits(0, 2)
      |> PacketWriter.write_bits(0, 1)
      # UnknownC8: type=0, bool=false
      |> PacketWriter.write_bits(0, 2)
      |> PacketWriter.write_bits(0, 1)
      # MiniMapMarker (14 bits)
      |> PacketWriter.write_bits(0, 14)
      # DisplayInfo (17 bits)
      |> PacketWriter.write_bits(packet.display_info, 17)
      # OutfitInfo (15 bits)
      |> PacketWriter.write_bits(packet.outfit_info, 15)
      |> PacketWriter.flush_bits()

    {:ok, writer}
  end

  defp write_player_entity_model(writer, packet) do
    writer
    # Id (uint64) - character ID
    |> PacketWriter.write_bits(packet.character_id, 64)
    # RealmId (14 bits)
    |> PacketWriter.write_bits(packet.realm_id, 14)
    # Name (wide string)
    |> PacketWriter.write_wide_string(packet.name)
    # Race (5 bits)
    |> PacketWriter.write_bits(packet.race, 5)
    # Class (5 bits)
    |> PacketWriter.write_bits(packet.class, 5)
    # Sex (2 bits)
    |> PacketWriter.write_bits(packet.sex, 2)
    # GroupId (uint64)
    |> PacketWriter.write_bits(packet.group_id, 64)
    # PetIdList count (8 bits) - empty
    |> PacketWriter.write_bits(0, 8)
    # GuildName (wide string) - empty
    |> PacketWriter.write_wide_string("")
    # GuildType (4 bits) - None = 0
    |> PacketWriter.write_bits(0, 4)
    # GuildIds count (5 bits) - empty
    |> PacketWriter.write_bits(0, 5)
    # Bones count (6 bits)
    |> PacketWriter.write_bits(length(packet.bones), 6)
    |> write_bones(packet.bones)
    # PvPFlag (3 bits) - Disabled = 0
    |> PacketWriter.write_bits(0, 3)
    # Unknown4C (8 bits)
    |> PacketWriter.write_bits(0, 8)
    # Title (14 bits)
    |> PacketWriter.write_bits(packet.title, 14)
  end

  defp write_bones(writer, []), do: writer

  defp write_bones(writer, [bone | rest]) do
    writer
    |> PacketWriter.write_float32_bits(bone)
    |> write_bones(rest)
  end

  # Write default movement commands for a stationary entity
  # This matches NexusForever's MovementManager.GetInitialNetworkEntityCommands()
  defp write_default_commands(writer, packet) do
    # 8 commands
    writer
    |> PacketWriter.write_bits(8, 5)
    # SetPlatform (1) - UnitId = 0
    |> write_command(@cmd_set_platform, fn w ->
      PacketWriter.write_bits(w, 0, 32)
    end)
    # SetPosition (2) - Position + Blend=false
    |> write_command(@cmd_set_position, fn w ->
      w
      |> PacketWriter.write_vector3(packet.position)
      |> PacketWriter.write_bits(0, 1)
    end)
    # SetVelocity (8) - Velocity = 0,0,0 + Blend=false
    |> write_command(@cmd_set_velocity, fn w ->
      w
      |> PacketWriter.write_packed_vector3({0.0, 0.0, 0.0})
      |> PacketWriter.write_bits(0, 1)
    end)
    # SetMove (11) - Move = 0,0,0 + Blend=false
    |> write_command(@cmd_set_move, fn w ->
      w
      |> PacketWriter.write_packed_vector3({0.0, 0.0, 0.0})
      |> PacketWriter.write_bits(0, 1)
    end)
    # SetRotation (14) - Rotation + Blend=false
    |> write_command(@cmd_set_rotation, fn w ->
      w
      |> PacketWriter.write_vector3(packet.rotation)
      |> PacketWriter.write_bits(0, 1)
    end)
    # SetScale (22) - Scale = 1.0 + Blend=false
    |> write_command(@cmd_set_scale, fn w ->
      w
      |> PacketWriter.write_packed_float(1.0)
      |> PacketWriter.write_bits(0, 1)
    end)
    # SetState (24) - StateFlags = 0
    |> write_command(@cmd_set_state, fn w ->
      PacketWriter.write_bits(w, 0, 32)
    end)
    # SetMode (27) - ModeType = 0 (Ground)
    |> write_command(@cmd_set_mode, fn w ->
      PacketWriter.write_bits(w, 0, 32)
    end)
  end

  defp write_command(writer, command_id, write_model_fn) do
    writer
    |> PacketWriter.write_bits(command_id, 5)
    |> write_model_fn.()
  end

  @doc """
  Create an entity create packet from character data and spawn location.

  Spawn location maps have:
  - world_id: integer
  - position: {x, y, z} tuple
  - rotation: {rx, ry, rz} tuple
  """
  @spec from_character(map(), map()) :: t()
  def from_character(character, spawn) do
    # Generate GUID for player entity
    player_guid = character.id + 0x2000_0000

    # Extract position and rotation from spawn tuples
    {x, y, z} = spawn.position
    {_rx, _ry, rz} = spawn.rotation

    # Get bones from appearance if available
    bones = case character do
      %{appearance: %{bones: bones}} when is_list(bones) -> bones
      _ -> []
    end

    %__MODULE__{
      guid: player_guid,
      entity_type: @entity_type_player,
      character_id: character.id,
      realm_id: 1,
      name: character.name,
      race: character.race || 1,
      class: character.class || 1,
      sex: character.sex || 0,
      group_id: 0,
      bones: bones,
      title: 0,
      create_flags: 0,
      time: :os.system_time(:millisecond) |> rem(0xFFFFFFFF),
      faction1: character.faction_id || 166,
      faction2: character.faction_id || 166,
      display_info: 0,
      outfit_info: 0,
      position: {x, y, z},
      rotation: {0.0, rz, 0.0}
    }
  end

  @doc """
  Create an entity create packet from an Entity struct.
  Used by WorldEntryHandler when spawning entities after world loading.
  """
  @spec from_entity(struct()) :: t()
  def from_entity(entity) do
    # Extract position and rotation tuples
    {pos_x, pos_y, pos_z} = entity.position || {0.0, 0.0, 0.0}
    rotation = entity.rotation || {0.0, 0.0, 0.0}

    %__MODULE__{
      guid: entity.guid,
      entity_type: @entity_type_player,
      character_id: entity.account_id || 0,
      realm_id: 1,
      name: entity.name || "",
      race: 1,
      class: 1,
      sex: 0,
      group_id: 0,
      bones: [],
      title: 0,
      create_flags: 0,
      time: :os.system_time(:millisecond) |> rem(0xFFFFFFFF),
      faction1: entity.faction || 166,
      faction2: entity.faction || 166,
      display_info: entity.display_info || 0,
      outfit_info: 0,
      position: {pos_x, pos_y, pos_z},
      rotation: rotation
    }
  end
end
