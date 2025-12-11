defmodule BezgelorDb.ArenaTeams do
  @moduledoc """
  Context module for arena team management.

  Provides functions for:
  - Creating and disbanding teams
  - Managing team membership
  - Recording match results
  - Team leaderboards
  """

  import Ecto.Query

  alias BezgelorDb.Repo
  alias BezgelorDb.Schema.{ArenaTeam, ArenaTeamMember}

  # =============================================================================
  # Team Management
  # =============================================================================

  @doc """
  Creates a new arena team.
  """
  @spec create_team(map()) :: {:ok, ArenaTeam.t()} | {:error, Ecto.Changeset.t()}
  def create_team(attrs) do
    attrs = Map.put(attrs, :created_at, DateTime.utc_now())

    %ArenaTeam{}
    |> ArenaTeam.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a team by ID.
  """
  @spec get_team(integer()) :: ArenaTeam.t() | nil
  def get_team(team_id) do
    Repo.get(ArenaTeam, team_id)
  end

  @doc """
  Gets a team by name.
  """
  @spec get_team_by_name(String.t()) :: ArenaTeam.t() | nil
  def get_team_by_name(name) do
    Repo.get_by(ArenaTeam, name: name)
  end

  @doc """
  Gets a team with its members preloaded.
  """
  @spec get_team_with_members(integer()) :: ArenaTeam.t() | nil
  def get_team_with_members(team_id) do
    ArenaTeam
    |> where([t], t.id == ^team_id)
    |> preload(members: :character)
    |> Repo.one()
  end

  @doc """
  Gets all teams for a character.
  """
  @spec get_character_teams(integer()) :: [ArenaTeam.t()]
  def get_character_teams(character_id) do
    ArenaTeam
    |> join(:inner, [t], m in ArenaTeamMember, on: m.team_id == t.id)
    |> where([t, m], m.character_id == ^character_id)
    |> where([t, m], is_nil(t.disbanded_at))
    |> Repo.all()
  end

  @doc """
  Disbands a team.
  """
  @spec disband_team(integer(), integer()) :: {:ok, ArenaTeam.t()} | {:error, term()}
  def disband_team(team_id, captain_id) do
    case get_team(team_id) do
      nil ->
        {:error, :not_found}

      %ArenaTeam{captain_id: ^captain_id} = team ->
        team
        |> ArenaTeam.disband()
        |> Repo.update()

      _team ->
        {:error, :not_captain}
    end
  end

  @doc """
  Records a match result for the team.
  """
  @spec record_match(integer(), boolean(), integer(), [integer()]) :: {:ok, ArenaTeam.t()} | {:error, term()}
  def record_match(team_id, won, rating_change, participant_ids) do
    Repo.transaction(fn ->
      team = get_team(team_id)

      if is_nil(team) do
        Repo.rollback(:not_found)
      end

      # Update team rating
      {:ok, updated_team} =
        team
        |> ArenaTeam.record_match(won, rating_change)
        |> Repo.update()

      # Update member stats for participants
      ArenaTeamMember
      |> where([m], m.team_id == ^team_id and m.character_id in ^participant_ids)
      |> Repo.all()
      |> Enum.each(fn member ->
        member
        |> ArenaTeamMember.record_match(won, rating_change)
        |> Repo.update!()
      end)

      updated_team
    end)
  end

  # =============================================================================
  # Membership Management
  # =============================================================================

  @doc """
  Adds a member to a team.
  """
  @spec add_member(integer(), integer()) :: {:ok, ArenaTeamMember.t()} | {:error, term()}
  def add_member(team_id, character_id) do
    team = get_team_with_members(team_id)

    cond do
      is_nil(team) ->
        {:error, :team_not_found}

      ArenaTeam.disbanded?(team) ->
        {:error, :team_disbanded}

      length(team.members) >= ArenaTeam.max_roster_size(team.bracket) ->
        {:error, :roster_full}

      member_of_team?(team_id, character_id) ->
        {:error, :already_member}

      true ->
        %ArenaTeamMember{}
        |> ArenaTeamMember.changeset(%{
          team_id: team_id,
          character_id: character_id,
          joined_at: DateTime.utc_now()
        })
        |> Repo.insert()
    end
  end

  @doc """
  Removes a member from a team.
  """
  @spec remove_member(integer(), integer()) :: {:ok, ArenaTeamMember.t()} | {:error, term()}
  def remove_member(team_id, character_id) do
    case get_member(team_id, character_id) do
      nil ->
        {:error, :not_member}

      %ArenaTeamMember{role: "captain"} ->
        {:error, :cannot_remove_captain}

      member ->
        Repo.delete(member)
    end
  end

  @doc """
  Leaves a team (member removes themselves).
  """
  @spec leave_team(integer(), integer()) :: {:ok, ArenaTeamMember.t()} | {:error, term()}
  def leave_team(team_id, character_id) do
    case get_member(team_id, character_id) do
      nil ->
        {:error, :not_member}

      %ArenaTeamMember{role: "captain"} = member ->
        team = get_team_with_members(team_id)

        # If captain is leaving, either transfer or disband
        other_members = Enum.reject(team.members, &(&1.character_id == character_id))

        if Enum.empty?(other_members) do
          # Last member, disband team
          {:ok, _} = Repo.update(ArenaTeam.disband(team))
          Repo.delete(member)
        else
          {:error, :captain_must_transfer}
        end

      member ->
        Repo.delete(member)
    end
  end

  @doc """
  Gets a team member.
  """
  @spec get_member(integer(), integer()) :: ArenaTeamMember.t() | nil
  def get_member(team_id, character_id) do
    Repo.get_by(ArenaTeamMember, team_id: team_id, character_id: character_id)
  end

  @doc """
  Checks if character is a member of a team.
  """
  @spec member_of_team?(integer(), integer()) :: boolean()
  def member_of_team?(team_id, character_id) do
    ArenaTeamMember
    |> where([m], m.team_id == ^team_id and m.character_id == ^character_id)
    |> Repo.exists?()
  end

  @doc """
  Promotes a member to captain.
  """
  @spec promote_to_captain(integer(), integer(), integer()) :: {:ok, ArenaTeam.t()} | {:error, term()}
  def promote_to_captain(team_id, current_captain_id, new_captain_id) do
    Repo.transaction(fn ->
      team = get_team(team_id)

      cond do
        is_nil(team) ->
          Repo.rollback(:not_found)

        team.captain_id != current_captain_id ->
          Repo.rollback(:not_captain)

        not member_of_team?(team_id, new_captain_id) ->
          Repo.rollback(:not_member)

        true ->
          # Demote current captain
          current_member = get_member(team_id, current_captain_id)
          {:ok, _} = Repo.update(ArenaTeamMember.demote_to_member(current_member))

          # Promote new captain
          new_member = get_member(team_id, new_captain_id)
          {:ok, _} = Repo.update(ArenaTeamMember.promote_to_captain(new_member))

          # Update team captain
          {:ok, team} = Repo.update(ArenaTeam.change_captain(team, new_captain_id))
          team
      end
    end)
  end

  # =============================================================================
  # Leaderboards
  # =============================================================================

  @doc """
  Gets team leaderboard for a bracket.
  """
  @spec get_team_leaderboard(String.t(), integer()) :: [ArenaTeam.t()]
  def get_team_leaderboard(bracket, limit \\ 100) do
    ArenaTeam
    |> where([t], t.bracket == ^bracket and is_nil(t.disbanded_at))
    |> where([t], t.games_played >= 10)
    |> order_by([t], desc: t.rating)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Gets teams by faction.
  """
  @spec get_teams_by_faction(integer(), String.t()) :: [ArenaTeam.t()]
  def get_teams_by_faction(faction_id, bracket) do
    ArenaTeam
    |> where([t], t.faction_id == ^faction_id and t.bracket == ^bracket)
    |> where([t], is_nil(t.disbanded_at))
    |> order_by([t], desc: t.rating)
    |> Repo.all()
  end

  # =============================================================================
  # Season Management
  # =============================================================================

  @doc """
  Resets team ratings for a new season.
  """
  @spec reset_for_season() :: {integer(), nil}
  def reset_for_season do
    # Reset teams
    {team_count, _} =
      from(t in ArenaTeam,
        where: is_nil(t.disbanded_at),
        update: [
          set: [
            rating: fragment("? / 2", t.rating),
            season_high: fragment("? / 2", t.rating),
            games_played: 0,
            games_won: 0
          ]
        ]
      )
      |> Repo.update_all([])

    # Reset members
    from(m in ArenaTeamMember,
      update: [
        set: [
          personal_rating: fragment("? / 2", m.personal_rating),
          season_games: 0,
          season_wins: 0
        ]
      ]
    )
    |> Repo.update_all([])

    {team_count, nil}
  end

  @doc """
  Checks if a character can create a team (not already on a team of that bracket).
  """
  @spec can_create_team?(integer(), String.t()) :: boolean()
  def can_create_team?(character_id, bracket) do
    ArenaTeam
    |> join(:inner, [t], m in ArenaTeamMember, on: m.team_id == t.id)
    |> where([t, m], m.character_id == ^character_id)
    |> where([t, m], t.bracket == ^bracket and is_nil(t.disbanded_at))
    |> Repo.exists?()
    |> Kernel.not()
  end
end
