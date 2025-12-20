defmodule BezgelorDb.Schema.ArenaTeamMember do
  @moduledoc """
  Schema for arena team membership.

  Tracks individual member statistics within a team including:
  - Personal rating contribution
  - Games played with the team
  - Join date and role
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BezgelorDb.Schema.{ArenaTeam, Character}

  @type t :: %__MODULE__{
          id: integer() | nil,
          team_id: integer(),
          character_id: integer(),
          personal_rating: integer(),
          games_played: integer(),
          games_won: integer(),
          season_games: integer(),
          season_wins: integer(),
          joined_at: DateTime.t(),
          role: String.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @roles ~w(captain member)

  schema "arena_team_members" do
    belongs_to(:team, ArenaTeam)
    belongs_to(:character, Character)

    field(:personal_rating, :integer, default: 0)
    field(:games_played, :integer, default: 0)
    field(:games_won, :integer, default: 0)
    field(:season_games, :integer, default: 0)
    field(:season_wins, :integer, default: 0)
    field(:joined_at, :utc_datetime)
    field(:role, :string, default: "member")

    timestamps()
  end

  @required_fields [:team_id, :character_id, :joined_at]
  @optional_fields [
    :personal_rating,
    :games_played,
    :games_won,
    :season_games,
    :season_wins,
    :role
  ]

  @doc """
  Creates a changeset for team membership.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(member, attrs) do
    member
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:role, @roles)
    |> validate_number(:personal_rating, greater_than_or_equal_to: 0)
    |> unique_constraint([:team_id, :character_id])
    |> foreign_key_constraint(:team_id)
    |> foreign_key_constraint(:character_id)
  end

  @doc """
  Records a match result for the member.
  """
  @spec record_match(t(), boolean(), integer()) :: Ecto.Changeset.t()
  def record_match(member, won, rating_change) do
    new_rating = max(0, member.personal_rating + rating_change)

    changes = %{
      personal_rating: new_rating,
      games_played: member.games_played + 1,
      season_games: member.season_games + 1
    }

    changes =
      if won do
        changes
        |> Map.put(:games_won, member.games_won + 1)
        |> Map.put(:season_wins, member.season_wins + 1)
      else
        changes
      end

    change(member, changes)
  end

  @doc """
  Promotes member to captain.
  """
  @spec promote_to_captain(t()) :: Ecto.Changeset.t()
  def promote_to_captain(member) do
    change(member, role: "captain")
  end

  @doc """
  Demotes captain to member.
  """
  @spec demote_to_member(t()) :: Ecto.Changeset.t()
  def demote_to_member(member) do
    change(member, role: "member")
  end

  @doc """
  Resets season statistics.
  """
  @spec reset_season(t()) :: Ecto.Changeset.t()
  def reset_season(member) do
    new_rating = div(member.personal_rating, 2)

    change(member,
      personal_rating: new_rating,
      season_games: 0,
      season_wins: 0
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
  Checks if member is the captain.
  """
  @spec captain?(t()) :: boolean()
  def captain?(%__MODULE__{role: "captain"}), do: true
  def captain?(%__MODULE__{}), do: false

  @doc """
  Returns the list of valid roles.
  """
  @spec roles() :: [String.t()]
  def roles, do: @roles
end
