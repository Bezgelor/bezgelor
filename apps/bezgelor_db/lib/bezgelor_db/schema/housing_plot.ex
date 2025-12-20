defmodule BezgelorDb.Schema.HousingPlot do
  @moduledoc """
  Schema for character housing plots.

  Each character owns one plot with customizable house type,
  theme settings, and permission level.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @permission_levels [:private, :neighbors, :roommates, :public]

  schema "housing_plots" do
    belongs_to(:character, BezgelorDb.Schema.Character)

    field(:house_type_id, :integer, default: 1)
    field(:permission_level, Ecto.Enum, values: @permission_levels, default: :private)
    field(:sky_id, :integer, default: 1)
    field(:ground_id, :integer, default: 1)
    field(:music_id, :integer, default: 1)
    field(:plot_name, :string)

    has_many(:decor, BezgelorDb.Schema.HousingDecor, foreign_key: :plot_id)
    has_many(:fabkits, BezgelorDb.Schema.HousingFabkit, foreign_key: :plot_id)
    has_many(:neighbors, BezgelorDb.Schema.HousingNeighbor, foreign_key: :plot_id)

    timestamps(type: :utc_datetime)
  end

  def changeset(plot, attrs) do
    plot
    |> cast(attrs, [
      :character_id,
      :house_type_id,
      :permission_level,
      :sky_id,
      :ground_id,
      :music_id,
      :plot_name
    ])
    |> validate_required([:character_id])
    |> validate_inclusion(:house_type_id, [1, 2])
    |> validate_inclusion(:permission_level, @permission_levels)
    |> validate_length(:plot_name, max: 64)
    |> foreign_key_constraint(:character_id)
    |> unique_constraint(:character_id)
  end

  def theme_changeset(plot, attrs) do
    plot
    |> cast(attrs, [:sky_id, :ground_id, :music_id, :plot_name])
    |> validate_length(:plot_name, max: 64)
  end

  def permission_changeset(plot, attrs) do
    plot
    |> cast(attrs, [:permission_level])
    |> validate_inclusion(:permission_level, @permission_levels)
  end

  def upgrade_changeset(plot, attrs) do
    plot
    |> cast(attrs, [:house_type_id])
    |> validate_inclusion(:house_type_id, [1, 2])
  end

  @doc "Get valid permission levels."
  def permission_levels, do: @permission_levels
end
