defmodule BezgelorWorld.Quest.PrerequisiteChecker do
  @moduledoc """
  Validates quest prerequisites.

  Quests have two types of prerequisites:
  1. Direct prerequisites in the quest definition (preq_level, preq_quest0-2, etc.)
  2. Complex prerequisites via the Prerequisite.tbl system

  ## Prerequisite Types (from Prerequisite.tbl)

  Known prerequisite type IDs:
  - 3: Level requirement
  - 6: Quest completion
  - 14: Faction standing

  ## Usage

      PrerequisiteChecker.can_accept_quest?(character_data, quest_data)
      # => {:ok, true} | {:error, :level_too_low} | {:error, :missing_quest_prereq}
  """

  alias BezgelorData.Store
  alias BezgelorDb.{Quests, Reputation}

  require Logger

  @type character_data :: %{
          id: non_neg_integer(),
          level: non_neg_integer(),
          race_id: non_neg_integer(),
          class_id: non_neg_integer(),
          faction_id: non_neg_integer()
        }

  @type check_result :: {:ok, true} | {:error, atom()}

  # Known prerequisite type IDs
  @prereq_type_level 3
  @prereq_type_quest 6
  @prereq_type_faction 14

  @doc """
  Check if a character can accept a quest.

  Validates all direct prerequisites from the quest definition.
  """
  @spec can_accept_quest?(character_data(), map()) :: check_result()
  def can_accept_quest?(character, quest) do
    with :ok <- check_level(character, quest),
         :ok <- check_race(character, quest),
         :ok <- check_class(character, quest),
         :ok <- check_faction(character, quest),
         :ok <- check_prerequisite_quests(character, quest),
         :ok <- check_prerequisite_item(character, quest),
         :ok <- check_not_already_accepted(character, quest),
         :ok <- check_quest_log_space(character) do
      {:ok, true}
    end
  end

  @doc """
  Check complex prerequisite from Prerequisite.tbl.

  Used for content that references the prerequisite table.
  """
  @spec check_prerequisite(character_data(), non_neg_integer()) :: check_result()
  def check_prerequisite(_character, 0), do: {:ok, true}
  def check_prerequisite(_character, nil), do: {:ok, true}

  def check_prerequisite(character, prerequisite_id) do
    case Store.get_prerequisite(prerequisite_id) do
      {:ok, prereq} ->
        check_prerequisite_record(character, prereq)

      :error ->
        Logger.warning("Prerequisite #{prerequisite_id} not found")
        {:ok, true}
    end
  end

  # Check prerequisite record with up to 3 conditions
  defp check_prerequisite_record(character, prereq) do
    # flags & 1 = OR logic (any condition), otherwise AND logic (all conditions)
    use_or_logic = Bitwise.band(prereq[:flags] || 0, 1) == 1

    conditions =
      0..2
      |> Enum.map(fn i ->
        type_key = String.to_atom("prerequisiteTypeId#{i}")
        object_key = String.to_atom("objectId#{i}")
        value_key = String.to_atom("value#{i}")

        type = Map.get(prereq, type_key, 0)
        object = Map.get(prereq, object_key, 0)
        value = Map.get(prereq, value_key, 0)

        {type, object, value}
      end)
      |> Enum.reject(fn {type, _, _} -> type == 0 end)

    if conditions == [] do
      {:ok, true}
    else
      results = Enum.map(conditions, &check_single_condition(character, &1))

      if use_or_logic do
        # Any condition passing is success
        if Enum.any?(results, &match?({:ok, true}, &1)) do
          {:ok, true}
        else
          # Return first error
          Enum.find(results, &match?({:error, _}, &1)) || {:error, :prerequisite_failed}
        end
      else
        # All conditions must pass
        case Enum.find(results, &match?({:error, _}, &1)) do
          nil -> {:ok, true}
          error -> error
        end
      end
    end
  end

  # Check a single prerequisite condition
  defp check_single_condition(character, {type, object, value}) do
    case type do
      @prereq_type_level ->
        if character.level >= value do
          {:ok, true}
        else
          {:error, :level_too_low}
        end

      @prereq_type_quest ->
        # object is quest ID, value is sometimes used for quest state
        if Quests.has_completed?(character.id, object) do
          {:ok, true}
        else
          {:error, :missing_quest_prereq}
        end

      @prereq_type_faction ->
        # object is faction ID, value is required standing
        case Reputation.get_standing(character.id, object) do
          nil ->
            {:error, :faction_standing_too_low}

          standing ->
            if standing >= value, do: {:ok, true}, else: {:error, :faction_standing_too_low}
        end

      _unknown ->
        # Unknown prerequisite type - pass by default
        Logger.debug("Unknown prerequisite type #{type}")
        {:ok, true}
    end
  end

  # Direct prerequisite checks

  defp check_level(character, quest) do
    required_level = Map.get(quest, :preq_level, 0)

    if required_level == 0 or character.level >= required_level do
      :ok
    else
      {:error, :level_too_low}
    end
  end

  defp check_race(character, quest) do
    required_race = Map.get(quest, :preq_race, 0)

    if required_race == 0 or character.race_id == required_race do
      :ok
    else
      {:error, :wrong_race}
    end
  end

  defp check_class(character, quest) do
    required_class = Map.get(quest, :preq_class, 0)

    if required_class == 0 or character.class_id == required_class do
      :ok
    else
      {:error, :wrong_class}
    end
  end

  defp check_faction(character, quest) do
    required_faction = Map.get(quest, :questPlayerFactionEnum, 0)

    cond do
      required_faction == 0 -> :ok
      # 1 = Exile, 2 = Dominion
      required_faction == character.faction_id -> :ok
      true -> {:error, :wrong_faction}
    end
  end

  defp check_prerequisite_quests(character, quest) do
    prereq_quests =
      [:preq_quest0, :preq_quest01, :preq_quest02]
      |> Enum.map(&Map.get(quest, &1, 0))
      |> Enum.reject(&(&1 == 0))

    missing =
      Enum.find(prereq_quests, fn quest_id ->
        not Quests.has_completed?(character.id, quest_id)
      end)

    if missing do
      {:error, :missing_quest_prereq}
    else
      :ok
    end
  end

  defp check_prerequisite_item(_character, quest) do
    required_item = Map.get(quest, :preq_item, 0)

    if required_item == 0 do
      :ok
    else
      # TODO: Check inventory for required item
      # For now, pass if no item required
      :ok
    end
  end

  defp check_not_already_accepted(character, quest) do
    quest_id = Map.get(quest, :id) || Map.get(quest, :ID)

    if quest_id && Quests.has_quest?(character.id, quest_id) do
      {:error, :already_have_quest}
    else
      :ok
    end
  end

  defp check_quest_log_space(character) do
    count = Quests.count_active_quests(character.id)
    max = Quests.max_active_quests()

    if count < max do
      :ok
    else
      {:error, :quest_log_full}
    end
  end

  @doc """
  Get failure message text ID for a prerequisite check.
  """
  @spec get_failure_text(non_neg_integer()) :: non_neg_integer() | nil
  def get_failure_text(0), do: nil
  def get_failure_text(nil), do: nil

  def get_failure_text(prerequisite_id) do
    case Store.get_prerequisite(prerequisite_id) do
      {:ok, prereq} ->
        text_id = Map.get(prereq, :localizedTextIdFailure, 0)
        if text_id > 0, do: text_id, else: nil

      :error ->
        nil
    end
  end
end
