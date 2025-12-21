defmodule BezgelorDb.Schema.HousingFabkit do
  @moduledoc """
  Schema for installed housing FABkits.

  FABkits are functional plugs in the 6 outdoor sockets (0-3 small, 4-5 large).
  State map stores type-specific data like harvest cooldowns.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "housing_fabkits" do
    belongs_to(:plot, BezgelorDb.Schema.HousingPlot)

    field(:socket_index, :integer)
    field(:fabkit_id, :integer)
    field(:state, :map, default: %{})

    field(:installed_at, :utc_datetime)
  end

  def changeset(fabkit, attrs) do
    fabkit
    |> cast(attrs, [:plot_id, :socket_index, :fabkit_id, :state])
    |> validate_required([:plot_id, :socket_index, :fabkit_id])
    |> validate_number(:socket_index, greater_than_or_equal_to: 0, less_than_or_equal_to: 5)
    |> put_change(:installed_at, DateTime.utc_now() |> DateTime.truncate(:second))
    |> foreign_key_constraint(:plot_id)
    |> unique_constraint([:plot_id, :socket_index])
  end

  def state_changeset(fabkit, attrs) do
    fabkit
    |> cast(attrs, [:state])
  end
end
