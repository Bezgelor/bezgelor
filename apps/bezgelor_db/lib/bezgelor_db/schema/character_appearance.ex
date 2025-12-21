defmodule BezgelorDb.Schema.CharacterAppearance do
  @moduledoc """
  Database schema for character appearance/customization.

  ## Overview

  WildStar has extensive character customization. This schema stores all
  the visual customization options selected during character creation.

  ## Fields

  ### Body
  - `body_type` - Body shape preset
  - `body_height` - Height slider value
  - `body_weight` - Weight slider value

  ### Face
  - `face_type` - Face shape preset
  - `eye_type` - Eye shape
  - `eye_color` - Eye color index
  - `nose_type` - Nose shape
  - `mouth_type` - Mouth shape
  - `ear_type` - Ear shape (race-dependent)

  ### Hair
  - `hair_style` - Hair style index
  - `hair_color` - Hair color index
  - `facial_hair` - Facial hair style (race/sex dependent)

  ### Skin
  - `skin_color` - Skin color/tone index

  ### Race-Specific Features
  - `feature_1` through `feature_4` - Race-specific customizations
    (e.g., Aurin ear/tail styles, Mordesh decay patterns)

  ### Bone Customization
  - `bones` - Array of bone slider values for fine-grained face/body tuning
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BezgelorDb.Schema.Character

  @type t :: %__MODULE__{
          id: integer() | nil,
          character_id: integer() | nil,
          character: Character.t() | Ecto.Association.NotLoaded.t() | nil,
          body_type: integer(),
          body_height: integer(),
          body_weight: integer(),
          face_type: integer(),
          eye_type: integer(),
          eye_color: integer(),
          nose_type: integer(),
          mouth_type: integer(),
          ear_type: integer(),
          hair_style: integer(),
          hair_color: integer(),
          facial_hair: integer(),
          skin_color: integer(),
          feature_1: integer(),
          feature_2: integer(),
          feature_3: integer(),
          feature_4: integer(),
          bones: list(float()),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "character_appearances" do
    belongs_to(:character, Character)

    # Body
    field(:body_type, :integer, default: 0)
    field(:body_height, :integer, default: 0)
    field(:body_weight, :integer, default: 0)

    # Face
    field(:face_type, :integer, default: 0)
    field(:eye_type, :integer, default: 0)
    field(:eye_color, :integer, default: 0)
    field(:nose_type, :integer, default: 0)
    field(:mouth_type, :integer, default: 0)
    field(:ear_type, :integer, default: 0)

    # Hair
    field(:hair_style, :integer, default: 0)
    field(:hair_color, :integer, default: 0)
    field(:facial_hair, :integer, default: 0)

    # Skin
    field(:skin_color, :integer, default: 0)

    # Race-specific features
    field(:feature_1, :integer, default: 0)
    field(:feature_2, :integer, default: 0)
    field(:feature_3, :integer, default: 0)
    field(:feature_4, :integer, default: 0)

    # Bone customization sliders
    field(:bones, {:array, :float}, default: [])

    # Raw customization label/value pairs (sent back to client in character list)
    field(:labels, {:array, :integer}, default: [])
    field(:values, {:array, :integer}, default: [])

    # Computed ItemVisual entries for body appearance (head, hands, feet, etc.)
    # Each entry is a map with :slot and :display_id
    # Computed from labels/values using CharacterCustomization table
    field(:visuals, {:array, :map}, default: [])

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(character_id)a
  @optional_fields ~w(body_type body_height body_weight
                      face_type eye_type eye_color nose_type mouth_type ear_type
                      hair_style hair_color facial_hair
                      skin_color
                      feature_1 feature_2 feature_3 feature_4
                      bones labels values visuals)a

  @doc """
  Build a changeset for creating or updating character appearance.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(appearance, attrs) do
    appearance
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:character_id)
    |> unique_constraint(:character_id)
  end

  @doc """
  Create changeset for a new character appearance.
  """
  @spec create_changeset(map()) :: Ecto.Changeset.t()
  def create_changeset(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
  end
end
