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

  # Decor Management

  @spec place_decor(integer(), map()) :: {:ok, HousingDecor.t()} | {:error, term()}
  def place_decor(plot_id, attrs) do
    %HousingDecor{}
    |> HousingDecor.changeset(Map.put(attrs, :plot_id, plot_id))
    |> Repo.insert()
  end

  @spec get_decor(integer()) :: {:ok, HousingDecor.t()} | :error
  def get_decor(decor_id) do
    case Repo.get(HousingDecor, decor_id) do
      nil -> :error
      decor -> {:ok, decor}
    end
  end

  @spec move_decor(integer(), map()) :: {:ok, HousingDecor.t()} | {:error, term()}
  def move_decor(decor_id, attrs) do
    case get_decor(decor_id) do
      {:ok, decor} ->
        decor
        |> HousingDecor.move_changeset(attrs)
        |> Repo.update()

      :error ->
        {:error, :not_found}
    end
  end

  @spec remove_decor(integer()) :: :ok | {:error, :not_found}
  def remove_decor(decor_id) do
    case Repo.get(HousingDecor, decor_id) do
      nil -> {:error, :not_found}
      decor ->
        Repo.delete(decor)
        :ok
    end
  end

  @spec list_decor(integer()) :: [HousingDecor.t()]
  def list_decor(plot_id) do
    from(d in HousingDecor, where: d.plot_id == ^plot_id)
    |> Repo.all()
  end

  @spec list_decor(integer(), :interior | :exterior) :: [HousingDecor.t()]
  def list_decor(plot_id, :interior) do
    from(d in HousingDecor, where: d.plot_id == ^plot_id and d.is_exterior == false)
    |> Repo.all()
  end

  def list_decor(plot_id, :exterior) do
    from(d in HousingDecor, where: d.plot_id == ^plot_id and d.is_exterior == true)
    |> Repo.all()
  end

  @spec count_decor(integer()) :: non_neg_integer()
  def count_decor(plot_id) do
    from(d in HousingDecor, where: d.plot_id == ^plot_id, select: count(d.id))
    |> Repo.one()
  end

  # FABkit Management

  @spec install_fabkit(integer(), map()) :: {:ok, HousingFabkit.t()} | {:error, term()}
  def install_fabkit(plot_id, attrs) do
    %HousingFabkit{}
    |> HousingFabkit.changeset(Map.put(attrs, :plot_id, plot_id))
    |> Repo.insert()
  end

  @spec get_fabkit(integer()) :: {:ok, HousingFabkit.t()} | :error
  def get_fabkit(fabkit_id) do
    case Repo.get(HousingFabkit, fabkit_id) do
      nil -> :error
      fabkit -> {:ok, fabkit}
    end
  end

  @spec get_fabkit_at_socket(integer(), integer()) :: {:ok, HousingFabkit.t()} | :error
  def get_fabkit_at_socket(plot_id, socket_index) do
    query =
      from f in HousingFabkit,
        where: f.plot_id == ^plot_id and f.socket_index == ^socket_index

    case Repo.one(query) do
      nil -> :error
      fabkit -> {:ok, fabkit}
    end
  end

  @spec remove_fabkit(integer()) :: :ok | {:error, :not_found}
  def remove_fabkit(fabkit_id) do
    case Repo.get(HousingFabkit, fabkit_id) do
      nil -> {:error, :not_found}
      fabkit ->
        Repo.delete(fabkit)
        :ok
    end
  end

  @spec update_fabkit_state(integer(), map()) :: {:ok, HousingFabkit.t()} | {:error, term()}
  def update_fabkit_state(fabkit_id, state) do
    case get_fabkit(fabkit_id) do
      {:ok, fabkit} ->
        fabkit
        |> HousingFabkit.state_changeset(%{state: state})
        |> Repo.update()

      :error ->
        {:error, :not_found}
    end
  end

  @spec list_fabkits(integer()) :: [HousingFabkit.t()]
  def list_fabkits(plot_id) do
    from(f in HousingFabkit, where: f.plot_id == ^plot_id, order_by: f.socket_index)
    |> Repo.all()
  end
end
