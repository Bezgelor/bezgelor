defmodule BezgelorDb.Warplots do
  @moduledoc """
  Context module for warplot management.

  Provides functions for:
  - Warplot ownership and creation
  - Plug installation and upgrades
  - War coin management
  - Battle recording
  """

  import Ecto.Query

  alias BezgelorDb.Repo
  alias BezgelorDb.Schema.{Warplot, WarplotPlug}

  # =============================================================================
  # Warplot Management
  # =============================================================================

  @doc """
  Creates a warplot for a guild.
  """
  @spec create_warplot(integer(), String.t()) :: {:ok, Warplot.t()} | {:error, Ecto.Changeset.t()}
  def create_warplot(guild_id, name) do
    %Warplot{}
    |> Warplot.changeset(%{
      guild_id: guild_id,
      name: name,
      created_at: DateTime.utc_now()
    })
    |> Repo.insert()
  end

  @doc """
  Gets a warplot by ID.
  """
  @spec get_warplot(integer()) :: Warplot.t() | nil
  def get_warplot(warplot_id) do
    Repo.get(Warplot, warplot_id)
  end

  @doc """
  Gets a warplot by guild ID.
  """
  @spec get_warplot_by_guild(integer()) :: Warplot.t() | nil
  def get_warplot_by_guild(guild_id) do
    Repo.get_by(Warplot, guild_id: guild_id)
  end

  @doc """
  Gets a warplot with plugs preloaded.
  """
  @spec get_warplot_with_plugs(integer()) :: Warplot.t() | nil
  def get_warplot_with_plugs(warplot_id) do
    Warplot
    |> where([w], w.id == ^warplot_id)
    |> preload(:plugs)
    |> Repo.one()
  end

  @doc """
  Adds war coins to a warplot.
  """
  @spec add_war_coins(integer(), integer()) :: {:ok, Warplot.t()} | {:error, term()}
  def add_war_coins(warplot_id, amount) when amount > 0 do
    case get_warplot(warplot_id) do
      nil ->
        {:error, :not_found}

      warplot ->
        warplot
        |> Warplot.add_war_coins(amount)
        |> Repo.update()
    end
  end

  @doc """
  Spends war coins from a warplot.
  """
  @spec spend_war_coins(integer(), integer()) :: {:ok, Warplot.t()} | {:error, term()}
  def spend_war_coins(warplot_id, amount) when amount > 0 do
    case get_warplot(warplot_id) do
      nil ->
        {:error, :not_found}

      warplot ->
        case Warplot.spend_war_coins(warplot, amount) do
          {:ok, changeset} -> Repo.update(changeset)
          {:error, reason} -> {:error, reason}
        end
    end
  end

  @doc """
  Records a battle result.
  """
  @spec record_battle(integer(), boolean(), integer()) :: {:ok, Warplot.t()} | {:error, term()}
  def record_battle(warplot_id, won, rating_change) do
    case get_warplot(warplot_id) do
      nil ->
        {:error, :not_found}

      warplot ->
        warplot
        |> Warplot.record_battle(won, rating_change)
        |> Repo.update()
    end
  end

  @doc """
  Adjusts warplot energy.
  """
  @spec adjust_energy(integer(), integer()) :: {:ok, Warplot.t()} | {:error, term()}
  def adjust_energy(warplot_id, delta) do
    case get_warplot(warplot_id) do
      nil ->
        {:error, :not_found}

      warplot ->
        warplot
        |> Warplot.adjust_energy(delta)
        |> Repo.update()
    end
  end

  @doc """
  Checks if a warplot can queue for battle.
  """
  @spec can_queue?(integer()) :: boolean()
  def can_queue?(warplot_id) do
    case get_warplot(warplot_id) do
      nil -> false
      warplot -> Warplot.can_battle?(warplot)
    end
  end

  # =============================================================================
  # Plug Management
  # =============================================================================

  @doc """
  Installs a plug in a socket.
  """
  @spec install_plug(integer(), integer(), integer()) :: {:ok, WarplotPlug.t()} | {:error, term()}
  def install_plug(warplot_id, plug_id, socket_id) do
    warplot = get_warplot(warplot_id)

    cond do
      is_nil(warplot) ->
        {:error, :warplot_not_found}

      socket_occupied?(warplot_id, socket_id) ->
        {:error, :socket_occupied}

      socket_id < 1 or socket_id > WarplotPlug.socket_count() ->
        {:error, :invalid_socket}

      true ->
        %WarplotPlug{}
        |> WarplotPlug.changeset(%{
          warplot_id: warplot_id,
          plug_id: plug_id,
          socket_id: socket_id,
          installed_at: DateTime.utc_now()
        })
        |> Repo.insert()
    end
  end

  @doc """
  Removes a plug from a socket.
  """
  @spec remove_plug(integer(), integer()) :: {:ok, WarplotPlug.t()} | {:error, term()}
  def remove_plug(warplot_id, socket_id) do
    case get_plug(warplot_id, socket_id) do
      nil -> {:error, :plug_not_found}
      plug -> Repo.delete(plug)
    end
  end

  @doc """
  Gets a plug in a specific socket.
  """
  @spec get_plug(integer(), integer()) :: WarplotPlug.t() | nil
  def get_plug(warplot_id, socket_id) do
    Repo.get_by(WarplotPlug, warplot_id: warplot_id, socket_id: socket_id)
  end

  @doc """
  Gets all plugs for a warplot.
  """
  @spec get_plugs(integer()) :: [WarplotPlug.t()]
  def get_plugs(warplot_id) do
    WarplotPlug
    |> where([p], p.warplot_id == ^warplot_id)
    |> order_by([p], asc: p.socket_id)
    |> Repo.all()
  end

  @doc """
  Checks if a socket is occupied.
  """
  @spec socket_occupied?(integer(), integer()) :: boolean()
  def socket_occupied?(warplot_id, socket_id) do
    WarplotPlug
    |> where([p], p.warplot_id == ^warplot_id and p.socket_id == ^socket_id)
    |> Repo.exists?()
  end

  @doc """
  Upgrades a plug.
  """
  @spec upgrade_plug(integer(), integer()) :: {:ok, WarplotPlug.t()} | {:error, term()}
  def upgrade_plug(warplot_id, socket_id) do
    case get_plug(warplot_id, socket_id) do
      nil ->
        {:error, :plug_not_found}

      plug ->
        case WarplotPlug.upgrade(plug) do
          {:ok, changeset} -> Repo.update(changeset)
          {:error, reason} -> {:error, reason}
        end
    end
  end

  @doc """
  Applies damage to a plug.
  """
  @spec damage_plug(integer(), integer(), integer()) :: {:ok, WarplotPlug.t()} | {:error, term()}
  def damage_plug(warplot_id, socket_id, damage_percent) do
    case get_plug(warplot_id, socket_id) do
      nil ->
        {:error, :plug_not_found}

      plug ->
        plug
        |> WarplotPlug.apply_damage(damage_percent)
        |> Repo.update()
    end
  end

  @doc """
  Repairs a plug.
  """
  @spec repair_plug(integer(), integer(), integer()) :: {:ok, WarplotPlug.t()} | {:error, term()}
  def repair_plug(warplot_id, socket_id, repair_percent) do
    case get_plug(warplot_id, socket_id) do
      nil ->
        {:error, :plug_not_found}

      plug ->
        plug
        |> WarplotPlug.repair(repair_percent)
        |> Repo.update()
    end
  end

  @doc """
  Fully repairs all plugs for a warplot.
  """
  @spec repair_all_plugs(integer()) :: {integer(), nil}
  def repair_all_plugs(warplot_id) do
    WarplotPlug
    |> where([p], p.warplot_id == ^warplot_id)
    |> Repo.update_all(set: [health_percent: 100])
  end

  # =============================================================================
  # Leaderboards
  # =============================================================================

  @doc """
  Gets warplot leaderboard.
  """
  @spec get_leaderboard(integer()) :: [Warplot.t()]
  def get_leaderboard(limit \\ 100) do
    Warplot
    |> where([w], w.battles_played >= 10)
    |> order_by([w], desc: w.rating)
    |> limit(^limit)
    |> preload(:guild)
    |> Repo.all()
  end

  # =============================================================================
  # Season Management
  # =============================================================================

  @doc """
  Resets warplot ratings for a new season.
  """
  @spec reset_for_season() :: {integer(), nil}
  def reset_for_season do
    from(w in Warplot,
      update: [
        set: [
          rating: fragment("? / 2", w.rating),
          season_high: fragment("? / 2", w.rating),
          battles_played: 0,
          battles_won: 0
        ]
      ]
    )
    |> Repo.update_all([])
  end
end
