defmodule BezgelorWorld.PvP.Rating do
  @moduledoc """
  ELO-based rating calculations for PvP.

  Provides functions for calculating rating changes after matches,
  expected win probabilities, and K-factor adjustments based on
  games played.
  """

  # Base K-factor (how much ratings change)
  @k_factor_new 40
  @k_factor_established 24
  @k_factor_veteran 16

  @starting_rating 1500
  @min_rating 0
  @max_rating 5000

  @doc """
  Calculate rating change after a match.
  Returns {winner_gain, loser_loss}.
  """
  @spec calculate_elo_change(integer(), integer(), keyword()) :: {integer(), integer()}
  def calculate_elo_change(winner_rating, loser_rating, opts \\ []) do
    winner_games = Keyword.get(opts, :winner_games, 50)
    loser_games = Keyword.get(opts, :loser_games, 50)

    winner_k = k_factor(winner_games)
    loser_k = k_factor(loser_games)

    # Expected score (probability of winning)
    winner_expected = expected_score(winner_rating, loser_rating)
    loser_expected = 1.0 - winner_expected

    # Actual score (1 for win, 0 for loss)
    winner_actual = 1.0
    loser_actual = 0.0

    # Rating change
    winner_change = round(winner_k * (winner_actual - winner_expected))
    loser_change = round(loser_k * (loser_actual - loser_expected))

    # Ensure minimum gain/loss
    winner_gain = max(1, winner_change)
    loser_loss = max(1, abs(loser_change))

    {winner_gain, loser_loss}
  end

  @doc """
  Calculate expected score (probability of winning).
  """
  @spec expected_score(integer(), integer()) :: float()
  def expected_score(player_rating, opponent_rating) do
    1.0 / (1.0 + :math.pow(10, (opponent_rating - player_rating) / 400))
  end

  @doc """
  Get K-factor based on games played.
  """
  @spec k_factor(integer()) :: integer()
  def k_factor(games_played) do
    cond do
      games_played < 20 -> @k_factor_new
      games_played < 50 -> @k_factor_established
      true -> @k_factor_veteran
    end
  end

  @doc """
  Calculate team rating from member ratings.
  """
  @spec team_rating([integer()]) :: integer()
  def team_rating(member_ratings) do
    case member_ratings do
      [] -> @starting_rating
      ratings -> round(Enum.sum(ratings) / length(ratings))
    end
  end

  @doc """
  Apply rating floor protection.
  """
  @spec apply_floor(integer(), integer()) :: integer()
  def apply_floor(rating, floor) do
    max(floor, rating)
  end

  @doc """
  Apply rating ceiling.
  """
  @spec apply_ceiling(integer()) :: integer()
  def apply_ceiling(rating) do
    min(@max_rating, rating)
  end

  @doc """
  Clamp rating within valid bounds.
  """
  @spec clamp(integer()) :: integer()
  def clamp(rating) do
    rating
    |> max(@min_rating)
    |> min(@max_rating)
  end

  @doc """
  Calculate matchmaking quality based on rating difference.
  Returns a value from 0.0 (poor) to 1.0 (excellent).
  """
  @spec matchmaking_quality(integer(), integer()) :: float()
  def matchmaking_quality(rating1, rating2) do
    diff = abs(rating1 - rating2)

    cond do
      diff <= 50 -> 1.0
      diff <= 100 -> 0.9
      diff <= 200 -> 0.7
      diff <= 300 -> 0.5
      diff <= 400 -> 0.3
      true -> 0.1
    end
  end

  @doc """
  Get starting rating.
  """
  @spec starting_rating() :: integer()
  def starting_rating, do: @starting_rating

  @doc """
  Get min rating.
  """
  @spec min_rating() :: integer()
  def min_rating, do: @min_rating

  @doc """
  Get max rating.
  """
  @spec max_rating() :: integer()
  def max_rating, do: @max_rating
end
