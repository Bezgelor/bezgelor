defmodule BezgelorWorld.PvP.RatingDecay do
  @moduledoc """
  Weekly rating decay for inactive high-rated players.

  Applies decay to players above the threshold who haven't played
  in the specified inactivity period. Decay will not push a player's
  rating below the decay floor.
  """

  require Logger

  alias BezgelorDb.PvP

  @decay_threshold 2000
  @decay_amount 50
  @decay_floor 2000
  @inactivity_weeks 1
  @decay_brackets ["2v2", "3v3", "5v5", "warplot"]

  @doc """
  Get the rating threshold above which decay applies.
  """
  @spec decay_threshold() :: integer()
  def decay_threshold, do: @decay_threshold

  @doc """
  Get the amount of rating lost per decay cycle.
  """
  @spec decay_amount() :: integer()
  def decay_amount, do: @decay_amount

  @doc """
  Get the minimum rating after decay is applied.
  """
  @spec decay_floor() :: integer()
  def decay_floor, do: @decay_floor

  @doc """
  Get the brackets that have rating decay.
  """
  @spec decay_brackets() :: [String.t()]
  def decay_brackets, do: @decay_brackets

  @doc """
  Process weekly decay for all players.
  Called by SeasonScheduler on a weekly basis.
  """
  @spec process_weekly_decay() :: {:ok, integer()}
  def process_weekly_decay do
    cutoff_date = DateTime.add(DateTime.utc_now(), -7 * @inactivity_weeks, :day)

    total_decayed =
      Enum.reduce(@decay_brackets, 0, fn bracket, count ->
        decayed = process_bracket_decay(bracket, cutoff_date)
        count + decayed
      end)

    Logger.info("Rating decay applied to #{total_decayed} players across all brackets")

    {:ok, total_decayed}
  end

  @doc """
  Calculate decay preview for a player.
  Shows what decay would be applied if the player doesn't play.
  """
  @spec decay_preview(integer(), DateTime.t()) :: {:will_decay, integer()} | {:no_decay, 0}
  def decay_preview(rating, last_game_at) do
    weeks_inactive = div(DateTime.diff(DateTime.utc_now(), last_game_at), 7 * 24 * 3600)

    if rating >= @decay_threshold and weeks_inactive >= @inactivity_weeks do
      decay_weeks = weeks_inactive - @inactivity_weeks + 1
      total_decay = decay_weeks * @decay_amount
      new_rating = max(@decay_floor, rating - total_decay)
      {:will_decay, rating - new_rating}
    else
      {:no_decay, 0}
    end
  end

  @doc """
  Calculate how many weeks until decay starts for a player.
  """
  @spec weeks_until_decay(integer(), DateTime.t() | nil) :: integer() | :never
  def weeks_until_decay(rating, last_game_at) when rating < @decay_threshold do
    :never
  end

  def weeks_until_decay(_rating, nil) do
    @inactivity_weeks
  end

  def weeks_until_decay(_rating, last_game_at) do
    days_since = DateTime.diff(DateTime.utc_now(), last_game_at, :day)
    weeks_since = div(days_since, 7)
    max(0, @inactivity_weeks - weeks_since)
  end

  @doc """
  Check if a player would be subject to decay.
  """
  @spec would_decay?(integer(), DateTime.t() | nil) :: boolean()
  def would_decay?(rating, _last_game_at) when rating < @decay_threshold, do: false
  def would_decay?(_rating, nil), do: true

  def would_decay?(rating, last_game_at) do
    rating >= @decay_threshold and
      DateTime.diff(DateTime.utc_now(), last_game_at, :day) >= @inactivity_weeks * 7
  end

  # Private functions

  defp process_bracket_decay(bracket, cutoff_date) do
    ratings = PvP.get_ratings_above(bracket, @decay_threshold)

    ratings
    |> Enum.filter(fn rating ->
      is_inactive?(rating, cutoff_date)
    end)
    |> Enum.reduce(0, fn rating, count ->
      new_rating = max(@decay_floor, rating.rating - @decay_amount)

      if new_rating < rating.rating do
        case PvP.update_rating(rating.id, %{
               rating: new_rating,
               last_decay_at: DateTime.utc_now()
             }) do
          {:ok, _} ->
            Logger.debug(
              "Applied decay to character #{rating.character_id} in #{bracket}: #{rating.rating} -> #{new_rating}"
            )

            count + 1

          {:error, _} ->
            count
        end
      else
        count
      end
    end)
  end

  defp is_inactive?(rating, cutoff_date) do
    case rating.last_game_at do
      nil -> true
      last_game -> DateTime.compare(last_game, cutoff_date) == :lt
    end
  end
end
