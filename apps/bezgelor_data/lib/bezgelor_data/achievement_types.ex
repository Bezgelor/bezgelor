defmodule BezgelorData.AchievementTypes do
  @moduledoc """
  Maps WildStar achievement type IDs to event types.

  Based on analysis of 4,943 achievements across 83 unique types.
  Each achievement type ID maps to an event type that triggers progress.

  ## Type Categories

  - Kill/Combat: Types 2, 61, 105
  - Quest: Types 35, 77
  - Exploration/Zone: Types 5, 8, 12, 121
  - Dungeon/Instance: Types 6, 7, 38, 54, 80, 97, 98, 103
  - Path: Types 37, 40, 96
  - Tradeskill: Types 87, 88, 94, 102
  - Challenge: Types 44, 45
  - PvP: Types 33, 76
  - Datacube/Lore: Types 1, 15, 46, 82
  - Event: Types 57, 116, 137, 143, 157
  - Social/Economy: Types 9, 63
  - Housing: Types 53, 65
  - Adventure: Types 42, 67
  - Meta: Types 104, 141
  - Progression: Types 3, 13, 16

  ## Unmapped Types (312 achievements across 45 minor types)

  These are handled as generic/counter achievements:
  14, 15, 22, 26, 46, 54, 55, 56, 62, 64, 66, 68, 72, 73, 75, 79, 83, 85, 86,
  89, 92, 97, 98, 101, 103, 106, 107, 108, 109, 111, 112, 113, 114, 118, 121,
  129, 130, 131, 133, 137, 140, 143, 152, 156, 157
  """

  # Kill/Combat achievements (506 achievements)
  @kill_types [2, 61, 105]

  # Quest achievements (830 achievements)
  @quest_types [35, 77]

  # Exploration/Zone achievements (984 achievements)
  @zone_types [5, 8, 12, 121]

  # Dungeon/Instance achievements (688 achievements)
  @dungeon_types [6, 7, 38, 54, 80, 97, 98, 103]

  # Path achievements (380 achievements)
  @path_types [37, 40, 96]

  # Tradeskill achievements (202 achievements)
  @tradeskill_types [87, 88, 94, 102]

  # Challenge achievements (184 achievements)
  @challenge_types [44, 45]

  # PvP achievements (117 achievements)
  @pvp_types [33, 76]

  # Datacube/Lore achievements (148 achievements)
  @datacube_types [1, 15, 46, 82]

  # Event achievements (258 achievements)
  @event_types [57, 116, 137, 143, 157]

  # Social/Economy achievements (135 achievements)
  @social_types [9, 63]

  # Housing achievements (49 achievements)
  @housing_types [53, 65]

  # Adventure achievements (29 achievements)
  @adventure_types [42, 67]

  # Meta achievements - triggered by other achievements (22 achievements)
  @meta_types [104, 141]

  # Level/Currency/Progression achievements (50 achievements)
  @progression_types [3, 13, 16]

  # Mount/Pet achievements (14 achievements)
  @mount_types [72, 86]

  # Reputation achievements (19 achievements) - shares type 13 with progression
  # Note: Type 13 is in @progression_types for reputation-based progression

  @doc """
  Get event type for achievement type ID.

  Returns the event type atom that triggers this achievement, or nil if unknown.

  ## Examples

      iex> AchievementTypes.event_type(2)
      :kill

      iex> AchievementTypes.event_type(35)
      :quest_complete

      iex> AchievementTypes.event_type(9999)
      nil
  """
  @spec event_type(non_neg_integer()) :: atom() | nil
  def event_type(type_id) when type_id in @kill_types, do: :kill
  def event_type(type_id) when type_id in @quest_types, do: :quest_complete
  def event_type(type_id) when type_id in @zone_types, do: :zone_explore
  def event_type(type_id) when type_id in @dungeon_types, do: :dungeon_complete
  def event_type(type_id) when type_id in @path_types, do: :path_mission
  def event_type(type_id) when type_id in @tradeskill_types, do: :tradeskill
  def event_type(type_id) when type_id in @challenge_types, do: :challenge_complete
  def event_type(type_id) when type_id in @pvp_types, do: :pvp
  def event_type(type_id) when type_id in @datacube_types, do: :datacube
  def event_type(type_id) when type_id in @event_types, do: :event
  def event_type(type_id) when type_id in @social_types, do: :social
  def event_type(type_id) when type_id in @housing_types, do: :housing
  def event_type(type_id) when type_id in @adventure_types, do: :adventure_complete
  def event_type(type_id) when type_id in @meta_types, do: :meta
  def event_type(type_id) when type_id in @progression_types, do: :progression
  def event_type(type_id) when type_id in @mount_types, do: :mount
  def event_type(_), do: nil

  @doc """
  Check if achievement type uses objectId as the specific target.

  These achievement types track a specific object (creature, quest, datacube, etc.)
  and should be indexed by that object ID for O(1) lookup.

  ## Examples

      iex> AchievementTypes.uses_object_id?(2)
      true

      iex> AchievementTypes.uses_object_id?(61)
      false
  """
  @spec uses_object_id?(non_neg_integer()) :: boolean()
  def uses_object_id?(type_id) do
    type_id in ((@kill_types -- [61, 105]) ++
                  @quest_types ++
                  @datacube_types ++
                  @housing_types ++
                  @adventure_types ++
                  [37, 42, 46, 82])
  end

  @doc """
  Check if achievement type uses value as a counter target.

  These achievement types count occurrences (kill X creatures, complete X quests)
  and should be indexed with :any target for counter-based tracking.

  ## Examples

      iex> AchievementTypes.uses_counter?(61)
      true

      iex> AchievementTypes.uses_counter?(2)
      false
  """
  @spec uses_counter?(non_neg_integer()) :: boolean()
  def uses_counter?(type_id) do
    type_id in [61, 77, 87, 88, 94, 102, 33, 76, 3, 13, 105]
  end

  @doc """
  Get all type IDs for a given event type.

  ## Examples

      iex> AchievementTypes.types_for_event(:kill)
      [2, 61, 105]
  """
  @spec types_for_event(atom()) :: [non_neg_integer()]
  def types_for_event(:kill), do: @kill_types
  def types_for_event(:quest_complete), do: @quest_types
  def types_for_event(:zone_explore), do: @zone_types
  def types_for_event(:dungeon_complete), do: @dungeon_types
  def types_for_event(:path_mission), do: @path_types
  def types_for_event(:tradeskill), do: @tradeskill_types
  def types_for_event(:challenge_complete), do: @challenge_types
  def types_for_event(:pvp), do: @pvp_types
  def types_for_event(:datacube), do: @datacube_types
  def types_for_event(:event), do: @event_types
  def types_for_event(:social), do: @social_types
  def types_for_event(:housing), do: @housing_types
  def types_for_event(:adventure_complete), do: @adventure_types
  def types_for_event(:meta), do: @meta_types
  def types_for_event(:progression), do: @progression_types
  def types_for_event(:mount), do: @mount_types
  def types_for_event(_), do: []

  @doc """
  Get all supported event types.
  """
  @spec all_event_types() :: [atom()]
  def all_event_types do
    [
      :kill,
      :quest_complete,
      :zone_explore,
      :dungeon_complete,
      :path_mission,
      :tradeskill,
      :challenge_complete,
      :pvp,
      :datacube,
      :event,
      :social,
      :housing,
      :adventure_complete,
      :meta,
      :progression,
      :mount
    ]
  end

  @doc """
  Get point value for achievement point enum.

  WildStar achievements have point values 0-3 mapped to actual points.
  """
  @spec points_for_enum(non_neg_integer()) :: non_neg_integer()
  def points_for_enum(0), do: 0
  def points_for_enum(1), do: 5
  def points_for_enum(2), do: 10
  def points_for_enum(3), do: 25
  def points_for_enum(_), do: 0
end
