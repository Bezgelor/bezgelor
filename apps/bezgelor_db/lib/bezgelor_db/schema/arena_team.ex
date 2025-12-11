defmodule BezgelorDb.Schema.ArenaTeam do
  @moduledoc """
  Schema for arena teams.

  Arena teams are persistent groups for rated arena play.
  Each team has a bracket (2v2, 3v3, 5v5), rating, and roster.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BezgelorDb.Schema.ArenaTeamMember

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t(),
          bracket: String.t(),
          rating: integer(),
          season_high: integer(),
          games_played: integer(),
          games_won: integer(),
          captain_id: integer(),
          faction_id: integer(),
          created_at: DateTime.t(),
          disbanded_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @brackets ~w(2v2 3v3 5v5)
  @max_roster_size %{"2v2" => 4, "3v3" => 6, "5v5" => 10}

  schema "arena_teams" do
    field :name, :string
    field :bracket, :string
    field :rating, :integer, default: 0
    field :season_high, :integer, default: 0
    field :games_played, :integer, default: 0
    field :games_won, :integer, default: 0
    field :captain_id, :integer
    field :faction_id, :integer
    field :created_at, :utc_datetime
    field :disbanded_at, :utc_datetime

    has_many :members, ArenaTeamMember, foreign_key: :team_id

    timestamps()
  end

  @required_fields [:name, :bracket, :captain_id, :faction_id, :created_at]
  @optional_fields [:rating, :season_high, :games_played, :games_won, :disbanded_at]

  @doc """
  Creates a changeset for an arena team.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(team, attrs) do
    team
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:bracket, @brackets)
    |> validate_length(:name, min: 2, max: 24)
    |> validate_format(:name, ~r/^[a-zA-Z0-9\s]+$/, message: "only letters, numbers and spaces allowed")
    |> validate_number(:rating, greater_than_or_equal_to: 0)
    |> unique_constraint(:name)
  end

  @doc """
  Records a match result for the team.
  """
  @spec record_match(t(), boolean(), integer()) :: Ecto.Changeset.t()
  def record_match(team, won, rating_change) do
    new_rating = max(0, team.rating + rating_change)
    new_season_high = max(team.season_high, new_rating)

    changes = %{
      rating: new_rating,
      season_high: new_season_high,
      games_played: team.games_played + 1
    }

    changes =
      if won do
        Map.put(changes, :games_won, team.games_won + 1)
      else
        changes
      end

    change(team, changes)
  end

  @doc """
  Disbands the team.
  """
  @spec disband(t()) :: Ecto.Changeset.t()
  def disband(team) do
    change(team, disbanded_at: DateTime.utc_now())
  end

  @doc """
  Changes the team captain.
  """
  @spec change_captain(t(), integer()) :: Ecto.Changeset.t()
  def change_captain(team, new_captain_id) do
    change(team, captain_id: new_captain_id)
  end

  @doc """
  Resets team rating for a new season.
  """
  @spec reset_for_season(t()) :: Ecto.Changeset.t()
  def reset_for_season(team) do
    new_rating = div(team.rating, 2)

    change(team,
      rating: new_rating,
      season_high: new_rating,
      games_played: 0,
      games_won: 0
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
  Checks if team is disbanded.
  """
  @spec disbanded?(t()) :: boolean()
  def disbanded?(%__MODULE__{disbanded_at: nil}), do: false
  def disbanded?(%__MODULE__{}), do: true

  @doc """
  Returns max roster size for the bracket.
  """
  @spec max_roster_size(String.t()) :: integer()
  def max_roster_size(bracket) do
    Map.get(@max_roster_size, bracket, 4)
  end

  @doc """
  Returns team size for matches in the bracket.
  """
  @spec team_size(String.t()) :: integer()
  def team_size("2v2"), do: 2
  def team_size("3v3"), do: 3
  def team_size("5v5"), do: 5
  def team_size(_), do: 2

  @doc """
  Returns the list of valid brackets.
  """
  @spec brackets() :: [String.t()]
  def brackets, do: @brackets
end
