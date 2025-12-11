defmodule BezgelorDb.Schema.PvpStats do
  @moduledoc """
  Schema for character PvP statistics.

  Tracks lifetime PvP performance including:
  - Kill/death statistics
  - Battleground and arena participation
  - Highest ratings achieved
  - Currency earned totals
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BezgelorDb.Schema.Character

  @type t :: %__MODULE__{
          id: integer() | nil,
          character_id: integer(),
          honorable_kills: integer(),
          deaths: integer(),
          killing_blows: integer(),
          assists: integer(),
          damage_done: integer(),
          healing_done: integer(),
          battlegrounds_played: integer(),
          battlegrounds_won: integer(),
          arenas_played: integer(),
          arenas_won: integer(),
          duels_won: integer(),
          duels_lost: integer(),
          warplots_played: integer(),
          warplots_won: integer(),
          highest_arena_2v2: integer(),
          highest_arena_3v3: integer(),
          highest_arena_5v5: integer(),
          highest_rbg_rating: integer(),
          conquest_earned_total: integer(),
          honor_earned_total: integer(),
          conquest_this_week: integer(),
          honor_this_week: integer(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "pvp_stats" do
    belongs_to :character, Character

    # Kill statistics
    field :honorable_kills, :integer, default: 0
    field :deaths, :integer, default: 0
    field :killing_blows, :integer, default: 0
    field :assists, :integer, default: 0
    field :damage_done, :integer, default: 0
    field :healing_done, :integer, default: 0

    # Battleground stats
    field :battlegrounds_played, :integer, default: 0
    field :battlegrounds_won, :integer, default: 0

    # Arena stats
    field :arenas_played, :integer, default: 0
    field :arenas_won, :integer, default: 0

    # Duel stats
    field :duels_won, :integer, default: 0
    field :duels_lost, :integer, default: 0

    # Warplot stats
    field :warplots_played, :integer, default: 0
    field :warplots_won, :integer, default: 0

    # Highest ratings (lifetime)
    field :highest_arena_2v2, :integer, default: 0
    field :highest_arena_3v3, :integer, default: 0
    field :highest_arena_5v5, :integer, default: 0
    field :highest_rbg_rating, :integer, default: 0

    # Currency totals
    field :conquest_earned_total, :integer, default: 0
    field :honor_earned_total, :integer, default: 0
    field :conquest_this_week, :integer, default: 0
    field :honor_this_week, :integer, default: 0

    timestamps()
  end

  @required_fields [:character_id]
  @optional_fields [
    :honorable_kills, :deaths, :killing_blows, :assists,
    :damage_done, :healing_done,
    :battlegrounds_played, :battlegrounds_won,
    :arenas_played, :arenas_won,
    :duels_won, :duels_lost,
    :warplots_played, :warplots_won,
    :highest_arena_2v2, :highest_arena_3v3, :highest_arena_5v5,
    :highest_rbg_rating,
    :conquest_earned_total, :honor_earned_total,
    :conquest_this_week, :honor_this_week
  ]

  @doc """
  Creates a changeset for PvP stats.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(stats, attrs) do
    stats
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_number(:honorable_kills, greater_than_or_equal_to: 0)
    |> validate_number(:deaths, greater_than_or_equal_to: 0)
    |> validate_number(:killing_blows, greater_than_or_equal_to: 0)
    |> validate_number(:assists, greater_than_or_equal_to: 0)
    |> unique_constraint(:character_id)
    |> foreign_key_constraint(:character_id)
  end

  @doc """
  Increments kill statistics after a PvP kill.
  """
  @spec record_kill(t(), keyword()) :: Ecto.Changeset.t()
  def record_kill(stats, opts \\ []) do
    killing_blow = Keyword.get(opts, :killing_blow, false)

    changes = %{
      honorable_kills: stats.honorable_kills + 1
    }

    changes =
      if killing_blow do
        Map.put(changes, :killing_blows, stats.killing_blows + 1)
      else
        Map.put(changes, :assists, stats.assists + 1)
      end

    change(stats, changes)
  end

  @doc """
  Records a death.
  """
  @spec record_death(t()) :: Ecto.Changeset.t()
  def record_death(stats) do
    change(stats, deaths: stats.deaths + 1)
  end

  @doc """
  Records battleground participation.
  """
  @spec record_battleground(t(), boolean()) :: Ecto.Changeset.t()
  def record_battleground(stats, won) do
    changes = %{
      battlegrounds_played: stats.battlegrounds_played + 1
    }

    changes =
      if won do
        Map.put(changes, :battlegrounds_won, stats.battlegrounds_won + 1)
      else
        changes
      end

    change(stats, changes)
  end

  @doc """
  Records arena participation.
  """
  @spec record_arena(t(), boolean()) :: Ecto.Changeset.t()
  def record_arena(stats, won) do
    changes = %{
      arenas_played: stats.arenas_played + 1
    }

    changes =
      if won do
        Map.put(changes, :arenas_won, stats.arenas_won + 1)
      else
        changes
      end

    change(stats, changes)
  end

  @doc """
  Records a duel result.
  """
  @spec record_duel(t(), boolean()) :: Ecto.Changeset.t()
  def record_duel(stats, won) do
    if won do
      change(stats, duels_won: stats.duels_won + 1)
    else
      change(stats, duels_lost: stats.duels_lost + 1)
    end
  end

  @doc """
  Updates highest rating if new rating is higher.
  """
  @spec update_highest_rating(t(), String.t(), integer()) :: Ecto.Changeset.t()
  def update_highest_rating(stats, bracket, new_rating) do
    field = bracket_to_field(bracket)
    current = Map.get(stats, field, 0)

    if new_rating > current do
      change(stats, [{field, new_rating}])
    else
      change(stats, %{})
    end
  end

  @doc """
  Adds currency earned.
  """
  @spec add_currency(t(), :conquest | :honor, integer()) :: Ecto.Changeset.t()
  def add_currency(stats, :conquest, amount) do
    change(stats,
      conquest_earned_total: stats.conquest_earned_total + amount,
      conquest_this_week: stats.conquest_this_week + amount
    )
  end

  def add_currency(stats, :honor, amount) do
    change(stats,
      honor_earned_total: stats.honor_earned_total + amount,
      honor_this_week: stats.honor_this_week + amount
    )
  end

  @doc """
  Resets weekly currency counters.
  """
  @spec reset_weekly(t()) :: Ecto.Changeset.t()
  def reset_weekly(stats) do
    change(stats, conquest_this_week: 0, honor_this_week: 0)
  end

  @doc """
  Calculates kill/death ratio.
  """
  @spec kd_ratio(t()) :: float()
  def kd_ratio(%__MODULE__{honorable_kills: kills, deaths: 0}), do: kills * 1.0
  def kd_ratio(%__MODULE__{honorable_kills: kills, deaths: deaths}) do
    Float.round(kills / deaths, 2)
  end

  @doc """
  Calculates battleground win rate.
  """
  @spec bg_win_rate(t()) :: float()
  def bg_win_rate(%__MODULE__{battlegrounds_played: 0}), do: 0.0
  def bg_win_rate(%__MODULE__{battlegrounds_won: won, battlegrounds_played: played}) do
    Float.round(won / played * 100, 1)
  end

  @doc """
  Calculates arena win rate.
  """
  @spec arena_win_rate(t()) :: float()
  def arena_win_rate(%__MODULE__{arenas_played: 0}), do: 0.0
  def arena_win_rate(%__MODULE__{arenas_won: won, arenas_played: played}) do
    Float.round(won / played * 100, 1)
  end

  # Private helpers

  defp bracket_to_field("2v2"), do: :highest_arena_2v2
  defp bracket_to_field("3v3"), do: :highest_arena_3v3
  defp bracket_to_field("5v5"), do: :highest_arena_5v5
  defp bracket_to_field("rbg"), do: :highest_rbg_rating
  defp bracket_to_field(_), do: :highest_arena_2v2
end
