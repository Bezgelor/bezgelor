defmodule BezgelorProtocol.Packets.World.ClientCharacterCreate do
  @moduledoc """
  Character creation request.

  ## Overview

  Client requests creation of a new character with specified
  attributes and appearance customization.

  ## Wire Format

  ```
  name        : wide_string - Character name (3-24 characters)
  sex         : uint32      - 0=male, 1=female
  race        : uint32      - Race ID
  class       : uint32      - Class ID
  path        : uint32      - Path ID (0-3)
  appearance  : AppearanceData - Character customization
  ```

  ## AppearanceData Format

  ```
  body_type   : uint32
  body_height : uint32
  body_weight : uint32
  face_type   : uint32
  eye_type    : uint32
  eye_color   : uint32
  nose_type   : uint32
  mouth_type  : uint32
  ear_type    : uint32
  hair_style  : uint32
  hair_color  : uint32
  facial_hair : uint32
  skin_color  : uint32
  feature_1   : uint32
  feature_2   : uint32
  feature_3   : uint32
  feature_4   : uint32
  bone_count  : uint32
  bones       : float32[] - bone_count float values
  ```
  """

  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [
    :name,
    :sex,
    :race,
    :class,
    :path,
    :appearance
  ]

  defmodule Appearance do
    @moduledoc "Character appearance customization data."
    defstruct [
      :body_type,
      :body_height,
      :body_weight,
      :face_type,
      :eye_type,
      :eye_color,
      :nose_type,
      :mouth_type,
      :ear_type,
      :hair_style,
      :hair_color,
      :facial_hair,
      :skin_color,
      :feature_1,
      :feature_2,
      :feature_3,
      :feature_4,
      bones: []
    ]

    @type t :: %__MODULE__{
            body_type: non_neg_integer(),
            body_height: non_neg_integer(),
            body_weight: non_neg_integer(),
            face_type: non_neg_integer(),
            eye_type: non_neg_integer(),
            eye_color: non_neg_integer(),
            nose_type: non_neg_integer(),
            mouth_type: non_neg_integer(),
            ear_type: non_neg_integer(),
            hair_style: non_neg_integer(),
            hair_color: non_neg_integer(),
            facial_hair: non_neg_integer(),
            skin_color: non_neg_integer(),
            feature_1: non_neg_integer(),
            feature_2: non_neg_integer(),
            feature_3: non_neg_integer(),
            feature_4: non_neg_integer(),
            bones: [float()]
          }
  end

  @type t :: %__MODULE__{
          name: String.t(),
          sex: non_neg_integer(),
          race: non_neg_integer(),
          class: non_neg_integer(),
          path: non_neg_integer(),
          appearance: Appearance.t()
        }

  @impl true
  def opcode, do: :client_character_create

  @impl true
  def read(reader) do
    with {:ok, name, reader} <- PacketReader.read_wide_string(reader),
         {:ok, sex, reader} <- PacketReader.read_uint32(reader),
         {:ok, race, reader} <- PacketReader.read_uint32(reader),
         {:ok, class, reader} <- PacketReader.read_uint32(reader),
         {:ok, path, reader} <- PacketReader.read_uint32(reader),
         {:ok, appearance, reader} <- read_appearance(reader) do
      packet = %__MODULE__{
        name: name,
        sex: sex,
        race: race,
        class: class,
        path: path,
        appearance: appearance
      }

      {:ok, packet, reader}
    end
  end

  defp read_appearance(reader) do
    with {:ok, body_type, reader} <- PacketReader.read_uint32(reader),
         {:ok, body_height, reader} <- PacketReader.read_uint32(reader),
         {:ok, body_weight, reader} <- PacketReader.read_uint32(reader),
         {:ok, face_type, reader} <- PacketReader.read_uint32(reader),
         {:ok, eye_type, reader} <- PacketReader.read_uint32(reader),
         {:ok, eye_color, reader} <- PacketReader.read_uint32(reader),
         {:ok, nose_type, reader} <- PacketReader.read_uint32(reader),
         {:ok, mouth_type, reader} <- PacketReader.read_uint32(reader),
         {:ok, ear_type, reader} <- PacketReader.read_uint32(reader),
         {:ok, hair_style, reader} <- PacketReader.read_uint32(reader),
         {:ok, hair_color, reader} <- PacketReader.read_uint32(reader),
         {:ok, facial_hair, reader} <- PacketReader.read_uint32(reader),
         {:ok, skin_color, reader} <- PacketReader.read_uint32(reader),
         {:ok, feature_1, reader} <- PacketReader.read_uint32(reader),
         {:ok, feature_2, reader} <- PacketReader.read_uint32(reader),
         {:ok, feature_3, reader} <- PacketReader.read_uint32(reader),
         {:ok, feature_4, reader} <- PacketReader.read_uint32(reader),
         {:ok, bones, reader} <- read_bones(reader) do
      appearance = %Appearance{
        body_type: body_type,
        body_height: body_height,
        body_weight: body_weight,
        face_type: face_type,
        eye_type: eye_type,
        eye_color: eye_color,
        nose_type: nose_type,
        mouth_type: mouth_type,
        ear_type: ear_type,
        hair_style: hair_style,
        hair_color: hair_color,
        facial_hair: facial_hair,
        skin_color: skin_color,
        feature_1: feature_1,
        feature_2: feature_2,
        feature_3: feature_3,
        feature_4: feature_4,
        bones: bones
      }

      {:ok, appearance, reader}
    end
  end

  defp read_bones(reader) do
    with {:ok, bone_count, reader} <- PacketReader.read_uint32(reader) do
      read_bone_values(reader, bone_count, [])
    end
  end

  defp read_bone_values(reader, 0, acc), do: {:ok, Enum.reverse(acc), reader}

  defp read_bone_values(reader, remaining, acc) do
    with {:ok, value, reader} <- PacketReader.read_float32(reader) do
      read_bone_values(reader, remaining - 1, [value | acc])
    end
  end

  @doc """
  Convert appearance packet data to database-compatible map.
  """
  @spec appearance_to_map(Appearance.t()) :: map()
  def appearance_to_map(%Appearance{} = appearance) do
    %{
      body_type: appearance.body_type,
      body_height: appearance.body_height,
      body_weight: appearance.body_weight,
      face_type: appearance.face_type,
      eye_type: appearance.eye_type,
      eye_color: appearance.eye_color,
      nose_type: appearance.nose_type,
      mouth_type: appearance.mouth_type,
      ear_type: appearance.ear_type,
      hair_style: appearance.hair_style,
      hair_color: appearance.hair_color,
      facial_hair: appearance.facial_hair,
      skin_color: appearance.skin_color,
      feature_1: appearance.feature_1,
      feature_2: appearance.feature_2,
      feature_3: appearance.feature_3,
      feature_4: appearance.feature_4,
      bones: appearance.bones
    }
  end
end
