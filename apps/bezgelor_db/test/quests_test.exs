defmodule BezgelorDb.QuestsTest do
  use ExUnit.Case

  alias BezgelorDb.{Accounts, Characters, Quests, Repo}

  @moduletag :database

  setup do
    case Repo.start_link([]) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    # Create test account and character
    email = "quest_test#{System.unique_integer([:positive])}@test.com"
    {:ok, account} = Accounts.create_account(email, "password123")

    {:ok, character} =
      Characters.create_character(account.id, %{
        name: "QuestTester#{System.unique_integer([:positive])}",
        sex: 0,
        race: 0,
        class: 0,
        faction_id: 166,
        world_id: 1,
        world_zone_id: 1
      })

    {:ok, account: account, character: character}
  end

  describe "accept_quest/3" do
    test "accepts quest with initial progress", %{character: character} do
      progress = Quests.init_progress([%{type: "kill", target: 10}])

      {:ok, quest} = Quests.accept_quest(character.id, 1001, progress: progress)

      assert quest.quest_id == 1001
      assert quest.state == :accepted
      assert quest.character_id == character.id

      objectives = get_in(quest.progress, ["objectives"])
      assert length(objectives) == 1
      assert hd(objectives)["target"] == 10
    end

    test "prevents duplicate quest acceptance", %{character: character} do
      {:ok, _} = Quests.accept_quest(character.id, 1001)
      assert {:error, :already_have_quest} = Quests.accept_quest(character.id, 1001)
    end

    test "prevents exceeding quest limit", %{character: character} do
      # Accept max quests
      for i <- 1..25 do
        {:ok, _} = Quests.accept_quest(character.id, i)
      end

      # Try one more
      assert {:error, :quest_log_full} = Quests.accept_quest(character.id, 100)
    end
  end

  describe "get_active_quests/1" do
    test "returns all active quests", %{character: character} do
      {:ok, _} = Quests.accept_quest(character.id, 1001)
      {:ok, _} = Quests.accept_quest(character.id, 1002)

      quests = Quests.get_active_quests(character.id)

      assert length(quests) == 2
      quest_ids = Enum.map(quests, & &1.quest_id)
      assert 1001 in quest_ids
      assert 1002 in quest_ids
    end

    test "excludes failed quests from active list", %{character: character} do
      {:ok, quest} = Quests.accept_quest(character.id, 1001)
      {:ok, _} = Quests.fail_quest(quest)

      quests = Quests.get_active_quests(character.id)
      assert length(quests) == 0
    end
  end

  describe "update_objective/3" do
    test "updates objective progress", %{character: character} do
      progress = Quests.init_progress([%{type: "kill", target: 10}])
      {:ok, quest} = Quests.accept_quest(character.id, 1001, progress: progress)

      {:ok, updated} = Quests.update_objective(quest, 0, 5)

      objectives = get_in(updated.progress, ["objectives"])
      assert hd(objectives)["current"] == 5
    end
  end

  describe "increment_objective/3" do
    test "increments objective by 1", %{character: character} do
      progress = Quests.init_progress([%{type: "kill", target: 10}])
      {:ok, quest} = Quests.accept_quest(character.id, 1001, progress: progress)

      {:ok, updated} = Quests.increment_objective(quest, 0)

      objectives = get_in(updated.progress, ["objectives"])
      assert hd(objectives)["current"] == 1
    end
  end

  describe "mark_complete/1" do
    test "marks quest as complete", %{character: character} do
      {:ok, quest} = Quests.accept_quest(character.id, 1001)

      {:ok, completed} = Quests.mark_complete(quest)

      assert completed.state == :complete
      assert completed.completed_at != nil
    end
  end

  describe "abandon_quest/2" do
    test "removes active quest", %{character: character} do
      {:ok, _} = Quests.accept_quest(character.id, 1001)

      {:ok, _} = Quests.abandon_quest(character.id, 1001)

      refute Quests.has_quest?(character.id, 1001)
    end

    test "returns error for non-existent quest", %{character: character} do
      assert {:error, :not_found} = Quests.abandon_quest(character.id, 9999)
    end
  end

  describe "turn_in_quest/2" do
    test "moves completed quest to history", %{character: character} do
      {:ok, quest} = Quests.accept_quest(character.id, 1001)
      {:ok, _} = Quests.mark_complete(quest)

      {:ok, history} = Quests.turn_in_quest(character.id, 1001)

      assert history.quest_id == 1001
      assert history.completion_count == 1
      refute Quests.has_quest?(character.id, 1001)
      assert Quests.has_completed?(character.id, 1001)
    end

    test "fails for incomplete quest", %{character: character} do
      {:ok, _} = Quests.accept_quest(character.id, 1001)

      assert {:error, :not_complete} = Quests.turn_in_quest(character.id, 1001)
    end

    test "increments completion count for repeatable", %{character: character} do
      # First completion
      {:ok, quest1} = Quests.accept_quest(character.id, 1001)
      {:ok, _} = Quests.mark_complete(quest1)
      {:ok, _} = Quests.turn_in_quest(character.id, 1001)

      # Second completion
      {:ok, quest2} = Quests.accept_quest(character.id, 1001)
      {:ok, _} = Quests.mark_complete(quest2)
      {:ok, history} = Quests.turn_in_quest(character.id, 1001)

      assert history.completion_count == 2
    end
  end

  describe "all_objectives_complete?/1" do
    test "returns true when all objectives met", %{character: character} do
      progress = Quests.init_progress([
        %{type: "kill", target: 5},
        %{type: "item", target: 3}
      ])

      {:ok, quest} = Quests.accept_quest(character.id, 1001, progress: progress)

      # Complete objectives
      {:ok, quest} = Quests.update_objective(quest, 0, 5)
      {:ok, quest} = Quests.update_objective(quest, 1, 3)

      assert Quests.all_objectives_complete?(quest)
    end

    test "returns false with incomplete objectives", %{character: character} do
      progress = Quests.init_progress([%{type: "kill", target: 10}])
      {:ok, quest} = Quests.accept_quest(character.id, 1001, progress: progress)
      {:ok, quest} = Quests.update_objective(quest, 0, 5)

      refute Quests.all_objectives_complete?(quest)
    end
  end

  describe "quest history" do
    test "has_completed? returns false for incomplete", %{character: character} do
      {:ok, _} = Quests.accept_quest(character.id, 1001)
      refute Quests.has_completed?(character.id, 1001)
    end

    test "has_completed? returns true after turn in", %{character: character} do
      {:ok, quest} = Quests.accept_quest(character.id, 1001)
      {:ok, _} = Quests.mark_complete(quest)
      {:ok, _} = Quests.turn_in_quest(character.id, 1001)

      assert Quests.has_completed?(character.id, 1001)
    end

    test "completion_count returns 0 for never completed", %{character: character} do
      assert Quests.completion_count(character.id, 9999) == 0
    end
  end

  describe "init_progress/1" do
    test "creates progress map with objectives" do
      objectives = [
        %{type: "kill", target: 10},
        %{type: "item", target: 5}
      ]

      progress = Quests.init_progress(objectives)

      assert is_map(progress)
      assert is_list(progress["objectives"])
      assert length(progress["objectives"]) == 2

      [obj1, obj2] = progress["objectives"]
      assert obj1["index"] == 0
      assert obj1["current"] == 0
      assert obj1["target"] == 10
      assert obj1["type"] == "kill"

      assert obj2["index"] == 1
      assert obj2["target"] == 5
    end
  end
end
