defmodule BezgelorDb.Housing do
  @moduledoc """
  Housing system database operations.

  Manages plots, decor, FABkits, and neighbor permissions.
  """

  import Ecto.Query
  alias BezgelorDb.Repo
  alias BezgelorDb.Schema.{HousingPlot, HousingNeighbor, HousingDecor, HousingFabkit}

  # Plot Lifecycle

  @spec create_plot(integer()) :: {:ok, HousingPlot.t()} | {:error, term()}
  def create_plot(character_id) do
    %HousingPlot{}
    |> HousingPlot.changeset(%{character_id: character_id})
    |> Repo.insert()
  end

  @spec get_plot(integer()) :: {:ok, HousingPlot.t()} | :error
  def get_plot(character_id) do
    query =
      from p in HousingPlot,
        where: p.character_id == ^character_id,
        preload: [:decor, :fabkits, :neighbors]

    case Repo.one(query) do
      nil -> :error
      plot -> {:ok, plot}
    end
  end

  @spec get_plot_by_id(integer()) :: {:ok, HousingPlot.t()} | :error
  def get_plot_by_id(plot_id) do
    query =
      from p in HousingPlot,
        where: p.id == ^plot_id,
        preload: [:decor, :fabkits, :neighbors]

    case Repo.one(query) do
      nil -> :error
      plot -> {:ok, plot}
    end
  end

  @spec upgrade_house(integer(), integer()) :: {:ok, HousingPlot.t()} | {:error, term()}
  def upgrade_house(character_id, house_type_id) do
    case get_plot(character_id) do
      {:ok, plot} ->
        plot
        |> HousingPlot.upgrade_changeset(%{house_type_id: house_type_id})
        |> Repo.update()

      :error ->
        {:error, :not_found}
    end
  end

  @spec update_plot_theme(integer(), map()) :: {:ok, HousingPlot.t()} | {:error, term()}
  def update_plot_theme(character_id, attrs) do
    case get_plot(character_id) do
      {:ok, plot} ->
        plot
        |> HousingPlot.theme_changeset(attrs)
        |> Repo.update()

      :error ->
        {:error, :not_found}
    end
  end

  @spec set_permission_level(integer(), atom()) :: {:ok, HousingPlot.t()} | {:error, term()}
  def set_permission_level(character_id, level) do
    case get_plot(character_id) do
      {:ok, plot} ->
        plot
        |> HousingPlot.permission_changeset(%{permission_level: level})
        |> Repo.update()

      :error ->
        {:error, :not_found}
    end
  end
end
