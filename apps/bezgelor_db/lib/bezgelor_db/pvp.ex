defmodule BezgelorDb.PvP do
  @moduledoc """
  Context module for PvP statistics, ratings, and seasons.

  Provides functions for:
  - Character PvP statistics tracking
  - Per-bracket rating management
  - Season management and rewards
  """

  import Ecto.Query

  alias BezgelorDb.Repo
  alias BezgelorDb.Schema.{PvpStats, PvpRating, PvpSeason}

  # =============================================================================
  # PvP Stats
  # =============================================================================

  @doc """
  Gets or creates PvP stats for a character.
  """
  @spec get_or_create_stats(integer()) :: {:ok, PvpStats.t()} | {:error, term()}
  def get_or_create_stats(character_id) do
    case get_stats(character_id) do
      nil ->
        %PvpStats{}
        |> PvpStats.changeset(%{character_id: character_id})
        |> Repo.insert()

      stats ->
        {:ok, stats}
    end
  end

  @doc """
  Gets PvP stats for a character.
  """
  @spec get_stats(integer()) :: PvpStats.t() | nil
  def get_stats(character_id) do
    Repo.get_by(PvpStats, character_id: character_id)
  end

  @doc """
  Records a PvP kill for a character.
  """
  @spec record_kill(integer(), keyword()) :: {:ok, PvpStats.t()} | {:error, term()}
  def record_kill(character_id, opts \\ []) do
    with {:ok, stats} <- get_or_create_stats(character_id) do
      stats
      |> PvpStats.record_kill(opts)
      |> Repo.update()
    end
  end

  @doc """
  Records a death for a character.
  """
  @spec record_death(integer()) :: {:ok, PvpStats.t()} | {:error, term()}
  def record_death(character_id) do
    with {:ok, stats} <- get_or_create_stats(character_id) do
      stats
      |> PvpStats.record_death()
      |> Repo.update()
    end
  end

  @doc """
  Records a duel result.
  """
  @spec record_duel(integer(), boolean()) :: {:ok, PvpStats.t()} | {:error, term()}
  def record_duel(character_id, won) do
    with {:ok, stats} <- get_or_create_stats(character_id) do
      stats
      |> PvpStats.record_duel(won)
      |> Repo.update()
    end
  end

  @doc """
  Records a battleground result.
  """
  @spec record_battleground(integer(), boolean()) :: {:ok, PvpStats.t()} | {:error, term()}
  def record_battleground(character_id, won) do
    with {:ok, stats} <- get_or_create_stats(character_id) do
      stats
      |> PvpStats.record_battleground(won)
      |> Repo.update()
    end
  end

  @doc """
  Records an arena result.
  """
  @spec record_arena(integer(), boolean()) :: {:ok, PvpStats.t()} | {:error, term()}
  def record_arena(character_id, won) do
    with {:ok, stats} <- get_or_create_stats(character_id) do
      stats
      |> PvpStats.record_arena(won)
      |> Repo.update()
    end
  end

  @doc """
  Adds currency to a character's stats.
  """
  @spec add_currency(integer(), :conquest | :honor, integer()) ::
          {:ok, PvpStats.t()} | {:error, term()}
  def add_currency(character_id, currency_type, amount) do
    with {:ok, stats} <- get_or_create_stats(character_id) do
      stats
      |> PvpStats.add_currency(currency_type, amount)
      |> Repo.update()
    end
  end

  @doc """
  Resets weekly currency for all characters.
  """
  @spec reset_weekly_currency() :: {integer(), nil}
  def reset_weekly_currency do
    Repo.update_all(PvpStats, set: [conquest_this_week: 0, honor_this_week: 0])
  end

  # =============================================================================
  # PvP Ratings
  # =============================================================================

  @doc """
  Gets or creates a rating record for a character and bracket.
  """
  @spec get_or_create_rating(integer(), String.t()) :: {:ok, PvpRating.t()} | {:error, term()}
  def get_or_create_rating(character_id, bracket) do
    case get_rating(character_id, bracket) do
      nil ->
        %PvpRating{}
        |> PvpRating.changeset(%{character_id: character_id, bracket: bracket})
        |> Repo.insert()

      rating ->
        {:ok, rating}
    end
  end

  @doc """
  Gets a rating record for a character and bracket.
  """
  @spec get_rating(integer(), String.t()) :: PvpRating.t() | nil
  def get_rating(character_id, bracket) do
    Repo.get_by(PvpRating, character_id: character_id, bracket: bracket)
  end

  @doc """
  Gets all ratings for a character.
  """
  @spec get_all_ratings(integer()) :: [PvpRating.t()]
  def get_all_ratings(character_id) do
    PvpRating
    |> where([r], r.character_id == ^character_id)
    |> Repo.all()
  end

  @doc """
  Records a match result and updates rating.
  """
  @spec record_match(integer(), String.t(), boolean(), integer()) ::
          {:ok, PvpRating.t()} | {:error, term()}
  def record_match(character_id, bracket, won, opponent_rating) do
    with {:ok, rating} <- get_or_create_rating(character_id, bracket) do
      rating
      |> PvpRating.record_match(won, opponent_rating)
      |> Repo.update()
    end
  end

  @doc """
  Gets leaderboard for a bracket.
  """
  @spec get_leaderboard(String.t(), integer()) :: [PvpRating.t()]
  def get_leaderboard(bracket, limit \\ 100) do
    PvpRating
    |> where([r], r.bracket == ^bracket and r.games_played >= 10)
    |> order_by([r], desc: r.rating)
    |> limit(^limit)
    |> preload(:character)
    |> Repo.all()
  end

  @doc """
  Applies rating decay to inactive high-rated players.
  """
  @spec apply_rating_decay() :: {:ok, integer()}
  def apply_rating_decay do
    decay_threshold = 1800
    decay_period_days = 7
    cutoff_date = DateTime.add(DateTime.utc_now(), -decay_period_days * 24 * 60 * 60, :second)

    {count, _} =
      PvpRating
      |> where([r], r.rating >= ^decay_threshold)
      |> where([r], r.last_game_at < ^cutoff_date)
      |> where([r], is_nil(r.last_decay_at) or r.last_decay_at < ^cutoff_date)
      |> Repo.update_all(
        inc: [rating: -15],
        set: [last_decay_at: DateTime.utc_now()]
      )

    {:ok, count}
  end

  @doc """
  Gets all ratings above a threshold for a bracket (for decay processing).
  """
  @spec get_ratings_above(String.t(), integer()) :: [PvpRating.t()]
  def get_ratings_above(bracket, threshold) do
    PvpRating
    |> where([r], r.bracket == ^bracket and r.rating >= ^threshold)
    |> Repo.all()
  end

  @doc """
  Counts rated players in a bracket (minimum 10 games).
  """
  @spec count_rated_players(String.t()) :: integer()
  def count_rated_players(bracket) do
    PvpRating
    |> where([r], r.bracket == ^bracket and r.games_played >= 10)
    |> Repo.aggregate(:count)
  end

  @doc """
  Gets the rating at a specific position in the leaderboard.
  """
  @spec rating_at_position(String.t(), integer()) :: integer() | nil
  def rating_at_position(bracket, position) do
    PvpRating
    |> where([r], r.bracket == ^bracket and r.games_played >= 10)
    |> order_by([r], desc: r.rating)
    |> offset(^(position - 1))
    |> limit(1)
    |> select([r], r.rating)
    |> Repo.one()
  end

  @doc """
  Gets player rank in a bracket.
  """
  @spec get_player_rank(integer(), String.t()) :: integer() | nil
  def get_player_rank(character_id, bracket) do
    subquery =
      from(r in PvpRating,
        where: r.bracket == ^bracket and r.games_played >= 10,
        select: %{
          character_id: r.character_id,
          rank: row_number() |> over(order_by: [desc: r.rating])
        }
      )

    from(s in subquery(subquery), where: s.character_id == ^character_id, select: s.rank)
    |> Repo.one()
  end

  @doc """
  Gets players around a specific rank.
  """
  @spec get_players_around_rank(String.t(), integer(), integer()) :: [PvpRating.t()]
  def get_players_around_rank(bracket, target_rank, range \\ 5) do
    PvpRating
    |> where([r], r.bracket == ^bracket and r.games_played >= 10)
    |> order_by([r], desc: r.rating)
    |> offset(^max(0, target_rank - range - 1))
    |> limit(^(range * 2 + 1))
    |> preload(:character)
    |> Repo.all()
  end

  @doc """
  Updates a rating record by ID.
  """
  @spec update_rating(integer(), map()) :: {:ok, PvpRating.t()} | {:error, Ecto.Changeset.t()}
  def update_rating(rating_id, attrs) do
    case Repo.get(PvpRating, rating_id) do
      nil ->
        {:error, :not_found}

      rating ->
        rating
        |> PvpRating.changeset(attrs)
        |> Repo.update()
    end
  end

  @doc """
  Updates a season record.
  """
  @spec update_season(integer(), map()) :: {:ok, PvpSeason.t()} | {:error, Ecto.Changeset.t()}
  def update_season(season_id, attrs) do
    case Repo.get(PvpSeason, season_id) do
      nil ->
        {:error, :not_found}

      season ->
        season
        |> PvpSeason.changeset(attrs)
        |> Repo.update()
    end
  end

  # =============================================================================
  # PvP Seasons
  # =============================================================================

  @doc """
  Creates a new PvP season.
  """
  @spec create_season(map()) :: {:ok, PvpSeason.t()} | {:error, Ecto.Changeset.t()}
  def create_season(attrs) do
    %PvpSeason{}
    |> PvpSeason.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a season by number.
  """
  @spec get_season(integer()) :: PvpSeason.t() | nil
  def get_season(season_number) do
    Repo.get_by(PvpSeason, season_number: season_number)
  end

  @doc """
  Gets the current active season.
  """
  @spec get_active_season() :: PvpSeason.t() | nil
  def get_active_season do
    PvpSeason
    |> where([s], s.is_active == true)
    |> Repo.one()
  end

  @doc """
  Activates a season and deactivates any previous active season.
  """
  @spec activate_season(integer()) :: {:ok, PvpSeason.t()} | {:error, term()}
  def activate_season(season_number) do
    Repo.transaction(fn ->
      # Deactivate current season
      Repo.update_all(PvpSeason, set: [is_active: false])

      # Activate new season
      case get_season(season_number) do
        nil ->
          Repo.rollback(:not_found)

        season ->
          case Repo.update(PvpSeason.activate(season)) do
            {:ok, updated} -> updated
            {:error, changeset} -> Repo.rollback(changeset)
          end
      end
    end)
  end

  @doc """
  Ends a season and distributes rewards.
  """
  @spec end_season(integer()) :: {:ok, map()} | {:error, term()}
  def end_season(season_number) do
    case get_season(season_number) do
      nil ->
        {:error, :not_found}

      season ->
        # Deactivate season
        {:ok, _} = Repo.update(PvpSeason.deactivate(season))

        # Get eligible players and their rewards
        rewards = calculate_season_rewards(season)

        {:ok, %{season: season, rewards: rewards}}
    end
  end

  @doc """
  Resets ratings for a new season.
  """
  @spec reset_ratings_for_season() :: {integer(), nil}
  def reset_ratings_for_season do
    # Soft reset: new rating = old rating / 2
    from(r in PvpRating,
      update: [
        set: [
          rating: fragment("? / 2", r.rating),
          season_high: fragment("? / 2", r.rating),
          games_played: 0,
          games_won: 0,
          win_streak: 0,
          loss_streak: 0,
          last_game_at: nil,
          last_decay_at: nil
        ]
      ]
    )
    |> Repo.update_all([])
  end

  # Private helpers

  defp calculate_season_rewards(season) do
    # Get top players for each bracket
    for bracket <- PvpRating.brackets() do
      leaderboard = get_leaderboard(bracket, 1000)

      rewards =
        Enum.map(leaderboard, fn rating ->
          tier = PvpSeason.get_reward_tier(season, rating.season_high)
          title_id = PvpSeason.get_title_id(season, tier)

          mount_id =
            if tier == :gladiator do
              PvpSeason.get_mount_id(season)
            else
              nil
            end

          %{
            character_id: rating.character_id,
            bracket: bracket,
            rating: rating.season_high,
            tier: tier,
            title_id: title_id,
            mount_id: mount_id
          }
        end)

      {bracket, rewards}
    end
    |> Map.new()
  end
end
