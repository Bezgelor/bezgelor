defmodule BezgelorDb.Guilds do
  @moduledoc """
  Guild management context.

  ## Features

  - Guild creation and disbanding
  - Member management (invite, kick, promote, demote)
  - Rank configuration with permissions
  - Guild bank with tab access control
  - Influence tracking

  ## Permission System

  Each rank has a permissions bitfield. Operations check the
  caller's rank permissions before proceeding.
  """

  import Ecto.Query
  alias BezgelorDb.Repo
  alias BezgelorDb.Schema.{Guild, GuildRank, GuildMember, GuildBankItem}

  # Guild Queries

  @doc "Get guild by ID."
  @spec get_guild(integer()) :: Guild.t() | nil
  def get_guild(guild_id) do
    Repo.get(Guild, guild_id)
  end

  @doc "Get guild by name."
  @spec get_guild_by_name(String.t()) :: Guild.t() | nil
  def get_guild_by_name(name) do
    Repo.get_by(Guild, name: name)
  end

  @doc "Get guild by tag."
  @spec get_guild_by_tag(String.t()) :: Guild.t() | nil
  def get_guild_by_tag(tag) do
    Repo.get_by(Guild, tag: String.upcase(tag))
  end

  @doc "Get character's guild membership."
  @spec get_membership(integer()) :: GuildMember.t() | nil
  def get_membership(character_id) do
    GuildMember
    |> where([m], m.character_id == ^character_id)
    |> Repo.one()
  end

  @doc "Get character's guild or nil."
  @spec get_character_guild(integer()) :: Guild.t() | nil
  def get_character_guild(character_id) do
    case get_membership(character_id) do
      nil -> nil
      member -> get_guild(member.guild_id)
    end
  end

  @doc "Get all members of a guild."
  @spec get_members(integer()) :: [GuildMember.t()]
  def get_members(guild_id) do
    GuildMember
    |> where([m], m.guild_id == ^guild_id)
    |> order_by([m], [m.rank_index, m.inserted_at])
    |> Repo.all()
  end

  @doc "Get member count."
  @spec member_count(integer()) :: integer()
  def member_count(guild_id) do
    GuildMember
    |> where([m], m.guild_id == ^guild_id)
    |> Repo.aggregate(:count)
  end

  @doc "Get all ranks for a guild."
  @spec get_ranks(integer()) :: [GuildRank.t()]
  def get_ranks(guild_id) do
    GuildRank
    |> where([r], r.guild_id == ^guild_id)
    |> order_by([r], r.rank_index)
    |> Repo.all()
  end

  @doc "Get rank by index."
  @spec get_rank(integer(), integer()) :: GuildRank.t() | nil
  def get_rank(guild_id, rank_index) do
    Repo.get_by(GuildRank, guild_id: guild_id, rank_index: rank_index)
  end

  # Guild Operations

  @doc "Create a new guild."
  @spec create_guild(integer(), String.t(), String.t()) ::
          {:ok, Guild.t()} | {:error, term()}
  def create_guild(leader_character_id, name, tag) do
    # Check if leader is already in a guild
    case get_membership(leader_character_id) do
      nil ->
        Repo.transaction(fn ->
          # Create guild
          case %Guild{}
               |> Guild.changeset(%{
                 name: name,
                 tag: String.upcase(tag),
                 leader_id: leader_character_id
               })
               |> Repo.insert() do
            {:ok, guild} ->
              # Create default ranks
              for rank_data <- GuildRank.default_ranks() do
                %GuildRank{}
                |> GuildRank.changeset(Map.put(rank_data, :guild_id, guild.id))
                |> Repo.insert!()
              end

              # Add leader as member with rank 0 (Guild Master)
              %GuildMember{}
              |> GuildMember.changeset(%{
                guild_id: guild.id,
                character_id: leader_character_id,
                rank_index: 0
              })
              |> Repo.insert!()

              guild

            {:error, changeset} ->
              Repo.rollback(changeset)
          end
        end)

      _membership ->
        {:error, :already_in_guild}
    end
  end

  @doc "Disband a guild (leader only)."
  @spec disband_guild(integer(), integer()) :: :ok | {:error, term()}
  def disband_guild(guild_id, requester_id) do
    with {:ok, _guild, _member, rank} <- get_member_with_rank(guild_id, requester_id),
         true <- GuildRank.can_disband?(rank) || {:error, :no_permission} do
      Repo.delete_all(from g in Guild, where: g.id == ^guild_id)
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # Member Operations

  @doc "Add a character to a guild."
  @spec add_member(integer(), integer(), integer(), integer()) ::
          {:ok, GuildMember.t()} | {:error, term()}
  def add_member(guild_id, character_id, inviter_id, rank_index \\ 4) do
    with {:ok, _guild, _member, rank} <- get_member_with_rank(guild_id, inviter_id),
         true <- GuildRank.can_invite?(rank) || {:error, :no_permission},
         nil <- get_membership(character_id) do
      %GuildMember{}
      |> GuildMember.changeset(%{
        guild_id: guild_id,
        character_id: character_id,
        rank_index: rank_index
      })
      |> Repo.insert()
    else
      %GuildMember{} -> {:error, :already_in_guild}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Remove a member from the guild."
  @spec remove_member(integer(), integer(), integer()) :: :ok | {:error, term()}
  def remove_member(guild_id, target_id, requester_id) do
    with {:ok, guild, requester_member, requester_rank} <- get_member_with_rank(guild_id, requester_id),
         {:ok, target_member} <- get_guild_member(guild_id, target_id) do
      cond do
        # Cannot kick yourself (use leave_guild)
        target_id == requester_id ->
          {:error, :cannot_kick_self}

        # Cannot kick the guild leader
        target_id == guild.leader_id ->
          {:error, :cannot_kick_leader}

        # Must have kick permission and outrank target
        not GuildRank.can_kick?(requester_rank) ->
          {:error, :no_permission}

        requester_member.rank_index >= target_member.rank_index ->
          {:error, :cannot_kick_higher_rank}

        true ->
          Repo.delete(target_member)
          :ok
      end
    end
  end

  @doc "Leave a guild voluntarily."
  @spec leave_guild(integer()) :: :ok | {:error, term()}
  def leave_guild(character_id) do
    case get_membership(character_id) do
      nil ->
        {:error, :not_in_guild}

      member ->
        guild = get_guild(member.guild_id)

        if guild.leader_id == character_id do
          {:error, :leader_cannot_leave}
        else
          Repo.delete(member)
          :ok
        end
    end
  end

  @doc "Promote a member (lower rank number)."
  @spec promote_member(integer(), integer(), integer()) :: {:ok, GuildMember.t()} | {:error, term()}
  def promote_member(guild_id, target_id, requester_id) do
    with {:ok, _guild, requester_member, requester_rank} <- get_member_with_rank(guild_id, requester_id),
         {:ok, target_member} <- get_guild_member(guild_id, target_id) do
      new_rank = target_member.rank_index - 1

      cond do
        not GuildRank.can_promote?(requester_rank) ->
          {:error, :no_permission}

        new_rank < 1 ->
          {:error, :cannot_promote_to_leader}

        new_rank <= requester_member.rank_index ->
          {:error, :cannot_promote_above_self}

        target_member.rank_index <= requester_member.rank_index ->
          {:error, :cannot_promote_higher_rank}

        true ->
          target_member
          |> GuildMember.rank_changeset(new_rank)
          |> Repo.update()
      end
    end
  end

  @doc "Demote a member (higher rank number)."
  @spec demote_member(integer(), integer(), integer()) :: {:ok, GuildMember.t()} | {:error, term()}
  def demote_member(guild_id, target_id, requester_id) do
    with {:ok, _guild, requester_member, requester_rank} <- get_member_with_rank(guild_id, requester_id),
         {:ok, target_member} <- get_guild_member(guild_id, target_id) do
      max_rank = 4  # Lowest rank
      new_rank = target_member.rank_index + 1

      cond do
        not GuildRank.can_demote?(requester_rank) ->
          {:error, :no_permission}

        new_rank > max_rank ->
          {:error, :already_lowest_rank}

        target_member.rank_index <= requester_member.rank_index ->
          {:error, :cannot_demote_higher_rank}

        true ->
          target_member
          |> GuildMember.rank_changeset(new_rank)
          |> Repo.update()
      end
    end
  end

  @doc "Transfer guild leadership."
  @spec transfer_leadership(integer(), integer(), integer()) :: {:ok, Guild.t()} | {:error, term()}
  def transfer_leadership(guild_id, new_leader_id, current_leader_id) do
    with {:ok, guild, current_member, _rank} <- get_member_with_rank(guild_id, current_leader_id),
         {:ok, new_leader_member} <- get_guild_member(guild_id, new_leader_id) do
      if guild.leader_id != current_leader_id do
        {:error, :not_leader}
      else
        Repo.transaction(fn ->
          # Update guild leader
          {:ok, guild} =
            guild
            |> Guild.leader_changeset(new_leader_id)
            |> Repo.update()

          # Swap ranks
          current_member
          |> GuildMember.rank_changeset(new_leader_member.rank_index)
          |> Repo.update!()

          new_leader_member
          |> GuildMember.rank_changeset(0)
          |> Repo.update!()

          guild
        end)
      end
    end
  end

  # Guild Settings

  @doc "Update MOTD."
  @spec update_motd(integer(), String.t(), integer()) :: {:ok, Guild.t()} | {:error, term()}
  def update_motd(guild_id, motd, requester_id) do
    with {:ok, guild, _member, rank} <- get_member_with_rank(guild_id, requester_id),
         true <- GuildRank.can_edit_motd?(rank) || {:error, :no_permission} do
      guild
      |> Guild.motd_changeset(motd)
      |> Repo.update()
    end
  end

  @doc "Update rank name."
  @spec update_rank_name(integer(), integer(), String.t(), integer()) ::
          {:ok, GuildRank.t()} | {:error, term()}
  def update_rank_name(guild_id, rank_index, name, requester_id) do
    with {:ok, _guild, _member, rank} <- get_member_with_rank(guild_id, requester_id),
         true <- GuildRank.can_edit_ranks?(rank) || {:error, :no_permission},
         %GuildRank{} = target_rank <- get_rank(guild_id, rank_index) || {:error, :rank_not_found} do
      target_rank
      |> GuildRank.name_changeset(name)
      |> Repo.update()
    end
  end

  @doc "Update rank permissions."
  @spec update_rank_permissions(integer(), integer(), integer(), integer()) ::
          {:ok, GuildRank.t()} | {:error, term()}
  def update_rank_permissions(guild_id, rank_index, permissions, requester_id) do
    with {:ok, _guild, _member, rank} <- get_member_with_rank(guild_id, requester_id),
         true <- GuildRank.can_edit_ranks?(rank) || {:error, :no_permission},
         true <- rank_index > 0 || {:error, :cannot_edit_leader_rank},
         %GuildRank{} = target_rank <- get_rank(guild_id, rank_index) || {:error, :rank_not_found} do
      target_rank
      |> GuildRank.permissions_changeset(permissions)
      |> Repo.update()
    end
  end

  # Guild Bank

  @doc "Get items in a bank tab."
  @spec get_bank_tab(integer(), integer()) :: [GuildBankItem.t()]
  def get_bank_tab(guild_id, tab_index) do
    GuildBankItem
    |> where([i], i.guild_id == ^guild_id and i.tab_index == ^tab_index)
    |> order_by([i], i.slot_index)
    |> Repo.all()
  end

  @doc "Deposit item to guild bank."
  @spec bank_deposit(integer(), integer(), integer(), integer(), integer(), map(), integer()) ::
          {:ok, GuildBankItem.t()} | {:error, term()}
  def bank_deposit(guild_id, tab_index, slot_index, item_id, stack_count, item_data, depositor_id) do
    with {:ok, guild, _member, rank} <- get_member_with_rank(guild_id, depositor_id),
         true <- GuildRank.can_bank_deposit?(rank) || {:error, :no_permission},
         true <- tab_index < guild.bank_tabs_unlocked || {:error, :tab_not_unlocked},
         nil <- get_bank_item(guild_id, tab_index, slot_index) do
      %GuildBankItem{}
      |> GuildBankItem.changeset(%{
        guild_id: guild_id,
        tab_index: tab_index,
        slot_index: slot_index,
        item_id: item_id,
        stack_count: stack_count,
        item_data: item_data,
        depositor_id: depositor_id
      })
      |> Repo.insert()
    else
      %GuildBankItem{} -> {:error, :slot_occupied}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Withdraw item from guild bank."
  @spec bank_withdraw(integer(), integer(), integer(), integer()) ::
          {:ok, GuildBankItem.t()} | {:error, term()}
  def bank_withdraw(guild_id, tab_index, slot_index, requester_id) do
    with {:ok, _guild, _member, rank} <- get_member_with_rank(guild_id, requester_id),
         true <- GuildRank.can_bank_withdraw?(rank) || {:error, :no_permission},
         %GuildBankItem{} = item <- get_bank_item(guild_id, tab_index, slot_index) || {:error, :slot_empty} do
      Repo.delete(item)
      {:ok, item}
    end
  end

  @doc "Move item within guild bank."
  @spec bank_move_item(integer(), integer(), integer(), integer(), integer(), integer()) ::
          {:ok, GuildBankItem.t()} | {:error, term()}
  def bank_move_item(guild_id, from_tab, from_slot, to_tab, to_slot, requester_id) do
    with {:ok, guild, _member, rank} <- get_member_with_rank(guild_id, requester_id),
         true <- GuildRank.can_bank_withdraw?(rank) || {:error, :no_permission},
         true <- to_tab < guild.bank_tabs_unlocked || {:error, :tab_not_unlocked},
         %GuildBankItem{} = item <- get_bank_item(guild_id, from_tab, from_slot) || {:error, :slot_empty},
         nil <- get_bank_item(guild_id, to_tab, to_slot) do
      item
      |> GuildBankItem.move_changeset(to_tab, to_slot)
      |> Repo.update()
    else
      %GuildBankItem{} -> {:error, :destination_occupied}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Unlock a new bank tab."
  @spec unlock_bank_tab(integer(), integer()) :: {:ok, Guild.t()} | {:error, term()}
  def unlock_bank_tab(guild_id, requester_id) do
    with {:ok, guild, _member, rank} <- get_member_with_rank(guild_id, requester_id),
         true <- GuildRank.can_edit_info?(rank) || {:error, :no_permission},
         true <- guild.bank_tabs_unlocked < 6 || {:error, :max_tabs_unlocked} do
      guild
      |> Guild.bank_tab_changeset(guild.bank_tabs_unlocked + 1)
      |> Repo.update()
    end
  end

  # Influence

  @doc "Add influence to the guild."
  @spec add_influence(integer(), integer(), integer()) :: {:ok, Guild.t()} | {:error, term()}
  def add_influence(guild_id, amount, contributor_id) do
    Repo.transaction(fn ->
      guild = Repo.get!(Guild, guild_id)

      {:ok, guild} =
        guild
        |> Guild.influence_changeset(guild.influence + amount)
        |> Repo.update()

      # Update member contribution
      member =
        GuildMember
        |> where([m], m.guild_id == ^guild_id and m.character_id == ^contributor_id)
        |> Repo.one!()

      member
      |> GuildMember.influence_changeset(amount)
      |> Repo.update!()

      guild
    end)
  end

  # Private Helpers

  defp get_member_with_rank(guild_id, character_id) do
    case {get_guild(guild_id), get_guild_member(guild_id, character_id)} do
      {nil, _} ->
        {:error, :guild_not_found}

      {_, {:error, :not_member}} ->
        {:error, :not_member}

      {guild, {:ok, member}} ->
        rank = get_rank(guild_id, member.rank_index)
        {:ok, guild, member, rank}
    end
  end

  defp get_guild_member(guild_id, character_id) do
    case Repo.get_by(GuildMember, guild_id: guild_id, character_id: character_id) do
      nil -> {:error, :not_member}
      member -> {:ok, member}
    end
  end

  defp get_bank_item(guild_id, tab_index, slot_index) do
    Repo.get_by(GuildBankItem, guild_id: guild_id, tab_index: tab_index, slot_index: slot_index)
  end
end
