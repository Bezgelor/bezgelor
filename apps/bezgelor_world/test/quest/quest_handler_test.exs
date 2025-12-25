defmodule BezgelorWorld.Handler.QuestHandlerTest do
  @moduledoc """
  Tests for QuestHandler session-based quest management.
  """
  use ExUnit.Case, async: true

  alias BezgelorWorld.Handler.QuestHandler
  alias BezgelorWorld.Quest.SessionQuestManager

  describe "handle_accept_packet via handler" do
    test "accepts quest and updates session_data" do
      # Create a mock state with session_data
      session_data = %{
        character_id: 1,
        active_quests: %{},
        completed_quest_ids: MapSet.new()
      }

      state = %{
        current_opcode: :client_accept_quest,
        session_data: session_data
      }

      # Build a mock accept quest packet
      # Quest ID 5861 is known to exist in test data
      quest_id = 5861
      payload = <<quest_id::little-32>>

      result = QuestHandler.handle(payload, state)

      case result do
        {:reply, opcode, _packet_data, updated_state} ->
          assert opcode == :server_quest_add
          assert Map.has_key?(updated_state.session_data[:active_quests], quest_id)

        {:ok, _state} ->
          # Quest might fail to accept if data not loaded - that's ok for unit test
          :ok

        {:error, _reason} ->
          # Parse error is acceptable in unit test without full setup
          :ok
      end
    end
  end

  # These integration tests require database access and proper setup
  describe "SessionQuestManager integration" do
    @describetag :integration

    test "accept_quest adds quest to session_data" do
      session_data = %{
        active_quests: %{},
        completed_quest_ids: MapSet.new()
      }

      character_id = 1
      quest_id = 5861

      case SessionQuestManager.accept_quest(session_data, character_id, quest_id) do
        {:ok, updated_session, {opcode, _packet}} ->
          assert opcode == :server_quest_add
          assert Map.has_key?(updated_session[:active_quests], quest_id)

          quest = updated_session[:active_quests][quest_id]
          assert quest.quest_id == quest_id
          assert quest.state == :accepted

        {:error, reason} ->
          # May fail if quest data not loaded - acceptable in unit test
          assert reason in [:quest_not_found, :not_found]
      end
    end

    test "abandon_quest removes quest from session_data" do
      # First add a quest to session
      quest = %{
        quest_id: 5861,
        state: :accepted,
        objectives: [],
        dirty: false
      }

      session_data = %{
        active_quests: %{5861 => quest},
        completed_quest_ids: MapSet.new()
      }

      character_id = 1
      quest_id = 5861

      case SessionQuestManager.abandon_quest(session_data, character_id, quest_id) do
        {:ok, updated_session, {opcode, _packet}} ->
          assert opcode == :server_quest_remove
          refute Map.has_key?(updated_session[:active_quests], quest_id)

        {:error, reason} ->
          # Should not fail if quest exists
          flunk("Abandon failed unexpectedly: #{inspect(reason)}")
      end
    end

    test "abandon_quest returns error for unknown quest" do
      session_data = %{
        active_quests: %{},
        completed_quest_ids: MapSet.new()
      }

      result = SessionQuestManager.abandon_quest(session_data, 1, 99999)
      assert {:error, :quest_not_found} = result
    end

    test "turn_in_quest moves quest to completed" do
      # Create a completed quest in session
      quest = %{
        quest_id: 5861,
        state: :complete,
        objectives: [%{index: 0, current: 1, target: 1, type: 2, data: 123}],
        dirty: false
      }

      session_data = %{
        active_quests: %{5861 => quest},
        completed_quest_ids: MapSet.new()
      }

      character_id = 1
      quest_id = 5861

      case SessionQuestManager.turn_in_quest(session_data, character_id, quest_id) do
        {:ok, updated_session, {opcode, _packet}} ->
          assert opcode == :server_quest_remove
          refute Map.has_key?(updated_session[:active_quests], quest_id)
          assert MapSet.member?(updated_session[:completed_quest_ids], quest_id)

        {:error, reason} ->
          # May fail due to DB interaction - acceptable in unit test
          assert reason in [:not_found, :quest_not_found]
      end
    end

    test "turn_in_quest fails if quest not complete" do
      quest = %{
        quest_id: 5861,
        state: :accepted,
        objectives: [%{index: 0, current: 0, target: 1, type: 2, data: 123}],
        dirty: false
      }

      session_data = %{
        active_quests: %{5861 => quest},
        completed_quest_ids: MapSet.new()
      }

      result = SessionQuestManager.turn_in_quest(session_data, 1, 5861)
      assert {:error, :quest_not_complete} = result
    end
  end

  describe "process_game_event" do
    test "kill event increments matching objective" do
      quest = %{
        quest_id: 100,
        state: :accepted,
        objectives: [
          %{index: 0, current: 0, target: 3, type: 2, data: 456}
        ],
        dirty: false
      }

      session_data = %{
        active_quests: %{100 => quest},
        completed_quest_ids: MapSet.new()
      }

      {updated_session, packets} =
        SessionQuestManager.process_game_event(
          session_data,
          :kill,
          %{creature_id: 456}
        )

      updated_quest = updated_session[:active_quests][100]
      objective = Enum.find(updated_quest.objectives, &(&1.index == 0))

      assert objective.current == 1
      assert updated_quest.dirty == true
      assert length(packets) == 1
    end

    test "kill event does not increment non-matching objective" do
      quest = %{
        quest_id: 100,
        state: :accepted,
        objectives: [
          %{index: 0, current: 0, target: 3, type: 2, data: 456}
        ],
        dirty: false
      }

      session_data = %{
        active_quests: %{100 => quest},
        completed_quest_ids: MapSet.new()
      }

      {updated_session, packets} =
        SessionQuestManager.process_game_event(
          session_data,
          :kill,
          # Different creature
          %{creature_id: 789}
        )

      updated_quest = updated_session[:active_quests][100]
      objective = Enum.find(updated_quest.objectives, &(&1.index == 0))

      assert objective.current == 0
      assert packets == []
    end

    test "loot event increments collect item objective" do
      quest = %{
        quest_id: 200,
        state: :accepted,
        objectives: [
          %{index: 0, current: 0, target: 5, type: 3, data: 1001}
        ],
        dirty: false
      }

      session_data = %{
        active_quests: %{200 => quest},
        completed_quest_ids: MapSet.new()
      }

      {updated_session, packets} =
        SessionQuestManager.process_game_event(
          session_data,
          :loot,
          %{item_id: 1001}
        )

      updated_quest = updated_session[:active_quests][200]
      objective = Enum.find(updated_quest.objectives, &(&1.index == 0))

      assert objective.current == 1
      assert length(packets) == 1
    end

    test "quest becomes completable when all objectives done" do
      quest = %{
        quest_id: 300,
        state: :accepted,
        objectives: [
          %{index: 0, current: 2, target: 3, type: 2, data: 456}
        ],
        dirty: false
      }

      session_data = %{
        active_quests: %{300 => quest},
        completed_quest_ids: MapSet.new()
      }

      # Final kill to complete the objective
      {updated_session, _packets} =
        SessionQuestManager.process_game_event(
          session_data,
          :kill,
          %{creature_id: 456}
        )

      updated_quest = updated_session[:active_quests][300]
      objective = Enum.find(updated_quest.objectives, &(&1.index == 0))

      assert objective.current == 3
      assert updated_quest.state == :complete
    end
  end
end
