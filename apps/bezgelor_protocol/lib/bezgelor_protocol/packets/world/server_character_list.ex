defmodule BezgelorProtocol.Packets.World.ServerCharacterList do
  @moduledoc """
  List of characters for the account.

  ## Overview

  Sent after successful world server authentication.
  Contains all characters for the account with their details and appearance.

  ## Packet Structure (bit-packed)

  ```
  server_time              : uint64         - Server timestamp (ms since epoch)
  character_count          : uint32         - Number of characters
  characters               : Character[]    - Character entries
  enabled_creation_count   : uint32         - Enabled character creation IDs count
  enabled_creation_ids     : uint32[]       - Enabled creation IDs
  disabled_creation_count  : uint32         - Disabled character creation IDs count
  disabled_creation_ids    : uint32[]       - Disabled creation IDs
  realm_id                 : 14 bits        - Current realm ID
  char_remove_identity     : Identity       - Character being removed
  char_remove_time         : uint32         - Time until removal (seconds)
  char_reservation_count   : uint32         - Reserved character slots
  max_characters           : uint32         - Maximum character slots
  additional_count         : uint32         - Additional character slots
  faction_restriction      : 14 bits        - Faction restriction (0=none)
  free_level_50            : bool (1 bit)   - Free level 50 enabled
  ```

  ## Character Structure

  ```
  id               : uint64      - Character ID
  name             : wide_string - Character name
  sex              : 2 bits      - 0=male, 1=female
  race             : 5 bits      - Race ID
  class            : 5 bits      - Class ID
  faction          : uint32      - Faction ID
  level            : uint32      - Character level
  appearance_count : uint32      - Appearance items
  appearance       : ItemVisual[]
  gear_count       : uint32      - Equipped gear items
  gear             : ItemVisual[]
  world_id         : 15 bits     - World ID
  world_zone_id    : 15 bits     - Zone ID
  realm_id         : 14 bits     - Realm ID
  position         : float32 x3  - X, Y, Z position
  yaw              : float32     - Yaw rotation
  pitch            : float32     - Pitch rotation
  path             : 3 bits      - Path ID
  is_locked        : 1 bit       - Character locked
  requires_rename  : 1 bit       - Needs rename
  gear_mask        : uint32      - Gear visibility mask
  label_count      : 4 bits      - Customization labels
  labels           : uint32[]    - Label IDs
  values           : uint32[]    - Label values
  bone_count       : uint32      - Bone customizations
  bones            : float32[]   - Bone values
  last_logged_out  : float32     - Days since last login
  ```
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct server_time: 0,
            characters: [],
            enabled_character_creation_ids: [],
            disabled_character_creation_ids: [],
            realm_id: 1,
            char_remove_identity: nil,
            char_remove_time: 0,
            char_reservation_count: 0,
            max_characters: 12,
            additional_count: 0,
            faction_restriction: 0,
            free_level_50: false

  defmodule CharacterEntry do
    @moduledoc """
    Character entry in the character list.
    """
    defstruct [
      :id,
      :name,
      :sex,
      :race,
      :class,
      :faction,
      :level,
      appearance: [],
      gear: [],
      world_id: 0,
      world_zone_id: 0,
      realm_id: 1,
      position: {0.0, 0.0, 0.0},
      yaw: 0.0,
      pitch: 0.0,
      path: 0,
      is_locked: false,
      requires_rename: false,
      gear_mask: 0,
      labels: [],
      values: [],
      bones: [],
      last_logged_out_days: 0.0
    ]

    @type t :: %__MODULE__{
            id: non_neg_integer(),
            name: String.t(),
            sex: non_neg_integer(),
            race: non_neg_integer(),
            class: non_neg_integer(),
            faction: non_neg_integer(),
            level: non_neg_integer(),
            appearance: [ItemVisual.t()],
            gear: [ItemVisual.t()],
            world_id: non_neg_integer(),
            world_zone_id: non_neg_integer(),
            realm_id: non_neg_integer(),
            position: {float(), float(), float()},
            yaw: float(),
            pitch: float(),
            path: non_neg_integer(),
            is_locked: boolean(),
            requires_rename: boolean(),
            gear_mask: non_neg_integer(),
            labels: [non_neg_integer()],
            values: [non_neg_integer()],
            bones: [float()],
            last_logged_out_days: float()
          }
  end

  defmodule ItemVisual do
    @moduledoc """
    Visual appearance data for an equipped item slot.
    """
    defstruct slot: 0,
              display_id: 0,
              colour_set_id: 0,
              dye_data: 0

    @type t :: %__MODULE__{
            slot: non_neg_integer(),
            display_id: non_neg_integer(),
            colour_set_id: non_neg_integer(),
            dye_data: integer()
          }
  end

  defmodule Identity do
    @moduledoc """
    Realm + Character identity.
    """
    defstruct realm_id: 0,
              id: 0

    @type t :: %__MODULE__{
            realm_id: non_neg_integer(),
            id: non_neg_integer()
          }
  end

  @type t :: %__MODULE__{
          server_time: non_neg_integer(),
          characters: [CharacterEntry.t()],
          enabled_character_creation_ids: [non_neg_integer()],
          disabled_character_creation_ids: [non_neg_integer()],
          realm_id: non_neg_integer(),
          char_remove_identity: Identity.t() | nil,
          char_remove_time: non_neg_integer(),
          char_reservation_count: non_neg_integer(),
          max_characters: non_neg_integer(),
          additional_count: non_neg_integer(),
          faction_restriction: non_neg_integer(),
          free_level_50: boolean()
        }

  @impl true
  def opcode, do: :server_character_list

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    # Server time (uint64) - use bits for continuous stream
    writer = PacketWriter.write_uint64_bits(writer, packet.server_time)

    # Character count and characters
    writer = PacketWriter.write_uint32_bits(writer, length(packet.characters))
    writer = Enum.reduce(packet.characters, writer, &write_character/2)

    # Enabled character creation IDs
    writer = PacketWriter.write_uint32_bits(writer, length(packet.enabled_character_creation_ids))

    writer =
      Enum.reduce(packet.enabled_character_creation_ids, writer, fn id, w ->
        PacketWriter.write_uint32_bits(w, id)
      end)

    # Disabled character creation IDs
    writer = PacketWriter.write_uint32_bits(writer, length(packet.disabled_character_creation_ids))

    writer =
      Enum.reduce(packet.disabled_character_creation_ids, writer, fn id, w ->
        PacketWriter.write_uint32_bits(w, id)
      end)

    # Realm ID (14 bits)
    writer = PacketWriter.write_bits(writer, packet.realm_id, 14)

    # Character remove identity
    identity = packet.char_remove_identity || %Identity{}
    writer = PacketWriter.write_bits(writer, identity.realm_id, 14)
    writer = PacketWriter.write_bits(writer, identity.id, 64)

    # Character remove time, reservation count, max characters, additional count
    writer = PacketWriter.write_bits(writer, packet.char_remove_time, 32)
    writer = PacketWriter.write_bits(writer, packet.char_reservation_count, 32)
    writer = PacketWriter.write_bits(writer, packet.max_characters, 32)
    writer = PacketWriter.write_bits(writer, packet.additional_count, 32)

    # Faction restriction (14 bits)
    writer = PacketWriter.write_bits(writer, packet.faction_restriction, 14)

    # Free level 50 (1 bit bool)
    writer = PacketWriter.write_bits(writer, if(packet.free_level_50, do: 1, else: 0), 1)

    # Flush remaining bits
    writer = PacketWriter.flush_bits(writer)

    {:ok, writer}
  end

  # Write a single character entry (bit-packed)
  # All writes use bit-stream functions to maintain continuous bit stream
  defp write_character(char, writer) do
    # ID (uint64) - use bits version to maintain continuous stream
    writer = PacketWriter.write_uint64_bits(writer, char.id)

    # Name (wide string)
    writer = PacketWriter.write_wide_string(writer, char.name || "")

    # Sex (2 bits), Race (5 bits), Class (5 bits)
    writer = PacketWriter.write_bits(writer, char.sex || 0, 2)
    writer = PacketWriter.write_bits(writer, char.race || 0, 5)
    writer = PacketWriter.write_bits(writer, char.class || 0, 5)

    # Faction (uint32), Level (uint32)
    writer = PacketWriter.write_bits(writer, char.faction || 0, 32)
    writer = PacketWriter.write_bits(writer, char.level || 1, 32)

    # Appearance items
    appearance = char.appearance || []
    writer = PacketWriter.write_bits(writer, length(appearance), 32)
    writer = Enum.reduce(appearance, writer, &write_item_visual/2)

    # Gear items
    gear = char.gear || []
    writer = PacketWriter.write_bits(writer, length(gear), 32)
    writer = Enum.reduce(gear, writer, &write_item_visual/2)

    # World ID (15 bits), World Zone ID (15 bits), Realm ID (14 bits)
    writer = PacketWriter.write_bits(writer, char.world_id || 0, 15)
    writer = PacketWriter.write_bits(writer, char.world_zone_id || 0, 15)
    writer = PacketWriter.write_bits(writer, char.realm_id || 1, 14)

    # Position (3 floats) + Yaw + Pitch
    # Use write_float32_bits to maintain continuous bit stream
    {x, y, z} = char.position || {0.0, 0.0, 0.0}
    writer = PacketWriter.write_float32_bits(writer, x)
    writer = PacketWriter.write_float32_bits(writer, y)
    writer = PacketWriter.write_float32_bits(writer, z)
    writer = PacketWriter.write_float32_bits(writer, char.yaw || 0.0)
    writer = PacketWriter.write_float32_bits(writer, char.pitch || 0.0)

    # Path (3 bits), IsLocked (1 bit), RequiresRename (1 bit)
    writer = PacketWriter.write_bits(writer, char.path || 0, 3)
    writer = PacketWriter.write_bits(writer, if(char.is_locked, do: 1, else: 0), 1)
    writer = PacketWriter.write_bits(writer, if(char.requires_rename, do: 1, else: 0), 1)

    # GearMask (uint32)
    writer = PacketWriter.write_bits(writer, char.gear_mask || 0, 32)

    # Labels/Values (count is 4 bits)
    labels = char.labels || []
    values = char.values || []
    writer = PacketWriter.write_bits(writer, length(labels), 4)

    writer =
      Enum.reduce(labels, writer, fn label, w ->
        PacketWriter.write_bits(w, label, 32)
      end)

    writer =
      Enum.reduce(values, writer, fn value, w ->
        PacketWriter.write_bits(w, value, 32)
      end)

    # Bones
    # Use write_float32_bits to maintain continuous bit stream
    bones = char.bones || []
    writer = PacketWriter.write_bits(writer, length(bones), 32)

    writer =
      Enum.reduce(bones, writer, fn bone, w ->
        PacketWriter.write_float32_bits(w, bone)
      end)

    # Last logged out days (float32)
    # Use write_float32_bits to maintain continuous bit stream
    PacketWriter.write_float32_bits(writer, char.last_logged_out_days || 0.0)
  end

  # Write ItemVisual (bit-packed)
  defp write_item_visual(item, writer) do
    # Slot (7 bits), DisplayId (15 bits), ColourSetId (14 bits), DyeData (int32)
    writer = PacketWriter.write_bits(writer, item.slot || 0, 7)
    writer = PacketWriter.write_bits(writer, item.display_id || 0, 15)
    writer = PacketWriter.write_bits(writer, item.colour_set_id || 0, 14)
    # DyeData is a signed int32, write as 32 bits
    PacketWriter.write_bits(writer, item.dye_data || 0, 32)
  end

  @doc """
  Build a character list packet from database characters.
  """
  @spec from_characters([map()], non_neg_integer()) :: t()
  def from_characters(characters, max_characters \\ 12) do
    server_time = System.system_time(:millisecond)

    entries =
      Enum.map(characters, fn char ->
        # Calculate days since last login (negative value, per NexusForever)
        last_logged_out_days =
          case char.last_online do
            %DateTime{} = dt ->
              diff_seconds = DateTime.diff(DateTime.utc_now(), dt, :second)
              # Multiply by -1 to match NexusForever format
              -(diff_seconds / 86400.0)

            nil ->
              0.0

            _ ->
              0.0
          end

        # Convert position from database format
        # Character schema has location_x, location_y, location_z fields
        {x, y, z} =
          cond do
            # Check for separate location fields (from Character schema)
            Map.has_key?(char, :location_x) ->
              {char.location_x || 0.0, char.location_y || 0.0, char.location_z || 0.0}

            # Legacy: position as a map
            is_map(Map.get(char, :position)) ->
              pos = char.position
              {Map.get(pos, :x, 0.0), Map.get(pos, :y, 0.0), Map.get(pos, :z, 0.0)}

            # Legacy: position as a tuple
            is_tuple(Map.get(char, :position)) ->
              char.position

            true ->
              {0.0, 0.0, 0.0}
          end

        # Extract customization data from appearance association
        {labels, values, bones} = get_customization_data(char)

        %CharacterEntry{
          id: char.id,
          name: char.name,
          sex: char.sex || 0,
          race: char.race || 0,
          class: char.class || 0,
          faction: char.faction_id || 0,
          level: char.level || 1,
          appearance: [],
          gear: [],
          world_id: char.world_id || 0,
          world_zone_id: char.world_zone_id || 0,
          realm_id: 1,
          position: {x, y, z},
          # Use rotation_z as yaw (horizontal rotation)
          yaw: Map.get(char, :rotation_z, 0.0) || 0.0,
          # Use rotation_x as pitch (vertical rotation)
          pitch: Map.get(char, :rotation_x, 0.0) || 0.0,
          path: char.active_path || 0,
          is_locked: false,
          requires_rename: false,
          # 0xFFFFFFFF shows all gear slots (per NexusForever)
          gear_mask: 0xFFFFFFFF,
          labels: labels,
          values: values,
          bones: bones,
          last_logged_out_days: last_logged_out_days
        }
      end)

    %__MODULE__{
      server_time: server_time,
      characters: entries,
      enabled_character_creation_ids: [],
      disabled_character_creation_ids: [],
      realm_id: 1,
      char_remove_identity: %Identity{realm_id: 0, id: 0},
      char_remove_time: 0,
      char_reservation_count: 0,
      max_characters: max_characters,
      additional_count: 0,
      faction_restriction: 0,
      free_level_50: false
    }
  end

  # Extract customization data (labels, values, bones) from character appearance association
  defp get_customization_data(char) do
    case Map.get(char, :appearance) do
      %{labels: labels, values: values, bones: bones}
      when is_list(labels) and is_list(values) and is_list(bones) ->
        {labels, values, bones}

      %{bones: bones} when is_list(bones) ->
        # Legacy: only bones stored
        {[], [], bones}

      _ ->
        {[], [], []}
    end
  end
end
