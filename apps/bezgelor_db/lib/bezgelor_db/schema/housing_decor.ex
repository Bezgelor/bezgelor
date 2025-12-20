defmodule BezgelorDb.Schema.HousingDecor do
  @moduledoc """
  Schema for placed housing decor items.

  Stores full free-form placement: position, rotation (euler angles),
  and uniform scale.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "housing_decor" do
    belongs_to(:plot, BezgelorDb.Schema.HousingPlot)

    field(:decor_id, :integer)

    # Position
    field(:pos_x, :float, default: 0.0)
    field(:pos_y, :float, default: 0.0)
    field(:pos_z, :float, default: 0.0)

    # Rotation (euler angles in degrees)
    field(:rot_pitch, :float, default: 0.0)
    field(:rot_yaw, :float, default: 0.0)
    field(:rot_roll, :float, default: 0.0)

    # Scale
    field(:scale, :float, default: 1.0)

    # Interior vs exterior
    field(:is_exterior, :boolean, default: false)

    field(:placed_at, :utc_datetime)
  end

  def changeset(decor, attrs) do
    decor
    |> cast(attrs, [
      :plot_id,
      :decor_id,
      :pos_x,
      :pos_y,
      :pos_z,
      :rot_pitch,
      :rot_yaw,
      :rot_roll,
      :scale,
      :is_exterior
    ])
    |> validate_required([:plot_id, :decor_id])
    |> validate_number(:scale, greater_than: 0.0, less_than_or_equal_to: 10.0)
    |> put_change(:placed_at, DateTime.utc_now() |> DateTime.truncate(:second))
    |> foreign_key_constraint(:plot_id)
  end

  def move_changeset(decor, attrs) do
    decor
    |> cast(attrs, [:pos_x, :pos_y, :pos_z, :rot_pitch, :rot_yaw, :rot_roll, :scale])
    |> validate_number(:scale, greater_than: 0.0, less_than_or_equal_to: 10.0)
  end
end
