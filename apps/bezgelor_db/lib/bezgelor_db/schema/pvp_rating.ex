defmodule BezgelorDb.Schema.PvpRating do
  @moduledoc """
  Schema for character PvP ratings per bracket.

  Tracks rating information including:
  - Current rating
  - Season high rating
  - Games played/won
  - Win streak tracking
  - Rating decay timestamps
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BezgelorDb.Schema.Character

  @type t :: %__MODULE__{
          id: integer() | nil,
          character_id: integer(),
          bracket: String.t(),
          rating: integer(),
          season_high: integer(),
          games_played: integer(),
          games_won: integer(),
          win_streak: integer(),
          loss_streak: integer(),
          mmr: integer(),
          last_game_at: DateTime.t() | nil,
          last_decay_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @brackets ~w(2v2 3v3 5v5 rbg warplot)

  # ELO constants
  @base_rating 0
  @base_mmr 1500
  @k_factor_new 32      # Higher K for new players (< 10 games)
  @k_factor_normal 24   # Normal K factor
  @k_factor_high 16     # Lower K for high-rated players (> 2000)
  @decay_threshold 1800 # Rating above which decay applies
  @decay_amount 15      # Rating lost per week of inactivity
  @decay_period_days 7  # Days before decay kicks in

  schema "pvp_ratings" do
    belongs_to :character, Character

    field :bracket, :string
    field :rating, :integer, default: @base_rating
    field :season_high, :integer, default: @base_rating
    field :games_played, :integer, default: 0
    field :games_won, :integer, default: 0
    field :win_streak, :integer, default: 0
    field :loss_streak, :integer, default: 0
    field :mmr, :integer, default: @base_mmr
    field :last_game_at, :utc_datetime
    field :last_decay_at, :utc_datetime

    timestamps()
  end

  @required_fields [:character_id, :bracket]
  @optional_fields [
    :rating, :season_high, :games_played, :games_won,
    :win_streak, :loss_streak, :mmr, :last_game_at, :last_decay_at
  ]

  @doc """
  Creates a changeset for PvP rating.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(rating, attrs) do
    rating
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:bracket, @brackets)
    |> validate_number(:rating, greater_than_or_equal_to: 0)
    |> validate_number(:mmr, greater_than_or_equal_to: 0)
    |> unique_constraint([:character_id, :bracket])
    |> foreign_key_constraint(:character_id)
  end

  @doc """
  Records a match result and updates rating.
  """
  @spec record_match(t(), boolean(), integer()) :: Ecto.Changeset.t()
  def record_match(rating_record, won, opponent_rating) do
    {new_rating, new_mmr} = calculate_new_ratings(rating_record, won, opponent_rating)
    new_season_high = max(rating_record.season_high, new_rating)

    changes = %{
      rating: new_rating,
      mmr: new_mmr,
      season_high: new_season_high,
      games_played: rating_record.games_played + 1,
      last_game_at: DateTime.utc_now()
    }

    changes =
      if won do
        changes
        |> Map.put(:games_won, rating_record.games_won + 1)
        |> Map.put(:win_streak, rating_record.win_streak + 1)
        |> Map.put(:loss_streak, 0)
      else
        changes
        |> Map.put(:win_streak, 0)
        |> Map.put(:loss_streak, rating_record.loss_streak + 1)
      end

    change(rating_record, changes)
  end

  @doc """
  Applies rating decay for inactive high-rated players.
  """
  @spec apply_decay(t()) :: Ecto.Changeset.t()
  def apply_decay(rating_record) do
    if should_decay?(rating_record) do
      new_rating = max(0, rating_record.rating - @decay_amount)

      change(rating_record,
        rating: new_rating,
        last_decay_at: DateTime.utc_now()
      )
    else
      change(rating_record, %{})
    end
  end

  @doc """
  Checks if rating should decay.
  """
  @spec should_decay?(t()) :: boolean()
  def should_decay?(%__MODULE__{rating: rating}) when rating < @decay_threshold, do: false
  def should_decay?(%__MODULE__{last_game_at: nil}), do: false
  def should_decay?(%__MODULE__{last_game_at: last_game}) do
    days_inactive = DateTime.diff(DateTime.utc_now(), last_game, :day)
    days_inactive >= @decay_period_days
  end

  @doc """
  Resets rating for a new season.
  """
  @spec reset_for_season(t()) :: Ecto.Changeset.t()
  def reset_for_season(rating_record) do
    # Soft reset: new rating is 50% of old rating (floor of 0)
    new_rating = div(rating_record.rating, 2)
    new_mmr = div(rating_record.mmr + @base_mmr, 2)

    change(rating_record,
      rating: new_rating,
      season_high: new_rating,
      mmr: new_mmr,
      games_played: 0,
      games_won: 0,
      win_streak: 0,
      loss_streak: 0,
      last_game_at: nil,
      last_decay_at: nil
    )
  end

  @doc """
  Calculates win rate percentage.
  """
  @spec win_rate(t()) :: float()
  def win_rate(%__MODULE__{games_played: 0}), do: 0.0
  def win_rate(%__MODULE__{games_won: won, games_played: played}) do
    Float.round(won / played * 100, 1)
  end

  @doc """
  Returns the list of valid brackets.
  """
  @spec brackets() :: [String.t()]
  def brackets, do: @brackets

  @doc """
  Returns base rating for new characters.
  """
  @spec base_rating() :: integer()
  def base_rating, do: @base_rating

  @doc """
  Returns base MMR for new characters.
  """
  @spec base_mmr() :: integer()
  def base_mmr, do: @base_mmr

  # Private helpers

  defp calculate_new_ratings(rating_record, won, opponent_rating) do
    k = get_k_factor(rating_record)
    expected = expected_score(rating_record.mmr, opponent_rating)
    actual = if won, do: 1.0, else: 0.0

    # MMR always changes
    mmr_change = round(k * (actual - expected))
    new_mmr = max(0, rating_record.mmr + mmr_change)

    # Rating only goes up from wins, down from losses (can't go negative)
    rating_change =
      cond do
        won -> max(1, abs(mmr_change))  # Minimum +1 for a win
        true -> min(-1, -abs(mmr_change))  # Minimum -1 for a loss
      end

    new_rating = max(0, rating_record.rating + rating_change)

    {new_rating, new_mmr}
  end

  defp get_k_factor(%__MODULE__{games_played: games, rating: rating}) do
    cond do
      games < 10 -> @k_factor_new
      rating > 2000 -> @k_factor_high
      true -> @k_factor_normal
    end
  end

  defp expected_score(player_mmr, opponent_mmr) do
    1.0 / (1.0 + :math.pow(10, (opponent_mmr - player_mmr) / 400))
  end
end
