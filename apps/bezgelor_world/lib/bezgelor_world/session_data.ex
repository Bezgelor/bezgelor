defmodule BezgelorWorld.SessionData do
  @moduledoc """
  Consistent accessors for session_data to prevent access pattern bugs.

  Session data is stored in `state.session_data` during a player's connection.
  This module provides helper functions to access common fields with proper
  defaults, avoiding bugs where code reads from the wrong location.

  ## Why This Exists

  Position is stored in `session_data[:entity].position` (updated by MovementHandler),
  but code sometimes incorrectly reads from `session_data[:position]`. This module
  encapsulates the correct access patterns.

  ## Usage

      alias BezgelorWorld.SessionData

      # In a handler:
      position = SessionData.get_position(state.session_data)
      {position, yaw} = SessionData.get_position_and_yaw(state.session_data)
      world_key = SessionData.get_world_key(state.session_data)
  """

  @type session_data :: map()
  @type position :: {float(), float(), float()}

  @doc """
  Get the player's current position from the entity.

  Returns `{0.0, 0.0, 0.0}` if entity is not set.
  """
  @spec get_position(session_data()) :: position()
  def get_position(session_data) do
    entity = session_data[:entity]
    if entity, do: entity.position, else: {0.0, 0.0, 0.0}
  end

  @doc """
  Get the player's current yaw (facing direction) from the entity.

  The yaw is the first element of the rotation tuple {yaw, pitch, roll}.
  Returns `0.0` if entity is not set.
  """
  @spec get_yaw(session_data()) :: float()
  def get_yaw(session_data) do
    entity = session_data[:entity]

    if entity do
      case entity.rotation do
        {yaw, _, _} -> yaw
        _ -> 0.0
      end
    else
      0.0
    end
  end

  @doc """
  Get both position and yaw in one call.

  The yaw is the first element of the rotation tuple {yaw, pitch, roll}.
  Returns `{{x, y, z}, yaw}`.
  """
  @spec get_position_and_yaw(session_data()) :: {position(), float()}
  def get_position_and_yaw(session_data) do
    entity = session_data[:entity]

    if entity do
      yaw =
        case entity.rotation do
          {y, _, _} -> y
          _ -> 0.0
        end

      {entity.position, yaw}
    else
      {{0.0, 0.0, 0.0}, 0.0}
    end
  end

  @doc """
  Get the entity struct.

  Returns `nil` if not set.
  """
  @spec get_entity(session_data()) :: struct() | nil
  def get_entity(session_data) do
    session_data[:entity]
  end

  @doc """
  Get the player's entity GUID.

  Returns `nil` if not set.
  """
  @spec get_entity_guid(session_data()) :: non_neg_integer() | nil
  def get_entity_guid(session_data) do
    session_data[:entity_guid]
  end

  @doc """
  Get the world key tuple `{world_id, instance_id}` for World.Instance calls.

  Defaults to `{1, 1}` if world_id is not set.
  """
  @spec get_world_key(session_data()) :: {non_neg_integer(), non_neg_integer()}
  def get_world_key(session_data) do
    world_id = session_data[:world_id] || 1
    instance_id = session_data[:zone_instance_id] || 1
    {world_id, instance_id}
  end

  @doc """
  Get the current world ID.

  Defaults to `1` if not set.
  """
  @spec get_world_id(session_data()) :: non_neg_integer()
  def get_world_id(session_data) do
    session_data[:world_id] || 1
  end

  @doc """
  Get the current zone ID.

  Defaults to `1` if not set.
  """
  @spec get_zone_id(session_data()) :: non_neg_integer()
  def get_zone_id(session_data) do
    session_data[:zone_id] || 1
  end

  @doc """
  Get the character struct.

  Returns `nil` if not set.
  """
  @spec get_character(session_data()) :: struct() | nil
  def get_character(session_data) do
    session_data[:character]
  end

  @doc """
  Get the player's current target GUID.

  Returns `nil` if no target is selected.
  """
  @spec get_target_guid(session_data()) :: non_neg_integer() | nil
  def get_target_guid(session_data) do
    session_data[:target_guid]
  end

  @doc """
  Check if the player is currently in the world.

  Returns `false` if not set.
  """
  @spec in_world?(session_data()) :: boolean()
  def in_world?(session_data) do
    session_data[:in_world] == true
  end
end
