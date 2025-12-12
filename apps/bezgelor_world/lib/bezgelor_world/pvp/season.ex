defmodule BezgelorWorld.PvP.Season do
  @moduledoc """
  PvP season management and rewards.

  Handles season lifecycle including:
  - Starting new seasons
  - Calculating tier cutoffs based on population
  - Distributing end-of-season rewards
  - Rating resets between seasons
  """

  require Logger

  alias BezgelorDb.PvP

  @season_duration_weeks 12

  @rating_tiers %{
    gladiator: %{min_rating: 2400, percentile: 0.5, title: "Gladiator", mount: true},
    duelist: %{min_rating: 2100, percentile: 3.0, title: "Duelist", mount: false},
    rival: %{min_rating: 1800, percentile: 10.0, title: "Rival", mount: false},
    challenger: %{min_rating: 1600, percentile: 35.0, title: "Challenger", mount: false},
    combatant: %{min_rating: 1400, percentile: nil, title: "Combatant", mount: false}
  }

  @doc """
  Get rating tier configuration.
  """
  @spec rating_tiers() :: map()
  def rating_tiers, do: @rating_tiers

  @doc """
  Get season duration in weeks.
  """
  @spec season_duration_weeks() :: integer()
  def season_duration_weeks, do: @season_duration_weeks

  @doc """
  Start a new PvP season.
  """
  @spec start_season(integer()) :: {:ok, map()} | {:error, term()}
  def start_season(season_number) do
    end_date = DateTime.add(DateTime.utc_now(), @season_duration_weeks * 7, :day)

    PvP.create_season(%{
      season_number: season_number,
      start_date: DateTime.utc_now(),
      end_date: end_date,
      is_active: true
    })
  end

  @doc """
  End current season and distribute rewards.
  """
  @spec end_season(integer()) :: {:ok, map()} | {:error, term()}
  def end_season(season_id) do
    Logger.info("Ending PvP season #{season_id}")

    # Get final standings
    standings = calculate_final_standings()

    # Distribute rewards
    distributed =
      Enum.map(standings, fn {character_id, tier, rating} ->
        case distribute_reward(character_id, tier, rating, season_id) do
          :ok -> {character_id, tier}
          {:error, _} -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    Logger.info("Distributed #{length(distributed)} rewards for season #{season_id}")

    # Reset ratings for new season
    reset_ratings_for_new_season()

    {:ok, %{season_id: season_id, rewards_distributed: length(distributed)}}
  end

  @doc """
  Calculate tier cutoffs based on actual population.
  """
  @spec calculate_tier_cutoffs(String.t()) :: map()
  def calculate_tier_cutoffs(bracket) do
    total_players = PvP.count_rated_players(bracket)

    @rating_tiers
    |> Enum.map(fn {tier, config} ->
      cutoff =
        case config.percentile do
          nil ->
            # Fixed rating requirement only
            config.min_rating

          percentile when total_players > 0 ->
            # Calculate based on percentile
            position = max(1, round(total_players * (percentile / 100)))
            rating_at_pos = PvP.rating_at_position(bracket, position)
            max(config.min_rating, rating_at_pos || config.min_rating)

          _ ->
            config.min_rating
        end

      {tier, cutoff}
    end)
    |> Map.new()
  end

  @doc """
  Get the tier for a given rating.
  """
  @spec get_tier(integer(), map()) :: atom() | nil
  def get_tier(rating, cutoffs) do
    cond do
      rating >= Map.get(cutoffs, :gladiator, 2400) -> :gladiator
      rating >= Map.get(cutoffs, :duelist, 2100) -> :duelist
      rating >= Map.get(cutoffs, :rival, 1800) -> :rival
      rating >= Map.get(cutoffs, :challenger, 1600) -> :challenger
      rating >= Map.get(cutoffs, :combatant, 1400) -> :combatant
      true -> nil
    end
  end

  @doc """
  Get reward configuration for a tier.
  """
  @spec get_tier_reward(atom()) :: map() | nil
  def get_tier_reward(tier) do
    Map.get(@rating_tiers, tier)
  end

  @doc """
  Get conquest currency reward amount for a tier.
  """
  @spec tier_conquest_reward(atom()) :: integer()
  def tier_conquest_reward(:gladiator), do: 5000
  def tier_conquest_reward(:duelist), do: 3000
  def tier_conquest_reward(:rival), do: 2000
  def tier_conquest_reward(:challenger), do: 1000
  def tier_conquest_reward(:combatant), do: 500
  def tier_conquest_reward(_), do: 0

  # Private functions

  defp calculate_final_standings do
    # Calculate for all brackets
    for bracket <- ["2v2", "3v3", "5v5", "warplot"],
        rating <- PvP.get_leaderboard(bracket, 1000) do
      cutoffs = calculate_tier_cutoffs(bracket)
      tier = get_tier(rating.season_high || rating.rating, cutoffs)
      {rating.character_id, tier, rating.season_high || rating.rating}
    end
    |> Enum.uniq_by(fn {char_id, _, _} -> char_id end)
    |> Enum.reject(fn {_, tier, _} -> is_nil(tier) end)
  end

  defp distribute_reward(character_id, tier, _rating, season_id) do
    reward = Map.get(@rating_tiers, tier)

    if reward do
      Logger.debug(
        "Distributing #{tier} reward to character #{character_id} for season #{season_id}"
      )

      # Grant title (using placeholder - actual implementation would use Characters context)
      # BezgelorDb.Characters.grant_title(character_id, reward.title, season_id)

      # Grant mount if applicable
      # if reward.mount do
      #   BezgelorDb.Characters.grant_mount(character_id, "gladiator_mount_#{season_id}")
      # end

      # Grant conquest currency reward
      conquest_amount = tier_conquest_reward(tier)
      PvP.add_currency(character_id, :conquest, conquest_amount)

      :ok
    else
      {:error, :no_reward}
    end
  end

  defp reset_ratings_for_new_season do
    # Use existing BezgelorDb.PvP.reset_ratings_for_season/0
    # which performs: new_rating = old_rating / 2
    PvP.reset_ratings_for_season()

    # Also reset arena teams
    if Code.ensure_loaded?(BezgelorDb.ArenaTeams) do
      BezgelorDb.ArenaTeams.reset_for_season()
    end
  end
end
