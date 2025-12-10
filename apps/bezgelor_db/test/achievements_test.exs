defmodule BezgelorDb.AchievementsTest do
  use ExUnit.Case

  alias BezgelorDb.{Accounts, Characters, Achievements, Repo}

  @moduletag :database

  setup do
    case Repo.start_link([]) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    # Create test account and character
    email = "ach_test#{System.unique_integer([:positive])}@test.com"
    {:ok, account} = Accounts.create_account(email, "password123")

    {:ok, character} =
      Characters.create_character(account.id, %{
        name: "AchTester#{System.unique_integer([:positive])}",
        sex: 0,
        race: 0,
        class: 0,
        faction_id: 166,
        world_id: 1,
        world_zone_id: 1
      })

    {:ok, account: account, character: character}
  end

  describe "update_progress/5" do
    test "creates and updates progress", %{character: character} do
      {:ok, ach, :progress} = Achievements.update_progress(character.id, 1001, 5, 10)

      assert ach.achievement_id == 1001
      assert ach.progress == 5
      refute ach.completed
    end

    test "completes when target reached", %{character: character} do
      {:ok, ach, :completed} = Achievements.update_progress(character.id, 1001, 10, 10, 15)

      assert ach.completed
      assert ach.points_awarded == 15
      assert ach.completed_at != nil
    end

    test "returns already_complete for completed achievement", %{character: character} do
      {:ok, _, :completed} = Achievements.update_progress(character.id, 1001, 10, 10)
      {:ok, ach, :already_complete} = Achievements.update_progress(character.id, 1001, 15, 10)

      assert ach.completed
      assert ach.progress == 10  # Not updated
    end
  end

  describe "increment_progress/5" do
    test "increments progress by amount", %{character: character} do
      {:ok, _, :progress} = Achievements.increment_progress(character.id, 1001, 3, 10)
      {:ok, ach, :progress} = Achievements.increment_progress(character.id, 1001, 4, 10)

      assert ach.progress == 7
    end

    test "completes when increment reaches target", %{character: character} do
      {:ok, _, :progress} = Achievements.increment_progress(character.id, 1001, 8, 10)
      {:ok, ach, :completed} = Achievements.increment_progress(character.id, 1001, 5, 10)

      assert ach.completed
      # Progress is set to target when completing
      assert ach.progress == 10
    end
  end

  describe "update_criteria/6" do
    test "updates criteria progress", %{character: character} do
      all_criteria = ["crit_a", "crit_b", "crit_c"]

      {:ok, ach, :progress} =
        Achievements.update_criteria(character.id, 1001, "crit_a", true, all_criteria)

      assert ach.criteria_progress["crit_a"] == true
      refute ach.completed
    end

    test "completes when all criteria met", %{character: character} do
      all_criteria = ["crit_a", "crit_b"]

      {:ok, _, :progress} =
        Achievements.update_criteria(character.id, 1001, "crit_a", true, all_criteria)

      {:ok, ach, :completed} =
        Achievements.update_criteria(character.id, 1001, "crit_b", true, all_criteria)

      assert ach.completed
    end
  end

  describe "complete/3" do
    test "directly completes achievement", %{character: character} do
      {:ok, ach, :completed} = Achievements.complete(character.id, 1001, 25)

      assert ach.completed
      assert ach.points_awarded == 25
    end
  end

  describe "queries" do
    test "get_achievements returns all", %{character: character} do
      Achievements.complete(character.id, 1001, 10)
      Achievements.update_progress(character.id, 1002, 5, 10)

      achievements = Achievements.get_achievements(character.id)

      assert length(achievements) == 2
    end

    test "get_completed returns only completed", %{character: character} do
      Achievements.complete(character.id, 1001, 10)
      Achievements.update_progress(character.id, 1002, 5, 10)

      completed = Achievements.get_completed(character.id)

      assert length(completed) == 1
      assert hd(completed).achievement_id == 1001
    end

    test "completed? returns correct status", %{character: character} do
      refute Achievements.completed?(character.id, 1001)

      Achievements.complete(character.id, 1001, 10)

      assert Achievements.completed?(character.id, 1001)
    end

    test "total_points sums completed", %{character: character} do
      Achievements.complete(character.id, 1001, 10)
      Achievements.complete(character.id, 1002, 25)
      Achievements.update_progress(character.id, 1003, 5, 10, 15)  # Not complete

      assert Achievements.total_points(character.id) == 35
    end

    test "completed_count counts completed", %{character: character} do
      Achievements.complete(character.id, 1001, 10)
      Achievements.complete(character.id, 1002, 25)
      Achievements.update_progress(character.id, 1003, 5, 10)

      assert Achievements.completed_count(character.id) == 2
    end
  end

  describe "recent_completions/2" do
    test "returns recent in order", %{character: character} do
      Achievements.complete(character.id, 1001, 10)
      Process.sleep(10)  # Ensure different timestamps
      Achievements.complete(character.id, 1002, 10)

      recent = Achievements.recent_completions(character.id, 5)

      assert length(recent) == 2
      assert hd(recent).achievement_id == 1002  # Most recent first
    end
  end
end
