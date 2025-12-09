defmodule BezgelorDb.Schema.Character do
  @moduledoc """
  Database schema for player characters.

  ## Overview

  Characters are the playable entities in the game world. Each account
  can have multiple characters. Characters store persistent state like
  level, position, and various progression data.

  ## Fields

  ### Identity
  - `name` - Unique character name (3-24 characters)
  - `sex` - Character sex (0 = male, 1 = female)
  - `race` - Race ID (Human, Aurin, etc.)
  - `class` - Class ID (Warrior, Esper, etc.)
  - `faction_id` - Faction (Exile or Dominion)

  ### Progression
  - `level` - Current level (1-50)
  - `total_xp` - Total experience points earned
  - `rest_bonus_xp` - Rested XP bonus

  ### Position
  - `location_x/y/z` - World coordinates
  - `rotation_x/y/z` - Character facing
  - `world_id` - Current world/continent
  - `world_zone_id` - Current zone within world

  ## Associations

  - `belongs_to :account` - The owning account
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BezgelorDb.Schema.Account

  @type t :: %__MODULE__{
          id: integer() | nil,
          account_id: integer() | nil,
          account: Account.t() | Ecto.Association.NotLoaded.t() | nil,
          name: String.t() | nil,
          sex: integer() | nil,
          race: integer() | nil,
          class: integer() | nil,
          level: integer(),
          faction_id: integer() | nil,
          location_x: float(),
          location_y: float(),
          location_z: float(),
          rotation_x: float(),
          rotation_y: float(),
          rotation_z: float(),
          world_id: integer() | nil,
          world_zone_id: integer() | nil,
          title: integer(),
          active_path: integer(),
          active_costume_index: integer(),
          active_spec: integer(),
          innate_index: integer(),
          total_xp: integer(),
          rest_bonus_xp: integer(),
          time_played_total: integer(),
          time_played_level: integer(),
          flags: integer(),
          last_online: DateTime.t() | nil,
          deleted_at: DateTime.t() | nil,
          original_name: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "characters" do
    belongs_to :account, Account

    field :name, :string
    field :sex, :integer
    field :race, :integer
    field :class, :integer
    field :level, :integer, default: 1
    field :faction_id, :integer

    # Position
    field :location_x, :float, default: 0.0
    field :location_y, :float, default: 0.0
    field :location_z, :float, default: 0.0
    field :rotation_x, :float, default: 0.0
    field :rotation_y, :float, default: 0.0
    field :rotation_z, :float, default: 0.0
    field :world_id, :integer
    field :world_zone_id, :integer

    # State
    field :title, :integer, default: 0
    field :active_path, :integer, default: 0
    field :active_costume_index, :integer, default: -1
    field :active_spec, :integer, default: 0
    field :innate_index, :integer, default: 0
    field :total_xp, :integer, default: 0
    field :rest_bonus_xp, :integer, default: 0
    field :time_played_total, :integer, default: 0
    field :time_played_level, :integer, default: 0
    field :flags, :integer, default: 0

    # Timestamps
    field :last_online, :utc_datetime
    field :deleted_at, :utc_datetime
    field :original_name, :string

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(account_id name sex race class faction_id world_id world_zone_id)a
  @optional_fields ~w(level location_x location_y location_z rotation_x rotation_y rotation_z
                      title active_path active_costume_index active_spec innate_index
                      total_xp rest_bonus_xp time_played_total time_played_level flags
                      last_online deleted_at original_name)a

  @doc """
  Build a changeset for creating or updating a character.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(character, attrs) do
    character
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:name, min: 3, max: 24)
    |> foreign_key_constraint(:account_id)
    |> unique_constraint(:name)
  end

  @doc """
  Changeset for updating character position.
  """
  @spec position_changeset(t(), map()) :: Ecto.Changeset.t()
  def position_changeset(character, attrs) do
    character
    |> cast(attrs, [:location_x, :location_y, :location_z,
                    :rotation_x, :rotation_y, :rotation_z,
                    :world_id, :world_zone_id])
  end

  @doc """
  Changeset for soft-deleting a character.
  """
  @spec delete_changeset(t()) :: Ecto.Changeset.t()
  def delete_changeset(character) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    character
    |> change(deleted_at: now, original_name: character.name)
  end
end
