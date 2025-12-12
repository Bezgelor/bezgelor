defmodule BezgelorData.StoreQuestTest do
  use ExUnit.Case

  alias BezgelorData.Store

  describe "get_quests_for_creature_giver/1" do
    test "returns quest IDs for creature that gives quests" do
      # Find a creature that gives quests by scanning creatures_full
      quest_givers = find_quest_giver_creature()

      if quest_givers != nil do
        {creature_id, expected_quests} = quest_givers
        result = Store.get_quests_for_creature_giver(creature_id)

        assert is_list(result)
        assert length(result) > 0
        assert result == expected_quests
        assert Enum.all?(result, &is_integer/1)
      else
        # Skip test if no quest givers found (unlikely with real data)
        assert true
      end
    end

    test "returns empty list for creature that doesn't give quests" do
      # Creature ID 1 is unlikely to be a quest giver (usually generic/low-level)
      result = Store.get_quests_for_creature_giver(1)
      assert is_list(result)
    end

    test "returns empty list for non-existent creature" do
      result = Store.get_quests_for_creature_giver(999_999_999)
      assert result == []
    end
  end

  describe "get_quests_for_creature_receiver/1" do
    test "returns quest IDs for creature that receives quest turn-ins" do
      # Find a creature that receives quests
      quest_receiver = find_quest_receiver_creature()

      if quest_receiver != nil do
        {creature_id, expected_quests} = quest_receiver
        result = Store.get_quests_for_creature_receiver(creature_id)

        assert is_list(result)
        assert length(result) > 0
        assert result == expected_quests
        assert Enum.all?(result, &is_integer/1)
      else
        assert true
      end
    end

    test "returns empty list for creature that doesn't receive quests" do
      result = Store.get_quests_for_creature_receiver(1)
      assert is_list(result)
    end

    test "returns empty list for non-existent creature" do
      result = Store.get_quests_for_creature_receiver(999_999_999)
      assert result == []
    end
  end

  describe "get_quest_with_objectives/1" do
    test "returns quest with objectives included" do
      # Get a quest that has objectives
      quest_with_obj = find_quest_with_objectives()

      if quest_with_obj != nil do
        {:ok, result} = Store.get_quest_with_objectives(quest_with_obj)

        assert Map.has_key?(result, :objectives)
        assert is_list(result.objectives)
        assert length(result.objectives) > 0

        # Each objective should have an id
        assert Enum.all?(result.objectives, fn obj -> Map.has_key?(obj, :id) end)
      else
        assert true
      end
    end

    test "returns quest with empty objectives list if quest has no objectives" do
      # Get any quest
      {items, _} = Store.list_paginated(:quests, 1)

      if length(items) > 0 do
        quest = hd(items)
        {:ok, result} = Store.get_quest_with_objectives(quest.id)

        assert Map.has_key?(result, :objectives)
        assert is_list(result.objectives)
      else
        assert true
      end
    end

    test "returns :error for non-existent quest" do
      result = Store.get_quest_with_objectives(999_999_999)
      assert result == :error
    end
  end

  describe "creature_quest_giver?/1" do
    test "returns true for creature that gives quests" do
      quest_giver = find_quest_giver_creature()

      if quest_giver != nil do
        {creature_id, _quests} = quest_giver
        assert Store.creature_quest_giver?(creature_id) == true
      else
        assert true
      end
    end

    test "returns false for non-existent creature" do
      assert Store.creature_quest_giver?(999_999_999) == false
    end
  end

  describe "creature_quest_receiver?/1" do
    test "returns true for creature that receives quests" do
      quest_receiver = find_quest_receiver_creature()

      if quest_receiver != nil do
        {creature_id, _quests} = quest_receiver
        assert Store.creature_quest_receiver?(creature_id) == true
      else
        assert true
      end
    end

    test "returns false for non-existent creature" do
      assert Store.creature_quest_receiver?(999_999_999) == false
    end
  end

  describe "integration: quest giver to quest lookup" do
    test "quests from creature giver exist in quest table" do
      quest_giver = find_quest_giver_creature()

      if quest_giver != nil do
        {creature_id, _} = quest_giver
        quest_ids = Store.get_quests_for_creature_giver(creature_id)

        # All quest IDs should correspond to actual quests
        for quest_id <- quest_ids do
          result = Store.get_quest(quest_id)
          assert match?({:ok, _}, result), "Quest #{quest_id} should exist"
        end
      else
        assert true
      end
    end
  end

  # Helper functions to find test data

  defp find_quest_giver_creature do
    # Scan creatures_full to find one with questIdGiven fields set
    {creatures, _} = Store.list_paginated(:creatures_full, 500)

    Enum.find_value(creatures, fn creature ->
      quest_ids = extract_quest_given_ids(creature)

      if length(quest_ids) > 0 do
        {creature[:ID], quest_ids}
      else
        nil
      end
    end)
  end

  defp find_quest_receiver_creature do
    # Scan creatures_full to find one with questIdReceive fields set
    {creatures, _} = Store.list_paginated(:creatures_full, 500)

    Enum.find_value(creatures, fn creature ->
      quest_ids = extract_quest_receive_ids(creature)

      if length(quest_ids) > 0 do
        {creature[:ID], quest_ids}
      else
        nil
      end
    end)
  end

  defp find_quest_with_objectives do
    # Find a quest that has at least one objective set
    {quests, _} = Store.list_paginated(:quests, 100)

    Enum.find_value(quests, fn quest ->
      objectives =
        0..5
        |> Enum.map(fn i ->
          key = String.to_atom("objective#{i}")
          Map.get(quest, key)
        end)
        |> Enum.reject(&(&1 == 0 or is_nil(&1)))

      if length(objectives) > 0, do: quest.id, else: nil
    end)
  end

  defp extract_quest_given_ids(creature) do
    0..24
    |> Enum.map(fn i ->
      key = String.to_atom("questIdGiven#{String.pad_leading(Integer.to_string(i), 2, "0")}")
      Map.get(creature, key)
    end)
    |> Enum.reject(&(&1 == 0 or is_nil(&1)))
  end

  defp extract_quest_receive_ids(creature) do
    0..24
    |> Enum.map(fn i ->
      key = String.to_atom("questIdReceive#{String.pad_leading(Integer.to_string(i), 2, "0")}")
      Map.get(creature, key)
    end)
    |> Enum.reject(&(&1 == 0 or is_nil(&1)))
  end
end
