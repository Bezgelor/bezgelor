defmodule BezgelorWorld.Quest.ObjectiveHandler do
  @moduledoc """
  Handles quest objective progress tracking and completion.

  ## Objective Types

  Based on analysis of quest_objectives data:

  | Type | Count | Description |
  |------|-------|-------------|
  | 38   | 2520  | Generic/script-triggered |
  | 5    | 1556  | Enter location/zone |
  | 12   | 1187  | Interact with object |
  | 32   | 709   | Achieve condition |
  | 2    | 598   | Kill specific creature |
  | 22   | 511   | Kill creature type count |
  | 8    | 498   | Use item |
  | 14   | 426   | Escort/protect NPC |
  | 3    | 350   | Collect item |
  | 4    | 327   | Talk to NPC |
  | 31   | 260   | Complete event |
  | 33   | 215   | Gather resource |
  | 17   | 199   | Use spell/ability |
  | 25   | 152   | Explore location |
  | 11   | 128   | Complete objective sequence |
  | 23   | 96    | Kill elite creature |
  | 16   | 55    | Timed event |
  | 10   | 52    | Loot item from creature |
  | 24   | 39    | Escort to location |
  | 18   | 35    | Defend location |

  ## Usage

      # Process a kill event
      ObjectiveHandler.process_event(:kill, character_id, %{creature_id: 1234})

      # Process location entry
      ObjectiveHandler.process_event(:enter_location, character_id, %{location_id: 567})
  """

  alias BezgelorData.Store
  alias BezgelorDb.Quests
  alias BezgelorWorld.Handler.QuestHandler

  require Logger

  # Objective type constants
  @type_kill_creature 2
  @type_collect_item 3
  @type_talk_to_npc 4
  @type_enter_location 5
  @type_use_item 8
  @type_escort_npc 14
  @type_interact_object 12
  @type_timed_event 16
  @type_use_ability 17
  @type_defend_location 18
  @type_kill_creature_type 22
  @type_kill_elite 23
  @type_escort_to_location 24
  @type_explore 25
  @type_complete_event 31
  @type_achieve_condition 32
  @type_gather_resource 33
  @type_generic 38
  @type_loot_item 10
  @type_objective_sequence 11

  @doc """
  Process a game event and update relevant quest objectives.

  Events:
  - `:kill` - Creature killed, data: %{creature_id: id}
  - `:loot` - Item looted, data: %{item_id: id, count: n}
  - `:interact` - Object interacted with, data: %{object_id: id}
  - `:enter_location` - Entered a location, data: %{location_id: id, zone_id: id}
  - `:talk_npc` - Talked to NPC, data: %{creature_id: id}
  - `:use_item` - Used an item, data: %{item_id: id}
  - `:use_ability` - Used an ability, data: %{spell_id: id}
  - `:gather` - Gathered a resource, data: %{node_id: id, resource_type: type}
  """
  @spec process_event(atom(), pid(), non_neg_integer(), map()) :: :ok
  def process_event(event_type, connection_pid, character_id, event_data) do
    # Get all active quests for character
    quests = Quests.get_active_quests(character_id)

    Enum.each(quests, fn quest ->
      process_quest_objectives(event_type, connection_pid, character_id, quest, event_data)
    end)

    :ok
  end

  # Process objectives for a single quest
  defp process_quest_objectives(event_type, connection_pid, character_id, quest, event_data) do
    objectives = get_in(quest.progress, ["objectives"]) || []

    Enum.each(objectives, fn obj ->
      obj_type = obj["type"]
      obj_data = obj["data"]
      current = obj["current"] || 0
      target = obj["target"] || 1
      index = obj["index"]

      if current < target and matches_event?(event_type, obj_type, obj_data, event_data) do
        # Increment the objective
        QuestHandler.increment_objective(connection_pid, character_id, quest.quest_id, index)
        Logger.debug("Quest #{quest.quest_id} objective #{index} incremented for #{event_type}")
      end
    end)
  end

  # Check if an event matches an objective type
  defp matches_event?(:kill, obj_type, obj_data, %{creature_id: creature_id}) do
    case obj_type do
      @type_kill_creature ->
        obj_data == creature_id

      @type_kill_creature_type ->
        # Check if creature matches the type
        matches_creature_type?(creature_id, obj_data)

      @type_kill_elite ->
        # Check if creature is elite and matches
        is_elite_creature?(creature_id) and (obj_data == 0 or obj_data == creature_id)

      @type_generic ->
        # Generic objectives might track kills
        obj_data == creature_id

      _ ->
        false
    end
  end

  defp matches_event?(:loot, obj_type, obj_data, %{item_id: item_id}) do
    case obj_type do
      @type_collect_item -> obj_data == item_id
      @type_loot_item -> obj_data == item_id
      @type_generic -> obj_data == item_id
      _ -> false
    end
  end

  defp matches_event?(:interact, obj_type, obj_data, %{object_id: object_id}) do
    case obj_type do
      @type_interact_object -> obj_data == object_id
      @type_generic -> obj_data == object_id
      _ -> false
    end
  end

  defp matches_event?(:enter_location, obj_type, obj_data, %{location_id: location_id}) do
    case obj_type do
      @type_enter_location -> obj_data == location_id
      @type_explore -> obj_data == location_id
      @type_escort_to_location -> obj_data == location_id
      @type_generic -> obj_data == location_id
      _ -> false
    end
  end

  defp matches_event?(:enter_location, obj_type, obj_data, %{zone_id: zone_id}) do
    case obj_type do
      @type_enter_location -> obj_data == zone_id
      @type_explore -> obj_data == zone_id
      @type_generic -> obj_data == zone_id
      _ -> false
    end
  end

  defp matches_event?(:talk_npc, obj_type, obj_data, %{creature_id: creature_id}) do
    case obj_type do
      @type_talk_to_npc -> obj_data == creature_id
      @type_generic -> obj_data == creature_id
      _ -> false
    end
  end

  defp matches_event?(:use_item, obj_type, obj_data, %{item_id: item_id}) do
    case obj_type do
      @type_use_item -> obj_data == item_id
      @type_generic -> obj_data == item_id
      _ -> false
    end
  end

  defp matches_event?(:use_ability, obj_type, obj_data, %{spell_id: spell_id}) do
    case obj_type do
      @type_use_ability -> obj_data == spell_id
      @type_generic -> obj_data == spell_id
      _ -> false
    end
  end

  defp matches_event?(:gather, obj_type, obj_data, %{node_id: node_id}) do
    case obj_type do
      @type_gather_resource -> obj_data == node_id
      @type_generic -> obj_data == node_id
      _ -> false
    end
  end

  defp matches_event?(:complete_event, obj_type, obj_data, %{event_id: event_id}) do
    case obj_type do
      @type_complete_event -> obj_data == event_id
      @type_generic -> obj_data == event_id
      _ -> false
    end
  end

  defp matches_event?(:defend, obj_type, obj_data, %{location_id: location_id}) do
    case obj_type do
      @type_defend_location -> obj_data == location_id
      @type_generic -> obj_data == location_id
      _ -> false
    end
  end

  defp matches_event?(:escort_complete, obj_type, obj_data, %{npc_id: npc_id}) do
    case obj_type do
      @type_escort_npc -> obj_data == npc_id
      @type_generic -> obj_data == npc_id
      _ -> false
    end
  end

  defp matches_event?(:condition_met, obj_type, obj_data, %{condition_id: condition_id}) do
    case obj_type do
      @type_achieve_condition -> obj_data == condition_id
      @type_generic -> obj_data == condition_id
      _ -> false
    end
  end

  defp matches_event?(:sequence_step, obj_type, obj_data, %{sequence_id: sequence_id}) do
    case obj_type do
      @type_objective_sequence -> obj_data == sequence_id
      @type_generic -> obj_data == sequence_id
      _ -> false
    end
  end

  defp matches_event?(:timer_complete, obj_type, obj_data, %{timer_id: timer_id}) do
    case obj_type do
      @type_timed_event -> obj_data == timer_id
      @type_generic -> obj_data == timer_id
      _ -> false
    end
  end

  defp matches_event?(_, _, _, _), do: false

  # Helper: Check if creature matches a creature type
  defp matches_creature_type?(creature_id, type_data) do
    case Store.get_creature_full(creature_id) do
      {:ok, creature} ->
        # type_data might be a creature group, tier, or archetype
        tier_id = Map.get(creature, :tierId) || Map.get(creature, :tier_id)
        archetype_id = Map.get(creature, :archetypeId) || Map.get(creature, :archetype_id)
        tier_id == type_data or archetype_id == type_data

      :error ->
        false
    end
  end

  # Helper: Check if creature is elite
  defp is_elite_creature?(creature_id) do
    case Store.get_creature_full(creature_id) do
      {:ok, creature} ->
        # difficulty_id >= 3 typically means elite in WildStar
        difficulty_id = Map.get(creature, :difficultyId) || Map.get(creature, :difficulty_id) || 0
        difficulty_id >= 3

      :error ->
        false
    end
  end

  @doc """
  Initialize objective progress from quest objective definitions.

  Converts static objective definitions to tracking format.
  """
  @spec init_objectives(list(map())) :: list(map())
  def init_objectives(objective_defs) do
    objective_defs
    |> Enum.with_index()
    |> Enum.map(fn {obj_def, index} ->
      %{
        "index" => index,
        "type" => obj_def[:type] || obj_def["type"],
        "data" => obj_def[:data] || obj_def["data"],
        "current" => 0,
        "target" => obj_def[:count] || obj_def["count"] || 1,
        "text_id" => obj_def[:localizedTextIdFull] || obj_def["localizedTextIdFull"]
      }
    end)
  end

  @doc """
  Get objective type name for debugging.
  """
  @spec type_name(non_neg_integer()) :: String.t()
  def type_name(@type_kill_creature), do: "kill_creature"
  def type_name(@type_collect_item), do: "collect_item"
  def type_name(@type_talk_to_npc), do: "talk_to_npc"
  def type_name(@type_enter_location), do: "enter_location"
  def type_name(@type_use_item), do: "use_item"
  def type_name(@type_interact_object), do: "interact_object"
  def type_name(@type_escort_npc), do: "escort_npc"
  def type_name(@type_timed_event), do: "timed_event"
  def type_name(@type_use_ability), do: "use_ability"
  def type_name(@type_defend_location), do: "defend_location"
  def type_name(@type_kill_creature_type), do: "kill_creature_type"
  def type_name(@type_kill_elite), do: "kill_elite"
  def type_name(@type_escort_to_location), do: "escort_to_location"
  def type_name(@type_explore), do: "explore"
  def type_name(@type_complete_event), do: "complete_event"
  def type_name(@type_achieve_condition), do: "achieve_condition"
  def type_name(@type_gather_resource), do: "gather_resource"
  def type_name(@type_generic), do: "generic"
  def type_name(@type_loot_item), do: "loot_item"
  def type_name(@type_objective_sequence), do: "objective_sequence"
  def type_name(type), do: "unknown_#{type}"
end
