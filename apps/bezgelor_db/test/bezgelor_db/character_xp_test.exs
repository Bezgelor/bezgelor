defmodule BezgelorDb.CharacterXPTest do
  use ExUnit.Case

  alias BezgelorDb.{Accounts, Characters, Repo}

  @moduletag :database

  setup do
    # Start the repo for testing if not already started
    case Repo.start_link([]) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    # Use a transaction for each test and roll back at the end
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    email = "xp_test#{System.unique_integer([:positive])}@test.com"
    {:ok, account} = Accounts.create_account(email, "password123")
    %{account: account}
  end

  describe "add_experience/2" do
    test "adds XP to character total", %{account: account} do
      {:ok, character} = create_test_character(account.id, %{level: 1, total_xp: 0})

      {:ok, updated} = Characters.add_experience(character, 100)

      assert updated.total_xp == 100
      assert updated.level == 1
    end

    test "accumulates XP across multiple calls", %{account: account} do
      {:ok, character} = create_test_character(account.id, %{level: 1, total_xp: 500})

      {:ok, updated1} = Characters.add_experience(character, 200)
      assert updated1.total_xp == 700

      # Second add might cause level up, handle both cases
      result = Characters.add_experience(updated1, 300)
      updated2 = case result do
        {:ok, char, level_up: true} -> char
        {:ok, char} -> char
      end
      assert updated2.total_xp == 1000
    end

    test "returns level up info when XP threshold crossed", %{account: account} do
      # Level 2 requires 1000 XP total
      {:ok, character} = create_test_character(account.id, %{level: 1, total_xp: 900})

      result = Characters.add_experience(character, 200)

      assert {:ok, updated, level_up: true} = result
      assert updated.level == 2
      assert updated.total_xp == 1100
    end

    test "handles multiple level ups at once", %{account: account} do
      # Start at level 1 with 0 XP, add enough for multiple levels
      {:ok, character} = create_test_character(account.id, %{level: 1, total_xp: 0})

      # Add massive XP (should level up multiple times)
      result = Characters.add_experience(character, 5000)

      assert {:ok, updated, level_up: true} = result
      assert updated.level > 2  # Should be level 3 or higher
      assert updated.total_xp == 5000
    end

    test "caps at max level 50", %{account: account} do
      {:ok, character} = create_test_character(account.id, %{level: 49, total_xp: 1_000_000_000})

      result = Characters.add_experience(character, 999_999_999)

      case result do
        {:ok, updated, level_up: true} ->
          assert updated.level <= 50
        {:ok, updated} ->
          assert updated.level <= 50
      end
    end

    test "returns error for negative XP", %{account: account} do
      {:ok, character} = create_test_character(account.id)

      # Note: The function guard should prevent this
      assert_raise FunctionClauseError, fn ->
        Characters.add_experience(character, -100)
      end
    end
  end

  describe "xp_for_level/1" do
    test "level 1 requires base XP" do
      xp = Characters.xp_for_level(1)
      assert xp == 1000
    end

    test "higher levels require more XP" do
      xp1 = Characters.xp_for_level(1)
      xp10 = Characters.xp_for_level(10)
      xp50 = Characters.xp_for_level(50)

      assert xp10 > xp1
      assert xp50 > xp10
    end
  end

  describe "total_xp_for_level/1" do
    test "level 1 requires 0 total XP" do
      assert Characters.total_xp_for_level(1) == 0
    end

    test "level 2 requires cumulative XP from level 1" do
      xp = Characters.total_xp_for_level(2)
      assert xp == Characters.xp_for_level(1)
    end

    test "level 3 requires cumulative XP from levels 1-2" do
      xp = Characters.total_xp_for_level(3)
      assert xp == Characters.xp_for_level(1) + Characters.xp_for_level(2)
    end
  end

  defp create_test_character(account_id, attrs \\ %{}) do
    name = "XPTest#{System.unique_integer([:positive])}"
    default_attrs = %{
      name: name,
      sex: 0,
      race: 0,
      class: 1,
      faction_id: 166,
      world_id: 1,
      world_zone_id: 1,
      level: 1,
      total_xp: 0
    }

    Characters.create_character(account_id, Map.merge(default_attrs, attrs))
  end
end
