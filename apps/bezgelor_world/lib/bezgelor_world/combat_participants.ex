defmodule BezgelorWorld.CombatParticipants do
  @moduledoc """
  Resolves combat participants for quest credit distribution.

  ## Overview

  When a creature dies, all participants who contributed to the kill
  should receive quest credit. This module converts entity GUIDs from
  the AI threat/participants list to character IDs that the quest system
  can use.

  ## Participant Resolution

  Currently supports:
  - Direct combatants (players who dealt damage)

  Future support planned for:
  - Group/party members in range who didn't deal damage directly
  - Raid members for raid boss kills

  ## Usage

      # Get character IDs for all participants
      character_ids = CombatParticipants.resolve(creature_ai, zone_id, instance_id)

      # Notify all participants of the kill
      for char_id <- character_ids do
        CombatBroadcaster.notify_creature_kill(zone_id, instance_id, char_id, creature_id)
      end
  """

  alias BezgelorCore.AI
  alias BezgelorWorld.WorldManager

  require Logger

  @doc """
  Resolve all character IDs that should receive credit for a creature kill.

  Takes the creature's AI state and returns a list of character IDs that
  participated in the combat.

  ## Parameters

  - `ai` - The creature's AI state (contains combat_participants)
  - `zone_id` - Zone ID where the combat occurred
  - `instance_id` - Instance ID where the combat occurred

  ## Returns

  List of character IDs that should receive kill credit.
  """
  @spec resolve(AI.t(), non_neg_integer(), non_neg_integer()) :: [non_neg_integer()]
  def resolve(ai, _zone_id, _instance_id) do
    # Get entity GUIDs of direct combatants
    participant_guids = AI.get_combat_participants(ai)

    # Convert entity GUIDs to character IDs
    character_ids =
      participant_guids
      |> Enum.map(&entity_guid_to_character_id/1)
      |> Enum.reject(&is_nil/1)

    # TODO: Add group member support when party system is implemented
    # For each character_id, check if they're in a group:
    #   - If in a group, add all group members who are in the same zone/instance
    #   - Only add group members within a reasonable range (e.g., 100m)
    #
    # Example future implementation:
    # character_ids = add_group_members(character_ids, zone_id, instance_id)

    character_ids
    |> Enum.uniq()
  end

  @doc """
  Resolve participants and include group members within range.

  This function extends the basic participant list to include group members
  who may not have dealt damage but should still receive credit.

  ## Parameters

  - `ai` - The creature's AI state
  - `zone_id` - Zone ID where the combat occurred
  - `instance_id` - Instance ID where the combat occurred
  - `creature_position` - Position of the creature (for range checks)
  - `credit_range` - Maximum distance for group credit (default: 100.0)

  ## Returns

  List of character IDs including group members within range.
  """
  @spec resolve_with_groups(AI.t(), non_neg_integer(), non_neg_integer(), {float(), float(), float()}, float()) ::
          [non_neg_integer()]
  def resolve_with_groups(ai, zone_id, instance_id, _creature_position, _credit_range \\ 100.0) do
    # Start with direct participants
    base_participants = resolve(ai, zone_id, instance_id)

    # Add group members for each participant
    # TODO: Implement when group system is available
    # For now, just return base participants
    base_participants
  end

  # Private helpers

  defp entity_guid_to_character_id(entity_guid) do
    case WorldManager.get_session_by_entity_guid(entity_guid) do
      nil ->
        Logger.debug("No session found for entity GUID #{entity_guid}")
        nil

      session ->
        session.character_id
    end
  end

  # Future: Add group members who didn't deal damage
  # defp add_group_members(character_ids, zone_id, instance_id) do
  #   # For each character, get their group
  #   # For each group member, check if they're in the same zone/instance
  #   # Add them to the list if within range
  #   character_ids
  # end
end
