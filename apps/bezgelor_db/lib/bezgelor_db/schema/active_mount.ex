defmodule BezgelorDb.Schema.ActiveMount do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "active_mounts" do
    belongs_to :character, BezgelorDb.Schema.Character

    field :mount_id, :integer
    field :customization, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  def changeset(mount, attrs) do
    mount
    |> cast(attrs, [:character_id, :mount_id, :customization])
    |> validate_required([:character_id, :mount_id])
    |> foreign_key_constraint(:character_id)
    |> unique_constraint(:character_id)
  end

  def customization_changeset(mount, customization) do
    mount
    |> change(customization: customization)
  end
end
