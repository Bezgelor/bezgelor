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
  | 15   | 26    | Discover point of interest |
  | 9    | 18    | Complete dungeon event |
  | 20   | 11    | Activate datacube/lore |
  | 21   | 10    | Scan creature |
  | 35   | 10    | Complete challenge |
  | 44   | 7     | Earn achievement |
  | 36   | 6     | Reach reputation level |
  | 28   | 5     | Win PvP match |
  | 37   | 4     | Reach character level |
  | 13   | 3     | Craft item |
  | 19   | 2     | Complete path mission |
  | 29   | 2     | Capture objective point |
  | 39   | 2     | Housing interaction |
  | 40   | 2     | Mount related |
  | 41   | 2     | Costume/appearance |
  | 42   | 2     | Earn title |
  | 47   | 2     | Social interaction |
  | 48   | 2     | Guild related |
  | 6    | ?     | Deliver item to NPC |
  | 7    | ?     | Equip specific item |
  | 27   | 1     | Special scripted |
  | 46   | 1     | Earn/spend currency |

  ## Usage

      # Process a kill event
      ObjectiveHandler.process_event(:kill, character_id, %{creature_id: 1234})

      # Process location entry
      ObjectiveHandler.process_event(:enter_location, character_id, %{location_id: 567})
  """

  require Logger

  # ============================================================================
  # Objective Type Constants (all 40 types from quest_objectives data)
  # ============================================================================

  # Combat objectives
  # 598 objectives - Kill specific creature
  @type_kill_creature 2
  # 511 objectives - Kill creatures of type/tier
  @type_kill_creature_type 22
  # 96 objectives - Kill elite creature
  @type_kill_elite 23

  # Item objectives
  # 350 objectives - Collect/loot item
  @type_collect_item 3
  # 52 objectives - Loot item from creature
  @type_loot_item 10
  # 498 objectives - Use an item
  @type_use_item 8
  # Deliver item to NPC
  @type_deliver_item 6
  # Equip specific item
  @type_equip_item 7
  # 3 objectives - Craft item
  @type_craft_item 13

  # Interaction objectives
  # 327 objectives - Talk to NPC
  @type_talk_to_npc 4
  # 1187 objectives - Interact with object
  @type_interact_object 12
  # 11 objectives - Activate datacube/lore
  @type_activate_datacube 20
  # 10 objectives - Scan creature
  @type_scan_creature 21

  # Location objectives
  # 1556 objectives - Enter location/zone
  @type_enter_location 5
  # 152 objectives - Explore location
  @type_explore 25
  # 26 objectives - Discover point of interest
  @type_discover_poi 15

  # Escort/defense objectives
  # 426 objectives - Escort/protect NPC
  @type_escort_npc 14
  # 35 objectives - Defend location
  @type_defend_location 18
  # 39 objectives - Escort NPC to location
  @type_escort_to_location 24

  # Ability objectives
  # 199 objectives - Use spell/ability
  @type_use_ability 17

  # Resource objectives
  # 215 objectives - Gather resource node
  @type_gather_resource 33

  # Event/sequence objectives
  # 260 objectives - Complete public event
  @type_complete_event 31
  # 709 objectives - Achieve condition/state
  @type_achieve_condition 32
  # 128 objectives - Complete objective sequence
  @type_objective_sequence 11
  # 18 objectives - Complete dungeon event
  @type_complete_dungeon 9
  # 55 objectives - Complete timed event
  @type_timed_event 16

  # Path objectives
  # 2 objectives - Complete path mission
  @type_path_mission 19

  # PvP/competitive objectives
  # 5 objectives - Win PvP match/battleground
  @type_win_pvp 28
  # 2 objectives - Capture objective point
  @type_capture_point 29
  # 10 objectives - Complete challenge
  @type_challenge 35

  # Specialized objectives
  # 6 objectives - Reach reputation level
  @type_reputation 36
  # 4 objectives - Reach character level
  @type_level_requirement 37
  # 2 objectives - Housing interaction
  @type_housing 39
  # 2 objectives - Mount related
  @type_mount 40
  # 2 objectives - Costume/appearance
  @type_costume 41
  # 2 objectives - Earn title
  @type_title 42
  # 7 objectives - Earn achievement
  @type_achievement 44
  # 1 objective - Earn/spend currency
  @type_currency 46
  # 2 objectives - Social interaction
  @type_social 47
  # 2 objectives - Guild related
  @type_guild 48

  # Generic/script-triggered (most common - fallback for many types)
  # 2520 objectives - Script-triggered
  @type_generic 38
  # 1 objective - Special scripted
  @type_special 27

  @doc """
  Process a game event and update relevant quest objectives.

  Sends the event to the Connection process for session-based tracking.
  The Connection will delegate to SessionQuestManager.

  Events:
  - `:kill` - Creature killed, data: %{creature_id: id}
  - `:loot` - Item looted, data: %{item_id: id, count: n}
  - `:interact` - Object interacted with, data: %{object_id: id}
  - `:enter_location` - Entered a location, data: %{location_id: id, zone_id: id}
  - `:talk_npc` - Talked to NPC, data: %{creature_id: id}
  - `:use_item` - Used an item, data: %{item_id: id}
  - `:use_ability` - Used an ability, data: %{spell_id: id}
  - `:gather` - Gathered a resource, data: %{node_id: id, resource_type: type}
  - `:deliver_item` - Item delivered to NPC, data: %{item_id: id, npc_id: id}
  - `:equip_item` - Item equipped, data: %{item_id: id}
  - `:craft` - Item crafted, data: %{item_id: id}
  - `:datacube` - Datacube/lore activated, data: %{datacube_id: id}
  - `:scan` - Creature scanned, data: %{creature_id: id}
  - `:discover_poi` - Point of interest discovered, data: %{poi_id: id}
  - `:escort_complete` - Escort completed, data: %{escort_id: id}
  - `:defend_complete` - Defense completed, data: %{location_id: id}
  - `:dungeon_complete` - Dungeon event completed, data: %{dungeon_id: id}
  - `:sequence_step` - Objective sequence step, data: %{sequence_id: id}
  - `:timed_complete` - Timed event completed, data: %{timer_id: id}
  - `:path_complete` - Path mission completed, data: %{mission_id: id}
  - `:pvp_win` - PvP victory, data: %{battleground_id: id}
  - `:capture` - Capture point taken, data: %{point_id: id}
  - `:challenge_complete` - Challenge completed, data: %{challenge_id: id}
  - `:complete_event` - Public event completed, data: %{event_id: id}
  - `:condition_met` - Condition achieved, data: %{condition_id: id}
  - `:reputation_gain` - Reputation earned, data: %{faction_id: id, level: n}
  - `:level_up` - Character leveled up, data: %{level: n}
  - `:housing` - Housing interaction, data: %{housing_id: id}
  - `:mount` - Mount used, data: %{mount_id: id}
  - `:costume` - Costume changed, data: %{costume_id: id}
  - `:title` - Title earned, data: %{title_id: id}
  - `:achievement` - Achievement earned, data: %{achievement_id: id}
  - `:currency` - Currency transaction, data: %{currency_id: id, amount: n}
  - `:social` - Social interaction, data: %{social_type: type}
  - `:guild` - Guild activity, data: %{guild_action: action}
  - `:special` - Special scripted event, data: %{special_id: id}
  """
  @spec process_event(atom(), pid(), non_neg_integer(), map()) :: :ok
  def process_event(event_type, connection_pid, _character_id, event_data) do
    # Send game event to the connection process for session-based tracking
    # Connection.handle_info will delegate to SessionQuestManager
    send(connection_pid, {:game_event, event_type, event_data})
    :ok
  end

  # Note: Direct objective matching functions were removed as they are now handled
  # by SessionQuestManager. If direct matching is needed in the future, see git history.

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
  # Combat
  def type_name(@type_kill_creature), do: "kill_creature"
  def type_name(@type_kill_creature_type), do: "kill_creature_type"
  def type_name(@type_kill_elite), do: "kill_elite"
  # Items
  def type_name(@type_collect_item), do: "collect_item"
  def type_name(@type_loot_item), do: "loot_item"
  def type_name(@type_use_item), do: "use_item"
  def type_name(@type_deliver_item), do: "deliver_item"
  def type_name(@type_equip_item), do: "equip_item"
  def type_name(@type_craft_item), do: "craft_item"
  # Interaction
  def type_name(@type_talk_to_npc), do: "talk_to_npc"
  def type_name(@type_interact_object), do: "interact_object"
  def type_name(@type_activate_datacube), do: "activate_datacube"
  def type_name(@type_scan_creature), do: "scan_creature"
  # Location
  def type_name(@type_enter_location), do: "enter_location"
  def type_name(@type_explore), do: "explore"
  def type_name(@type_discover_poi), do: "discover_poi"
  # Escort/defense
  def type_name(@type_escort_npc), do: "escort_npc"
  def type_name(@type_defend_location), do: "defend_location"
  def type_name(@type_escort_to_location), do: "escort_to_location"
  # Ability
  def type_name(@type_use_ability), do: "use_ability"
  # Resource
  def type_name(@type_gather_resource), do: "gather_resource"
  # Event/sequence
  def type_name(@type_complete_event), do: "complete_event"
  def type_name(@type_achieve_condition), do: "achieve_condition"
  def type_name(@type_objective_sequence), do: "objective_sequence"
  def type_name(@type_complete_dungeon), do: "complete_dungeon"
  def type_name(@type_timed_event), do: "timed_event"
  # Path
  def type_name(@type_path_mission), do: "path_mission"
  # PvP/competitive
  def type_name(@type_win_pvp), do: "win_pvp"
  def type_name(@type_capture_point), do: "capture_point"
  def type_name(@type_challenge), do: "challenge"
  # Specialized
  def type_name(@type_reputation), do: "reputation"
  def type_name(@type_level_requirement), do: "level_requirement"
  def type_name(@type_housing), do: "housing"
  def type_name(@type_mount), do: "mount"
  def type_name(@type_costume), do: "costume"
  def type_name(@type_title), do: "title"
  def type_name(@type_achievement), do: "achievement"
  def type_name(@type_currency), do: "currency"
  def type_name(@type_social), do: "social"
  def type_name(@type_guild), do: "guild"
  # Generic/special
  def type_name(@type_generic), do: "generic"
  def type_name(@type_special), do: "special"
  def type_name(type), do: "unknown_#{type}"
end
