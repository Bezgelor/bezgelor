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

  # Neighbor Management

  @spec add_neighbor(integer(), integer()) :: {:ok, HousingNeighbor.t()} | {:error, term()}
  def add_neighbor(plot_id, character_id) do
    %HousingNeighbor{}
    |> HousingNeighbor.changeset(%{plot_id: plot_id, character_id: character_id})
    |> Repo.insert()
  end

  @spec remove_neighbor(integer(), integer()) :: :ok | {:error, :not_found}
  def remove_neighbor(plot_id, character_id) do
    query =
      from n in HousingNeighbor,
        where: n.plot_id == ^plot_id and n.character_id == ^character_id

    case Repo.delete_all(query) do
      {0, _} -> {:error, :not_found}
      {_, _} -> :ok
    end
  end

  @spec promote_to_roommate(integer(), integer()) :: {:ok, HousingNeighbor.t()} | {:error, term()}
  def promote_to_roommate(plot_id, character_id) do
    case get_neighbor(plot_id, character_id) do
      {:ok, neighbor} ->
        neighbor
        |> HousingNeighbor.roommate_changeset(%{is_roommate: true})
        |> Repo.update()

      :error ->
        {:error, :not_found}
    end
  end

  @spec demote_from_roommate(integer(), integer()) :: {:ok, HousingNeighbor.t()} | {:error, term()}
  def demote_from_roommate(plot_id, character_id) do
    case get_neighbor(plot_id, character_id) do
      {:ok, neighbor} ->
        neighbor
        |> HousingNeighbor.roommate_changeset(%{is_roommate: false})
        |> Repo.update()

      :error ->
        {:error, :not_found}
    end
  end

  @spec list_neighbors(integer()) :: [HousingNeighbor.t()]
  def list_neighbors(plot_id) do
    from(n in HousingNeighbor, where: n.plot_id == ^plot_id, preload: [:character])
    |> Repo.all()
  end

  @spec is_neighbor?(integer(), integer()) :: boolean()
  def is_neighbor?(plot_id, character_id) do
    query =
      from n in HousingNeighbor,
        where: n.plot_id == ^plot_id and n.character_id == ^character_id

    Repo.exists?(query)
  end

  @spec is_roommate?(integer(), integer()) :: boolean()
  def is_roommate?(plot_id, character_id) do
    query =
      from n in HousingNeighbor,
        where: n.plot_id == ^plot_id and n.character_id == ^character_id and n.is_roommate == true

    Repo.exists?(query)
  end

  @spec can_visit?(integer(), integer()) :: boolean()
  def can_visit?(plot_id, visitor_character_id) do
    case get_plot_by_id(plot_id) do
      {:ok, plot} ->
        cond do
          # Owner can always visit
          plot.character_id == visitor_character_id -> true
          # Public plots allow anyone
          plot.permission_level == :public -> true
          # Check neighbor/roommate permission
          plot.permission_level in [:neighbors, :roommates] -> is_neighbor?(plot_id, visitor_character_id)
          # Private - only owner
          true -> false
        end

      :error ->
        false
    end
  end

  @spec can_decorate?(integer(), integer()) :: boolean()
  def can_decorate?(plot_id, character_id) do
    case get_plot_by_id(plot_id) do
      {:ok, plot} ->
        # Owner or roommate can decorate
        plot.character_id == character_id or is_roommate?(plot_id, character_id)

      :error ->
        false
    end
  end

  defp get_neighbor(plot_id, character_id) do
    query =
      from n in HousingNeighbor,
        where: n.plot_id == ^plot_id and n.character_id == ^character_id

    case Repo.one(query) do
      nil -> :error
      neighbor -> {:ok, neighbor}
    end
  end
end
