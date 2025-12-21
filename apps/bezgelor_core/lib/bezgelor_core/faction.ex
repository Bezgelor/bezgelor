defmodule BezgelorCore.Faction do
  @moduledoc """
  Faction relationship system for WildStar.

  WildStar has two main player factions (Exile and Dominion) plus
  creature factions that determine hostility.

  ## Faction Types

  - `:exile` - Exile player faction
  - `:dominion` - Dominion player faction
  - `:hostile` - Hostile to all players
  - `:neutral` - Neutral to all (won't aggro)
  - `:friendly` - Friendly to all players
  """

  @type faction :: :exile | :dominion | :hostile | :neutral | :friendly

  # Known faction IDs from WildStar data
  @exile_faction_id 166
  @dominion_faction_id 167

  # Hostile creature factions (IDs that are hostile to players)
  @hostile_faction_ids [281, 282, 283, 284, 285]

  @doc """
  Check if two factions are hostile to each other.
  """
  @spec hostile?(faction(), faction()) :: boolean()
  def hostile?(:hostile, _target), do: true
  def hostile?(_source, :hostile), do: true
  def hostile?(:neutral, _target), do: false
  def hostile?(_source, :neutral), do: false
  def hostile?(:friendly, _target), do: false
  def hostile?(_source, :friendly), do: false
  def hostile?(:exile, :dominion), do: true
  def hostile?(:dominion, :exile), do: true
  def hostile?(same, same), do: false
  def hostile?(_, _), do: false

  @doc """
  Convert a faction ID to faction atom.
  """
  @spec faction_from_id(non_neg_integer()) :: faction()
  def faction_from_id(@exile_faction_id), do: :exile
  def faction_from_id(@dominion_faction_id), do: :dominion
  def faction_from_id(id) when id in @hostile_faction_ids, do: :hostile
  def faction_from_id(0), do: :neutral
  def faction_from_id(_), do: :neutral

  @doc """
  Check if a creature faction ID is hostile to a player faction.
  """
  @spec creature_hostile_to_player?(non_neg_integer(), faction()) :: boolean()
  def creature_hostile_to_player?(creature_faction_id, player_faction) do
    creature_faction = faction_from_id(creature_faction_id)
    hostile?(creature_faction, player_faction)
  end
end
