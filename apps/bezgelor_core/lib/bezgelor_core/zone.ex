defmodule BezgelorCore.Zone do
  @moduledoc """
  Zone data and spawn points.

  For Phase 6, we use hardcoded default zones.
  Static game data loading is a future enhancement.

  ## Factions

  - 166: Dominion
  - 167: Exile

  ## CharacterCreationStart Values

  - 0: Arkship
  - 1: Demo01
  - 2: Demo02
  - 3: Nexus (Veteran)
  - 4: PreTutorial (Novice) - cryopod awakening tutorial
  - 5: Level50

  ## Default Spawn Locations

  New characters spawn based on their CharacterCreationStart type and faction:

  - Novice/Arkship (0, 4): Faction-specific tutorial arkship
    - Exile: World 1634 (Gambler's Ruin), Zone 4844 (Cryo Awakening Protocol)
    - Dominion: World 1537 (Destiny), Zone 4813 (Cryo Awakening Protocol)
  - Veteran (3): Faction-specific Nexus starting zone
  - Level 50 (5): Faction capital city (Thayd/Illium)

  Existing characters spawn at their last saved position.
  """

  @type spawn_location :: %{
          world_id: non_neg_integer(),
          zone_id: non_neg_integer(),
          position: {float(), float(), float()},
          rotation: {float(), float(), float()}
        }

  # CharacterCreationStart enum values (from NexusForever)
  @creation_start_arkship 0
  @creation_start_demo01 1
  @creation_start_demo02 2
  @creation_start_nexus 3
  @creation_start_pretutorial 4
  @creation_start_level50 5

  # Novice tutorial arkship spawns (PreTutorial = 4)
  # These are the cryopod awakening tutorial instances where players
  # wake up from cryosleep and begin the game

  # Exile tutorial: Gambler's Ruin - Cryo Awakening Protocol
  # World 1634, Zone 4844 - Location 50231
  @exile_tutorial_start %{
    world_id: 1634,
    zone_id: 4844,
    position: {4088.164551, -7.53978, -3.654721},
    rotation: {0.0, 0.0, 0.0}
  }

  # Dominion tutorial: Destiny - Cryo Awakening Protocol
  # World 1537, Zone 4813 - Location 50230
  @dominion_tutorial_start %{
    world_id: 1537,
    zone_id: 4813,
    position: {4605.650391, -7.57124, 494.995911},
    rotation: {0.0, 0.0, 0.0}
  }

  # Exile starting zone on Nexus (Veteran/Nexus = 3)
  @exile_nexus_start %{
    world_id: 426,
    zone_id: 1,
    position: {4110.71, -658.6249, -5145.48},
    rotation: {0.317613, 0.0, 0.0}
  }

  # Dominion starting zone on Nexus (Veteran/Nexus = 3)
  @dominion_nexus_start %{
    world_id: 1387,
    zone_id: 2,
    position: {-3835.341, -980.2174, -6050.524},
    rotation: {-0.45682, 0.0, 0.0}
  }

  # Exile Level 50 start (Thayd)
  @exile_level50_start %{
    world_id: 51,
    zone_id: 1,
    position: {4074.34, -797.8368, -2399.37},
    rotation: {0.0, 0.0, 0.0}
  }

  # Dominion Level 50 start (Illium)
  @dominion_level50_start %{
    world_id: 22,
    zone_id: 2,
    position: {-3343.58, -887.4646, -536.03},
    rotation: {-0.7632219, 0.0, 0.0}
  }

  # Faction IDs (matches NexusForever Faction.cs)
  @faction_dominion 166
  @faction_exile 167

  @doc """
  Get starting location for a new character based on creation type and faction.

  ## CharacterCreationStart Types

  - 4 (PreTutorial/Novice): Faction-specific tutorial arkship cryopod awakening
  - 3 (Nexus/Veteran): Open world on Nexus
  - 5 (Level50): Capital city (Thayd/Illium)

  ## Examples

      iex> Zone.starting_location(4, 167)  # Novice Exile
      %{world_id: 1634, zone_id: 4844, position: {4088.164551, -7.53978, -3.654721}, rotation: {0.0, 0.0, 0.0}}

      iex> Zone.starting_location(4, 166)  # Novice Dominion
      %{world_id: 1537, zone_id: 4813, position: {4605.650391, -7.57124, 494.995911}, rotation: {0.0, 0.0, 0.0}}
  """
  @spec starting_location(non_neg_integer(), non_neg_integer()) :: spawn_location()
  def starting_location(creation_start, faction_id)

  # PreTutorial (Novice = 4) - Faction-specific tutorial arkship cryopod awakening
  def starting_location(@creation_start_pretutorial, @faction_exile), do: @exile_tutorial_start
  def starting_location(@creation_start_pretutorial, @faction_dominion), do: @dominion_tutorial_start
  # Fallback for PreTutorial with unknown faction - use Exile arkship
  def starting_location(@creation_start_pretutorial, _faction_id), do: @exile_tutorial_start

  # Arkship (0) - Same as PreTutorial (faction-specific)
  def starting_location(@creation_start_arkship, @faction_exile), do: @exile_tutorial_start
  def starting_location(@creation_start_arkship, @faction_dominion), do: @dominion_tutorial_start
  def starting_location(@creation_start_arkship, _faction_id), do: @exile_tutorial_start

  # Nexus/Veteran (3) - Faction-specific starting zone on Nexus
  def starting_location(@creation_start_nexus, @faction_exile), do: @exile_nexus_start
  def starting_location(@creation_start_nexus, @faction_dominion), do: @dominion_nexus_start

  # Level50 (5) - Faction capital city
  def starting_location(@creation_start_level50, @faction_exile), do: @exile_level50_start
  def starting_location(@creation_start_level50, @faction_dominion), do: @dominion_level50_start

  # Demo modes (1, 2) - Use faction-specific tutorial
  def starting_location(@creation_start_demo01, @faction_exile), do: @exile_tutorial_start
  def starting_location(@creation_start_demo01, @faction_dominion), do: @dominion_tutorial_start
  def starting_location(@creation_start_demo01, _faction_id), do: @exile_tutorial_start

  def starting_location(@creation_start_demo02, @faction_exile), do: @exile_tutorial_start
  def starting_location(@creation_start_demo02, @faction_dominion), do: @dominion_tutorial_start
  def starting_location(@creation_start_demo02, _faction_id), do: @exile_tutorial_start

  # Fallback - Use faction-specific tutorial arkship
  def starting_location(_creation_start, @faction_exile), do: @exile_tutorial_start
  def starting_location(_creation_start, @faction_dominion), do: @dominion_tutorial_start
  def starting_location(_creation_start, _faction_id), do: @exile_tutorial_start

  @doc """
  Get default spawn location for a faction (legacy function).

  For new characters, use `starting_location/2` instead.

  ## Examples

      iex> Zone.default_spawn(166)
      %{world_id: 1387, zone_id: 2, position: {-3835.341, -980.2174, -6050.524}, rotation: {-0.45682, 0.0, 0.0}}

      iex> Zone.default_spawn(167)
      %{world_id: 426, zone_id: 1, position: {4110.71, -658.6249, -5145.48}, rotation: {0.317613, 0.0, 0.0}}
  """
  @spec default_spawn(non_neg_integer()) :: spawn_location()
  def default_spawn(@faction_exile), do: @exile_nexus_start
  def default_spawn(@faction_dominion), do: @dominion_nexus_start
  def default_spawn(_), do: @exile_nexus_start

  @doc """
  Get spawn location for a character.

  Returns the character's saved position if valid, otherwise
  returns the default spawn for their faction.

  ## Examples

      iex> character = %{world_id: 100, world_zone_id: 5, location_x: 1.0, location_y: 2.0, location_z: 3.0, rotation_x: 0.0, rotation_y: 0.0, rotation_z: 0.0, faction_id: 167}
      iex> Zone.spawn_location(character)
      %{world_id: 100, zone_id: 5, position: {1.0, 2.0, 3.0}, rotation: {0.0, 0.0, 0.0}}
  """
  @spec spawn_location(map()) :: spawn_location()
  def spawn_location(character) do
    if valid_position?(character) do
      %{
        world_id: character.world_id,
        zone_id: character.world_zone_id,
        position: {
          character.location_x || 0.0,
          character.location_y || 0.0,
          character.location_z || 0.0
        },
        rotation: {
          character.rotation_x || 0.0,
          character.rotation_y || 0.0,
          character.rotation_z || 0.0
        }
      }
    else
      default_spawn(character.faction_id)
    end
  end

  @doc """
  Check if a character has a valid saved position.
  """
  @spec valid_position?(map()) :: boolean()
  def valid_position?(character) do
    character.world_id != nil and character.world_id > 0
  end

  @doc """
  Get the Exile faction ID.
  """
  @spec exile_faction_id() :: non_neg_integer()
  def exile_faction_id, do: @faction_exile

  @doc """
  Get the Dominion faction ID.
  """
  @spec dominion_faction_id() :: non_neg_integer()
  def dominion_faction_id, do: @faction_dominion
end
