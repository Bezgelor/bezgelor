defmodule BezgelorProtocol.Packets.World.ServerCharacterList do
  @moduledoc """
  List of characters for the account.

  ## Overview

  Sent after successful world server authentication.
  Contains all characters for the account with their details and appearance.

  ## Packet Structure

  ```
  max_characters : uint32        - Maximum character slots
  character_count: uint32        - Number of characters in list
  characters     : CharacterEntry[] - List of character entries
  ```

  ## CharacterEntry Structure

  ```
  id             : uint64        - Character ID
  name           : wide_string   - Character name
  sex            : uint32        - 0=male, 1=female
  race           : uint32        - Race ID
  class          : uint32        - Class ID
  path           : uint32        - Path ID
  faction_id     : uint32        - Faction ID (166=Exile, 167=Dominion)
  level          : uint32        - Character level
  world_id       : uint32        - Current world ID
  zone_id        : uint32        - Current zone ID
  last_login     : uint64        - Unix timestamp (seconds)
  appearance     : AppearanceData - Customization data
  ```
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct characters: [],
            max_characters: 12

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
      :path,
      :faction_id,
      :level,
      :world_id,
      :zone_id,
      :last_login,
      :appearance
    ]

    @type t :: %__MODULE__{
            id: non_neg_integer(),
            name: String.t(),
            sex: non_neg_integer(),
            race: non_neg_integer(),
            class: non_neg_integer(),
            path: non_neg_integer(),
            faction_id: non_neg_integer(),
            level: non_neg_integer(),
            world_id: non_neg_integer(),
            zone_id: non_neg_integer(),
            last_login: non_neg_integer() | nil,
            appearance: map() | nil
          }
  end

  @type t :: %__MODULE__{
          characters: [CharacterEntry.t()],
          max_characters: non_neg_integer()
        }

  @impl true
  def opcode, do: :server_character_list

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_uint32(packet.max_characters)
      |> PacketWriter.write_uint32(length(packet.characters))

    writer = Enum.reduce(packet.characters, writer, &write_character/2)

    {:ok, writer}
  end

  # Write a single character entry
  defp write_character(char, writer) do
    last_login_ts =
      case char.last_login do
        %DateTime{} = dt -> DateTime.to_unix(dt)
        nil -> 0
        ts when is_integer(ts) -> ts
      end

    writer
    |> PacketWriter.write_uint64(char.id)
    |> PacketWriter.write_wide_string(char.name)
    |> PacketWriter.write_uint32(char.sex)
    |> PacketWriter.write_uint32(char.race)
    |> PacketWriter.write_uint32(char.class)
    |> PacketWriter.write_uint32(char.path || 0)
    |> PacketWriter.write_uint32(char.faction_id)
    |> PacketWriter.write_uint32(char.level)
    |> PacketWriter.write_uint32(char.world_id || 0)
    |> PacketWriter.write_uint32(char.zone_id || 0)
    |> PacketWriter.write_uint64(last_login_ts)
    |> write_appearance(char.appearance)
  end

  # Write character appearance data
  defp write_appearance(writer, nil) do
    # Write default appearance (all zeros)
    writer
    |> PacketWriter.write_uint32(0)
    |> PacketWriter.write_uint32(0)
    |> PacketWriter.write_uint32(0)
    |> PacketWriter.write_uint32(0)
    |> PacketWriter.write_uint32(0)
    |> PacketWriter.write_uint32(0)
    |> PacketWriter.write_uint32(0)
    |> PacketWriter.write_uint32(0)
    |> PacketWriter.write_uint32(0)
    |> PacketWriter.write_uint32(0)
    |> PacketWriter.write_uint32(0)
    |> PacketWriter.write_uint32(0)
    |> PacketWriter.write_uint32(0)
    |> PacketWriter.write_uint32(0)
    |> PacketWriter.write_uint32(0)
    |> PacketWriter.write_uint32(0)
    |> PacketWriter.write_uint32(0)
    |> write_bones([])
  end

  defp write_appearance(writer, appearance) when is_map(appearance) do
    writer
    |> PacketWriter.write_uint32(get_field(appearance, :body_type))
    |> PacketWriter.write_uint32(get_field(appearance, :body_height))
    |> PacketWriter.write_uint32(get_field(appearance, :body_weight))
    |> PacketWriter.write_uint32(get_field(appearance, :face_type))
    |> PacketWriter.write_uint32(get_field(appearance, :eye_type))
    |> PacketWriter.write_uint32(get_field(appearance, :eye_color))
    |> PacketWriter.write_uint32(get_field(appearance, :nose_type))
    |> PacketWriter.write_uint32(get_field(appearance, :mouth_type))
    |> PacketWriter.write_uint32(get_field(appearance, :ear_type))
    |> PacketWriter.write_uint32(get_field(appearance, :hair_style))
    |> PacketWriter.write_uint32(get_field(appearance, :hair_color))
    |> PacketWriter.write_uint32(get_field(appearance, :facial_hair))
    |> PacketWriter.write_uint32(get_field(appearance, :skin_color))
    |> PacketWriter.write_uint32(get_field(appearance, :feature_1))
    |> PacketWriter.write_uint32(get_field(appearance, :feature_2))
    |> PacketWriter.write_uint32(get_field(appearance, :feature_3))
    |> PacketWriter.write_uint32(get_field(appearance, :feature_4))
    |> write_bones(get_field(appearance, :bones) || [])
  end

  # Write bone customization array
  defp write_bones(writer, bones) when is_list(bones) do
    writer
    |> PacketWriter.write_uint32(length(bones))
    |> write_bone_values(bones)
  end

  defp write_bone_values(writer, []), do: writer

  defp write_bone_values(writer, [bone | rest]) do
    writer
    |> PacketWriter.write_float32(bone)
    |> write_bone_values(rest)
  end

  # Get field from struct or map with default
  defp get_field(data, key) when is_struct(data), do: Map.get(data, key, 0) || 0
  defp get_field(data, key) when is_map(data), do: Map.get(data, key, 0) || 0

  @doc """
  Build a character list packet from database characters.
  """
  @spec from_characters([map()], non_neg_integer()) :: t()
  def from_characters(characters, max_characters \\ 12) do
    entries =
      Enum.map(characters, fn char ->
        %CharacterEntry{
          id: char.id,
          name: char.name,
          sex: char.sex,
          race: char.race,
          class: char.class,
          path: char.active_path,
          faction_id: char.faction_id,
          level: char.level,
          world_id: char.world_id,
          zone_id: char.world_zone_id,
          last_login: char.last_online,
          appearance: char.appearance
        }
      end)

    %__MODULE__{
      characters: entries,
      max_characters: max_characters
    }
  end
end
