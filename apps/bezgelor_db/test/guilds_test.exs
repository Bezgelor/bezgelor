defmodule BezgelorDb.GuildsTest do
  use ExUnit.Case

  alias BezgelorDb.{Accounts, Characters, Guilds, Repo}
  alias BezgelorDb.Schema.GuildRank

  @moduletag :database

  setup do
    case Repo.start_link([]) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    # Create test accounts and characters
    email1 = "guild_test#{System.unique_integer([:positive])}@test.com"
    {:ok, account1} = Accounts.create_account(email1, "password123")

    {:ok, leader} =
      Characters.create_character(account1.id, %{
        name: "GuildLeader#{System.unique_integer([:positive])}",
        sex: 0,
        race: 0,
        class: 0,
        faction_id: 166,
        world_id: 1,
        world_zone_id: 1
      })

    email2 = "guild_test#{System.unique_integer([:positive])}@test.com"
    {:ok, account2} = Accounts.create_account(email2, "password123")

    {:ok, member} =
      Characters.create_character(account2.id, %{
        name: "GuildMember#{System.unique_integer([:positive])}",
        sex: 0,
        race: 0,
        class: 0,
        faction_id: 166,
        world_id: 1,
        world_zone_id: 1
      })

    {:ok, leader: leader, member: member}
  end

  describe "guild creation" do
    test "create_guild creates guild with ranks", %{leader: leader} do
      {:ok, guild} = Guilds.create_guild(leader.id, "Test Guild", "TEST")

      assert guild.name == "Test Guild"
      assert guild.tag == "TEST"
      assert guild.leader_id == leader.id

      ranks = Guilds.get_ranks(guild.id)
      assert length(ranks) == 5
    end

    test "create_guild adds leader as rank 0", %{leader: leader} do
      {:ok, guild} = Guilds.create_guild(leader.id, "Test Guild", "TEST")

      member = Guilds.get_membership(leader.id)
      assert member.rank_index == 0
      assert member.guild_id == guild.id
    end

    test "create_guild fails if already in guild", %{leader: leader} do
      {:ok, _} = Guilds.create_guild(leader.id, "First Guild", "FRST")
      {:error, :already_in_guild} = Guilds.create_guild(leader.id, "Second Guild", "SCND")
    end

    test "create_guild requires unique name", %{leader: leader, member: member} do
      {:ok, _} = Guilds.create_guild(leader.id, "Unique Name", "UNIQ")
      {:error, _} = Guilds.create_guild(member.id, "Unique Name", "DIFF")
    end
  end

  describe "member operations" do
    setup %{leader: leader, member: member} do
      {:ok, guild} = Guilds.create_guild(leader.id, "Test Guild", "TEST")
      {:ok, guild: guild, leader: leader, member: member}
    end

    test "add_member adds to guild", %{guild: guild, leader: leader, member: member} do
      {:ok, membership} = Guilds.add_member(guild.id, member.id, leader.id)

      assert membership.guild_id == guild.id
      assert membership.rank_index == 4  # Default lowest rank
    end

    test "add_member fails without permission", %{guild: guild, leader: leader, member: member} do
      # Add member, then try to invite another
      {:ok, _} = Guilds.add_member(guild.id, member.id, leader.id)

      email3 = "guild_test#{System.unique_integer([:positive])}@test.com"
      {:ok, account3} = Accounts.create_account(email3, "password123")

      {:ok, another} =
        Characters.create_character(account3.id, %{
          name: "Another#{System.unique_integer([:positive])}",
          sex: 0, race: 0, class: 0, faction_id: 166, world_id: 1, world_zone_id: 1
        })

      # Initiates (rank 4) cannot invite
      {:error, :no_permission} = Guilds.add_member(guild.id, another.id, member.id)
    end

    test "remove_member kicks member", %{guild: guild, leader: leader, member: member} do
      {:ok, _} = Guilds.add_member(guild.id, member.id, leader.id)
      :ok = Guilds.remove_member(guild.id, member.id, leader.id)

      assert Guilds.get_membership(member.id) == nil
    end

    test "cannot kick guild leader", %{guild: guild, leader: leader, member: member} do
      {:ok, _} = Guilds.add_member(guild.id, member.id, leader.id)
      # Promote member to officer
      {:ok, _} = Guilds.promote_member(guild.id, member.id, leader.id)
      {:ok, _} = Guilds.promote_member(guild.id, member.id, leader.id)
      {:ok, _} = Guilds.promote_member(guild.id, member.id, leader.id)  # Now rank 1

      {:error, :cannot_kick_leader} = Guilds.remove_member(guild.id, leader.id, member.id)
    end

    test "leave_guild removes member", %{guild: guild, leader: leader, member: member} do
      {:ok, _} = Guilds.add_member(guild.id, member.id, leader.id)
      :ok = Guilds.leave_guild(member.id)

      assert Guilds.get_membership(member.id) == nil
    end

    test "leader cannot leave", %{leader: leader} do
      {:error, :leader_cannot_leave} = Guilds.leave_guild(leader.id)
    end
  end

  describe "rank operations" do
    setup %{leader: leader, member: member} do
      {:ok, guild} = Guilds.create_guild(leader.id, "Test Guild", "TEST")
      {:ok, _} = Guilds.add_member(guild.id, member.id, leader.id)
      {:ok, guild: guild, leader: leader, member: member}
    end

    test "promote_member lowers rank index", %{guild: guild, leader: leader, member: member} do
      membership = Guilds.get_membership(member.id)
      assert membership.rank_index == 4

      {:ok, updated} = Guilds.promote_member(guild.id, member.id, leader.id)
      assert updated.rank_index == 3
    end

    test "cannot promote to guild master", %{guild: guild, leader: leader, member: member} do
      {:ok, _} = Guilds.promote_member(guild.id, member.id, leader.id)  # 3
      {:ok, _} = Guilds.promote_member(guild.id, member.id, leader.id)  # 2
      {:ok, _} = Guilds.promote_member(guild.id, member.id, leader.id)  # 1

      {:error, :cannot_promote_to_leader} = Guilds.promote_member(guild.id, member.id, leader.id)
    end

    test "demote_member raises rank index", %{guild: guild, leader: leader, member: member} do
      {:ok, _} = Guilds.promote_member(guild.id, member.id, leader.id)  # 3
      {:ok, demoted} = Guilds.demote_member(guild.id, member.id, leader.id)

      assert demoted.rank_index == 4
    end

    test "cannot demote below lowest rank", %{guild: guild, leader: leader, member: member} do
      {:error, :already_lowest_rank} = Guilds.demote_member(guild.id, member.id, leader.id)
    end

    test "transfer_leadership swaps ranks", %{guild: guild, leader: leader, member: member} do
      {:ok, _} = Guilds.promote_member(guild.id, member.id, leader.id)  # Rank 3

      {:ok, updated_guild} = Guilds.transfer_leadership(guild.id, member.id, leader.id)

      assert updated_guild.leader_id == member.id

      new_leader = Guilds.get_membership(member.id)
      assert new_leader.rank_index == 0

      old_leader = Guilds.get_membership(leader.id)
      assert old_leader.rank_index == 3
    end
  end

  describe "guild settings" do
    setup %{leader: leader} do
      {:ok, guild} = Guilds.create_guild(leader.id, "Test Guild", "TEST")
      {:ok, guild: guild, leader: leader}
    end

    test "update_motd changes MOTD", %{guild: guild, leader: leader} do
      {:ok, updated} = Guilds.update_motd(guild.id, "Welcome to our guild!", leader.id)
      assert updated.motd == "Welcome to our guild!"
    end

    test "update_rank_name changes rank name", %{guild: guild, leader: leader} do
      {:ok, rank} = Guilds.update_rank_name(guild.id, 1, "Council", leader.id)
      assert rank.name == "Council"
    end
  end

  describe "guild bank" do
    setup %{leader: leader} do
      {:ok, guild} = Guilds.create_guild(leader.id, "Test Guild", "TEST")
      {:ok, guild: guild, leader: leader}
    end

    test "bank_deposit adds item", %{guild: guild, leader: leader} do
      {:ok, item} = Guilds.bank_deposit(guild.id, 0, 0, 1001, 5, %{}, leader.id)

      assert item.item_id == 1001
      assert item.stack_count == 5
      assert item.depositor_id == leader.id
    end

    test "bank_deposit fails on occupied slot", %{guild: guild, leader: leader} do
      {:ok, _} = Guilds.bank_deposit(guild.id, 0, 0, 1001, 1, %{}, leader.id)
      {:error, :slot_occupied} = Guilds.bank_deposit(guild.id, 0, 0, 1002, 1, %{}, leader.id)
    end

    test "bank_withdraw removes item", %{guild: guild, leader: leader} do
      {:ok, _} = Guilds.bank_deposit(guild.id, 0, 0, 1001, 5, %{}, leader.id)
      {:ok, item} = Guilds.bank_withdraw(guild.id, 0, 0, leader.id)

      assert item.item_id == 1001
      assert Guilds.get_bank_tab(guild.id, 0) == []
    end

    test "bank_move_item moves to new slot", %{guild: guild, leader: leader} do
      {:ok, _} = Guilds.bank_deposit(guild.id, 0, 0, 1001, 5, %{}, leader.id)
      {:ok, moved} = Guilds.bank_move_item(guild.id, 0, 0, 0, 10, leader.id)

      assert moved.slot_index == 10
    end

    test "bank_deposit fails on locked tab", %{guild: guild, leader: leader} do
      # Tab 1 is locked by default (only tab 0 unlocked)
      {:error, :tab_not_unlocked} = Guilds.bank_deposit(guild.id, 1, 0, 1001, 1, %{}, leader.id)
    end

    test "unlock_bank_tab unlocks new tab", %{guild: guild, leader: leader} do
      {:ok, updated} = Guilds.unlock_bank_tab(guild.id, leader.id)
      assert updated.bank_tabs_unlocked == 2

      {:ok, _} = Guilds.bank_deposit(guild.id, 1, 0, 1001, 1, %{}, leader.id)
    end
  end

  describe "influence" do
    setup %{leader: leader} do
      {:ok, guild} = Guilds.create_guild(leader.id, "Test Guild", "TEST")
      {:ok, guild: guild, leader: leader}
    end

    test "add_influence increases guild influence", %{guild: guild, leader: leader} do
      {:ok, updated} = Guilds.add_influence(guild.id, 500, leader.id)
      assert updated.influence == 500
    end

    test "add_influence tracks member contribution", %{guild: guild, leader: leader} do
      {:ok, _} = Guilds.add_influence(guild.id, 500, leader.id)

      member = Guilds.get_membership(leader.id)
      assert member.total_influence == 500
    end
  end

  describe "permissions" do
    test "default_ranks have correct permissions" do
      ranks = GuildRank.default_ranks()

      gm = Enum.find(ranks, &(&1.rank_index == 0))
      assert gm.permissions > 0  # GM has all permissions

      initiate = Enum.find(ranks, &(&1.rank_index == 4))
      assert initiate.permissions == 0  # Initiates have no permissions
    end
  end
end
