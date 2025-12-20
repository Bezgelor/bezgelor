defmodule BezgelorDb.Schema.ActivePet do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @max_level 25

  schema "active_pets" do
    belongs_to(:character, BezgelorDb.Schema.Character)

    field(:pet_id, :integer)
    field(:level, :integer, default: 1)
    field(:xp, :integer, default: 0)
    field(:nickname, :string)

    timestamps(type: :utc_datetime)
  end

  def changeset(pet, attrs) do
    pet
    |> cast(attrs, [:character_id, :pet_id, :level, :xp, :nickname])
    |> validate_required([:character_id, :pet_id])
    |> validate_number(:level, greater_than_or_equal_to: 1, less_than_or_equal_to: @max_level)
    |> validate_number(:xp, greater_than_or_equal_to: 0)
    |> validate_length(:nickname, max: 20)
    |> foreign_key_constraint(:character_id)
    |> unique_constraint(:character_id)
  end

  def xp_changeset(pet, xp, level) do
    pet
    |> cast(%{xp: xp, level: level}, [:xp, :level])
  end

  def nickname_changeset(pet, nickname) do
    pet
    |> cast(%{nickname: nickname}, [:nickname])
    |> validate_length(:nickname, max: 20)
  end

  def max_level, do: @max_level
end
