defmodule BezgelorDb.Schema.Warplot do
  @moduledoc """
  Schema for warplot ownership and configuration.

  Warplots are customizable fortresses for 40v40 PvP battles.
  Guilds can own and upgrade warplots with various plugs and buildings.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BezgelorDb.Schema.{Guild, WarplotPlug}

  @type t :: %__MODULE__{
          id: integer() | nil,
          guild_id: integer(),
          name: String.t(),
          war_coins: integer(),
          rating: integer(),
          season_high: integer(),
          battles_played: integer(),
          battles_won: integer(),
          energy: integer(),
          max_energy: integer(),
          layout_id: integer(),
          created_at: DateTime.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @max_energy 1000
  @base_energy 500

  schema "warplots" do
    belongs_to :guild, Guild

    field :name, :string
    field :war_coins, :integer, default: 0
    field :rating, :integer, default: 0
    field :season_high, :integer, default: 0
    field :battles_played, :integer, default: 0
    field :battles_won, :integer, default: 0
    field :energy, :integer, default: @base_energy
    field :max_energy, :integer, default: @max_energy
    field :layout_id, :integer, default: 1
    field :created_at, :utc_datetime

    has_many :plugs, WarplotPlug

    timestamps()
  end

  @required_fields [:guild_id, :name, :created_at]
  @optional_fields [
    :war_coins, :rating, :season_high, :battles_played, :battles_won,
    :energy, :max_energy, :layout_id
  ]

  @doc """
  Creates a changeset for a warplot.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(warplot, attrs) do
    warplot
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:name, min: 2, max: 32)
    |> validate_number(:war_coins, greater_than_or_equal_to: 0)
    |> validate_number(:rating, greater_than_or_equal_to: 0)
    |> validate_number(:energy, greater_than_or_equal_to: 0)
    |> unique_constraint(:guild_id)
    |> foreign_key_constraint(:guild_id)
  end

  @doc """
  Records a battle result.
  """
  @spec record_battle(t(), boolean(), integer()) :: Ecto.Changeset.t()
  def record_battle(warplot, won, rating_change) do
    new_rating = max(0, warplot.rating + rating_change)
    new_season_high = max(warplot.season_high, new_rating)

    changes = %{
      rating: new_rating,
      season_high: new_season_high,
      battles_played: warplot.battles_played + 1
    }

    changes =
      if won do
        Map.put(changes, :battles_won, warplot.battles_won + 1)
      else
        changes
      end

    change(warplot, changes)
  end

  @doc """
  Adds war coins to the warplot.
  """
  @spec add_war_coins(t(), integer()) :: Ecto.Changeset.t()
  def add_war_coins(warplot, amount) when amount > 0 do
    change(warplot, war_coins: warplot.war_coins + amount)
  end

  @doc """
  Spends war coins from the warplot.
  """
  @spec spend_war_coins(t(), integer()) :: {:ok, Ecto.Changeset.t()} | {:error, :insufficient_funds}
  def spend_war_coins(warplot, amount) when amount > 0 do
    if warplot.war_coins >= amount do
      {:ok, change(warplot, war_coins: warplot.war_coins - amount)}
    else
      {:error, :insufficient_funds}
    end
  end

  @doc """
  Adjusts warplot energy.
  """
  @spec adjust_energy(t(), integer()) :: Ecto.Changeset.t()
  def adjust_energy(warplot, delta) do
    new_energy =
      (warplot.energy + delta)
      |> max(0)
      |> min(warplot.max_energy)

    change(warplot, energy: new_energy)
  end

  @doc """
  Resets warplot for a new season.
  """
  @spec reset_for_season(t()) :: Ecto.Changeset.t()
  def reset_for_season(warplot) do
    new_rating = div(warplot.rating, 2)

    change(warplot,
      rating: new_rating,
      season_high: new_rating,
      battles_played: 0,
      battles_won: 0
    )
  end

  @doc """
  Calculates win rate percentage.
  """
  @spec win_rate(t()) :: float()
  def win_rate(%__MODULE__{battles_played: 0}), do: 0.0
  def win_rate(%__MODULE__{battles_won: won, battles_played: played}) do
    Float.round(won / played * 100, 1)
  end

  @doc """
  Checks if warplot has enough energy for a battle.
  """
  @spec can_battle?(t()) :: boolean()
  def can_battle?(%__MODULE__{energy: energy}) do
    energy >= 100  # Minimum energy to queue
  end

  @doc """
  Returns max energy constant.
  """
  @spec max_energy() :: integer()
  def max_energy, do: @max_energy

  @doc """
  Returns base energy constant.
  """
  @spec base_energy() :: integer()
  def base_energy, do: @base_energy
end
