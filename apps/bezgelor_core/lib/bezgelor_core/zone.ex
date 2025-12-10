defmodule BezgelorCore.Zone do
  @moduledoc """
  Zone data and spawn points.

  For Phase 6, we use hardcoded default zones.
  Static game data loading is a future enhancement.

  ## Factions

  - 166: Exile
  - 167: Dominion

  ## Default Spawn Locations

  New characters spawn in their faction's starting area.
  Existing characters spawn at their last saved position.
  """

  @type spawn_location :: %{
          world_id: non_neg_integer(),
          zone_id: non_neg_integer(),
          position: {float(), float(), float()},
          rotation: {float(), float(), float()}
        }

  # Exile starting zone (Everstar Grove)
  @exile_start %{
    world_id: 870,
    zone_id: 1,
    position: {-3200.0, -800.0, -580.0},
    rotation: {0.0, 0.0, 0.0}
  }

  # Dominion starting zone (Levian Bay)
  @dominion_start %{
    world_id: 870,
    zone_id: 2,
    position: {-3200.0, -800.0, -580.0},
    rotation: {0.0, 0.0, 0.0}
  }

  # Faction IDs
  @faction_exile 166
  @faction_dominion 167

  @doc """
  Get default spawn location for a faction.

  ## Examples

      iex> Zone.default_spawn(166)
      %{world_id: 870, zone_id: 1, position: {-3200.0, -800.0, -580.0}, rotation: {0.0, 0.0, 0.0}}

      iex> Zone.default_spawn(167)
      %{world_id: 870, zone_id: 2, position: {-3200.0, -800.0, -580.0}, rotation: {0.0, 0.0, 0.0}}
  """
  @spec default_spawn(non_neg_integer()) :: spawn_location()
  def default_spawn(@faction_exile), do: @exile_start
  def default_spawn(@faction_dominion), do: @dominion_start
  def default_spawn(_), do: @exile_start

  @doc """
  Get spawn location for a character.

  Returns the character's saved position if valid, otherwise
  returns the default spawn for their faction.

  ## Examples

      iex> character = %{world_id: 100, world_zone_id: 5, location_x: 1.0, location_y: 2.0, location_z: 3.0, rotation_x: 0.0, rotation_y: 0.0, rotation_z: 0.0, faction_id: 166}
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
