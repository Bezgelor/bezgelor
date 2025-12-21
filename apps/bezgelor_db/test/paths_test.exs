defmodule BezgelorDb.PathsTest do
  use ExUnit.Case

  alias BezgelorDb.{Accounts, Characters, Paths, Repo}

  @moduletag :database

  setup do
    case Repo.start_link([]) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    # Create test account and character
    email = "path_test#{System.unique_integer([:positive])}@test.com"
    {:ok, account} = Accounts.create_account(email, "password123")

    {:ok, character} =
      Characters.create_character(account.id, %{
        name: "PathTester#{System.unique_integer([:positive])}",
        sex: 0,
        race: 0,
        class: 0,
        faction_id: 166,
        world_id: 1,
        world_zone_id: 1
      })

    {:ok, account: account, character: character}
  end

  describe "path initialization" do
    test "initialize_path creates path", %{character: character} do
      {:ok, path} = Paths.initialize_path(character.id, 0)

      assert path.path_type == 0
      assert path.path_level == 1
      assert path.path_xp == 0
      assert path.unlocked_abilities == []
    end

    test "get_path returns nil when not initialized", %{character: character} do
      assert Paths.get_path(character.id) == nil
    end

    test "get_path returns path when initialized", %{character: character} do
      {:ok, _} = Paths.initialize_path(character.id, 2)
      path = Paths.get_path(character.id)

      assert path.path_type == 2
    end
  end

  describe "XP and leveling" do
    test "award_xp increases XP", %{character: character} do
      {:ok, _} = Paths.initialize_path(character.id, 0)
      {:ok, path, :xp_gained} = Paths.award_xp(character.id, 500)

      assert path.path_xp == 500
      assert path.path_level == 1
    end

    test "award_xp triggers level up", %{character: character} do
      {:ok, _} = Paths.initialize_path(character.id, 0)
      # Level 2 needs 2000 XP (level * 1000)
      {:ok, path, :level_up} = Paths.award_xp(character.id, 2500)

      assert path.path_level == 2
      # 2500 - 2000 for level 2
      assert path.path_xp == 500
    end

    test "award_xp can trigger multiple level ups", %{character: character} do
      {:ok, _} = Paths.initialize_path(character.id, 0)
      # Level 2 = 2000, Level 3 = 3000, Total = 5000
      {:ok, path, :level_up} = Paths.award_xp(character.id, 5500)

      assert path.path_level == 3
      assert path.path_xp == 500
    end

    test "get_progress returns level and XP", %{character: character} do
      {:ok, _} = Paths.initialize_path(character.id, 1)
      {:ok, _, _} = Paths.award_xp(character.id, 750)

      {level, xp} = Paths.get_progress(character.id)

      assert level == 1
      assert xp == 750
    end
  end

  describe "abilities" do
    test "unlock_ability adds ability", %{character: character} do
      {:ok, _} = Paths.initialize_path(character.id, 0)
      {:ok, path} = Paths.unlock_ability(character.id, 1001)

      assert 1001 in path.unlocked_abilities
    end

    test "unlock_ability is idempotent", %{character: character} do
      {:ok, _} = Paths.initialize_path(character.id, 0)
      {:ok, _} = Paths.unlock_ability(character.id, 1001)
      {:ok, path} = Paths.unlock_ability(character.id, 1001)

      assert Enum.count(path.unlocked_abilities, &(&1 == 1001)) == 1
    end

    test "ability_unlocked? returns correct status", %{character: character} do
      {:ok, _} = Paths.initialize_path(character.id, 0)

      refute Paths.ability_unlocked?(character.id, 1001)

      {:ok, _} = Paths.unlock_ability(character.id, 1001)

      assert Paths.ability_unlocked?(character.id, 1001)
    end
  end

  describe "missions" do
    test "accept_mission creates mission", %{character: character} do
      {:ok, _} = Paths.initialize_path(character.id, 0)
      {:ok, mission} = Paths.accept_mission(character.id, 5001)

      assert mission.mission_id == 5001
      assert mission.state == :active
      assert mission.progress == %{}
    end

    test "accept_mission fails for duplicate", %{character: character} do
      {:ok, _} = Paths.initialize_path(character.id, 0)
      {:ok, _} = Paths.accept_mission(character.id, 5001)
      {:error, {:already_exists, :active}} = Paths.accept_mission(character.id, 5001)
    end

    test "update_progress updates mission progress", %{character: character} do
      {:ok, _} = Paths.initialize_path(character.id, 0)
      {:ok, _} = Paths.accept_mission(character.id, 5001)
      {:ok, mission} = Paths.update_progress(character.id, 5001, %{"kills" => 5})

      assert mission.progress["kills"] == 5
    end

    test "increment_counter increments value", %{character: character} do
      {:ok, _} = Paths.initialize_path(character.id, 0)
      {:ok, _} = Paths.accept_mission(character.id, 5001)

      {:ok, _, :progress} = Paths.increment_counter(character.id, 5001, "scans", 1, 10)
      {:ok, mission, :progress} = Paths.increment_counter(character.id, 5001, "scans", 2, 10)

      assert mission.progress["scans"] == 3
    end

    test "increment_counter detects target reached", %{character: character} do
      {:ok, _} = Paths.initialize_path(character.id, 0)
      {:ok, _} = Paths.accept_mission(character.id, 5001)

      {:ok, _, :target_reached} = Paths.increment_counter(character.id, 5001, "scans", 10, 10)
    end

    test "complete_mission marks complete", %{character: character} do
      {:ok, _} = Paths.initialize_path(character.id, 0)
      {:ok, _} = Paths.accept_mission(character.id, 5001)
      {:ok, mission} = Paths.complete_mission(character.id, 5001)

      assert mission.state == :completed
      assert mission.completed_at != nil
    end

    test "fail_mission marks failed", %{character: character} do
      {:ok, _} = Paths.initialize_path(character.id, 0)
      {:ok, _} = Paths.accept_mission(character.id, 5001)
      {:ok, mission} = Paths.fail_mission(character.id, 5001)

      assert mission.state == :failed
    end

    test "abandon_mission removes mission", %{character: character} do
      {:ok, _} = Paths.initialize_path(character.id, 0)
      {:ok, _} = Paths.accept_mission(character.id, 5001)
      :ok = Paths.abandon_mission(character.id, 5001)

      assert Paths.get_mission(character.id, 5001) == nil
    end

    test "abandon completed mission fails", %{character: character} do
      {:ok, _} = Paths.initialize_path(character.id, 0)
      {:ok, _} = Paths.accept_mission(character.id, 5001)
      {:ok, _} = Paths.complete_mission(character.id, 5001)

      {:error, :cannot_abandon_completed} = Paths.abandon_mission(character.id, 5001)
    end

    test "get_active_missions returns active only", %{character: character} do
      {:ok, _} = Paths.initialize_path(character.id, 0)
      {:ok, _} = Paths.accept_mission(character.id, 5001)
      {:ok, _} = Paths.accept_mission(character.id, 5002)
      {:ok, _} = Paths.complete_mission(character.id, 5001)

      missions = Paths.get_active_missions(character.id)

      assert length(missions) == 1
      assert hd(missions).mission_id == 5002
    end

    test "completed_mission_count counts completed", %{character: character} do
      {:ok, _} = Paths.initialize_path(character.id, 0)
      {:ok, _} = Paths.accept_mission(character.id, 5001)
      {:ok, _} = Paths.accept_mission(character.id, 5002)
      {:ok, _} = Paths.complete_mission(character.id, 5001)
      {:ok, _} = Paths.complete_mission(character.id, 5002)

      assert Paths.completed_mission_count(character.id) == 2
    end
  end
end
