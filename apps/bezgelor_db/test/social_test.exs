defmodule BezgelorDb.SocialTest do
  use ExUnit.Case

  alias BezgelorDb.{Accounts, Characters, Repo, Social}

  @moduletag :database

  setup do
    case Repo.start_link([]) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    # Create test account
    email = "social_test#{System.unique_integer([:positive])}@test.com"
    {:ok, account} = Accounts.create_account(email, "password123")

    # Create test characters
    {:ok, char1} = create_character(account.id, "SocialChar1")
    {:ok, char2} = create_character(account.id, "SocialChar2")
    {:ok, char3} = create_character(account.id, "SocialChar3")

    {:ok, account: account, char1: char1, char2: char2, char3: char3}
  end

  describe "friends" do
    test "add_friend/3 creates friend relationship", %{char1: char1, char2: char2} do
      assert {:ok, friend} = Social.add_friend(char1.id, char2.id, "Best friend")

      assert friend.character_id == char1.id
      assert friend.friend_character_id == char2.id
      assert friend.note == "Best friend"
    end

    test "add_friend/3 prevents adding self", %{char1: char1} do
      assert {:error, :cannot_friend_self} = Social.add_friend(char1.id, char1.id)
    end

    test "add_friend/3 prevents duplicate friends", %{char1: char1, char2: char2} do
      assert {:ok, _} = Social.add_friend(char1.id, char2.id)
      assert {:error, _} = Social.add_friend(char1.id, char2.id)
    end

    test "list_friends/1 returns all friends", %{char1: char1, char2: char2, char3: char3} do
      assert {:ok, _} = Social.add_friend(char1.id, char2.id)
      assert {:ok, _} = Social.add_friend(char1.id, char3.id)

      friends = Social.list_friends(char1.id)

      assert length(friends) == 2
      friend_ids = Enum.map(friends, & &1.friend_character_id)
      assert char2.id in friend_ids
      assert char3.id in friend_ids
    end

    test "remove_friend/2 removes friend relationship", %{char1: char1, char2: char2} do
      assert {:ok, _} = Social.add_friend(char1.id, char2.id)
      assert {:ok, _} = Social.remove_friend(char1.id, char2.id)
      assert [] = Social.list_friends(char1.id)
    end

    test "remove_friend/2 returns error for non-existent friend", %{char1: char1, char2: char2} do
      assert {:error, :not_found} = Social.remove_friend(char1.id, char2.id)
    end

    test "is_friend?/2 returns correct status", %{char1: char1, char2: char2} do
      refute Social.is_friend?(char1.id, char2.id)

      assert {:ok, _} = Social.add_friend(char1.id, char2.id)

      assert Social.is_friend?(char1.id, char2.id)
      # Friendship is one-directional
      refute Social.is_friend?(char2.id, char1.id)
    end

    test "update_friend_note/3 updates note", %{char1: char1, char2: char2} do
      assert {:ok, _} = Social.add_friend(char1.id, char2.id, "Old note")
      assert {:ok, friend} = Social.update_friend_note(char1.id, char2.id, "New note")

      assert friend.note == "New note"
    end
  end

  describe "ignores" do
    test "add_ignore/2 creates ignore relationship", %{char1: char1, char2: char2} do
      assert {:ok, ignore} = Social.add_ignore(char1.id, char2.id)

      assert ignore.character_id == char1.id
      assert ignore.ignored_character_id == char2.id
    end

    test "add_ignore/2 prevents ignoring self", %{char1: char1} do
      assert {:error, :cannot_ignore_self} = Social.add_ignore(char1.id, char1.id)
    end

    test "add_ignore/2 prevents duplicate ignores", %{char1: char1, char2: char2} do
      assert {:ok, _} = Social.add_ignore(char1.id, char2.id)
      assert {:error, _} = Social.add_ignore(char1.id, char2.id)
    end

    test "list_ignores/1 returns all ignores", %{char1: char1, char2: char2, char3: char3} do
      assert {:ok, _} = Social.add_ignore(char1.id, char2.id)
      assert {:ok, _} = Social.add_ignore(char1.id, char3.id)

      ignores = Social.list_ignores(char1.id)

      assert length(ignores) == 2
      ignore_ids = Enum.map(ignores, & &1.ignored_character_id)
      assert char2.id in ignore_ids
      assert char3.id in ignore_ids
    end

    test "remove_ignore/2 removes ignore relationship", %{char1: char1, char2: char2} do
      assert {:ok, _} = Social.add_ignore(char1.id, char2.id)
      assert {:ok, _} = Social.remove_ignore(char1.id, char2.id)
      assert [] = Social.list_ignores(char1.id)
    end

    test "remove_ignore/2 returns error for non-existent ignore", %{char1: char1, char2: char2} do
      assert {:error, :not_found} = Social.remove_ignore(char1.id, char2.id)
    end

    test "is_ignored?/2 returns correct status", %{char1: char1, char2: char2} do
      refute Social.is_ignored?(char1.id, char2.id)

      assert {:ok, _} = Social.add_ignore(char1.id, char2.id)

      assert Social.is_ignored?(char1.id, char2.id)
      # Ignore is one-directional
      refute Social.is_ignored?(char2.id, char1.id)
    end

    test "is_ignored_by_either?/2 checks both directions", %{char1: char1, char2: char2} do
      refute Social.is_ignored_by_either?(char1.id, char2.id)

      assert {:ok, _} = Social.add_ignore(char1.id, char2.id)

      assert Social.is_ignored_by_either?(char1.id, char2.id)
      assert Social.is_ignored_by_either?(char2.id, char1.id)
    end
  end

  defp create_character(account_id, name) do
    Characters.create_character(account_id, %{
      name: name,
      sex: 0,
      race: 0,
      class: 0,
      faction_id: 166,
      world_id: 1,
      world_zone_id: 1
    })
  end
end
