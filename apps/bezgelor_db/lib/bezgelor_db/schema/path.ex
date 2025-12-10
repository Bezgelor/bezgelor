defmodule BezgelorDb.Schema.Path do
  @moduledoc """
  Schema for character path progression (Soldier, Settler, Scientist, Explorer).

  ## Path Types

  - `0` - Soldier - Combat-focused missions
  - `1` - Settler - Building and social missions
  - `2` - Scientist - Discovery and lore missions
  - `3` - Explorer - Exploration and jumping puzzles

  ## Progression

  Each path has its own XP pool and level (1-30).
  Path missions reward path XP and unlock abilities.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @path_soldier 0
  @path_settler 1
  @path_scientist 2
  @path_explorer 3

  @max_level 30

  schema "character_paths" do
    belongs_to :character, BezgelorDb.Schema.Character

    # Path type (0=Soldier, 1=Settler, 2=Scientist, 3=Explorer)
    field :path_type, :integer

    # Progression
    field :path_xp, :integer, default: 0
    field :path_level, :integer, default: 1

    # Unlocked abilities (list of ability IDs)
    field :unlocked_abilities, {:array, :integer}, default: []

    timestamps(type: :utc_datetime)
  end

  def changeset(path, attrs) do
    path
    |> cast(attrs, [:character_id, :path_type, :path_xp, :path_level, :unlocked_abilities])
    |> validate_required([:character_id, :path_type])
    |> validate_inclusion(:path_type, [@path_soldier, @path_settler, @path_scientist, @path_explorer])
    |> validate_number(:path_level, greater_than_or_equal_to: 1, less_than_or_equal_to: @max_level)
    |> validate_number(:path_xp, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:character_id)
    |> unique_constraint([:character_id], name: :character_paths_character_id_index)
  end

  def xp_changeset(path, xp, level) do
    path
    |> cast(%{path_xp: xp, path_level: level}, [:path_xp, :path_level])
    |> validate_number(:path_level, greater_than_or_equal_to: 1, less_than_or_equal_to: @max_level)
  end

  def unlock_ability_changeset(path, ability_id) do
    new_abilities =
      if ability_id in path.unlocked_abilities do
        path.unlocked_abilities
      else
        [ability_id | path.unlocked_abilities]
      end

    path
    |> change(unlocked_abilities: new_abilities)
  end
end
