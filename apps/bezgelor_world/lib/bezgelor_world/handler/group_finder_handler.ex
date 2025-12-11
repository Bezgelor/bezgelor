defmodule BezgelorWorld.Handler.GroupFinderHandler do
  @moduledoc """
  Handles group finder related packets.

  ## Queue Flow

  1. Player sends ClientGroupFinderJoin to queue
  2. Server adds player to queue, sends ServerGroupFinderQueued
  3. Matcher finds a match, server sends ServerGroupFinderMatch to all
  4. Players accept/decline via ClientGroupFinderResponse
  5. If all accept, server creates instance, sends ServerGroupFinderResult

  ## Supported Content Types

  - :dungeon - 5-player dungeons
  - :adventure - 5-player adventures
  - :raid - 20-player raids
  - :expedition - 5-player flexible composition
  """

  require Logger

  alias BezgelorWorld.GroupFinder.GroupFinder
  alias BezgelorProtocol.Packets.World.{
    ServerGroupFinderQueued,
    ServerGroupFinderUpdate,
    ServerGroupFinderResult
  }

  @doc """
  Handles player joining the group finder queue.
  """
  def handle_join(packet, state) do
    character_id = state.session_data[:character_id]

    if character_id do
      entry = %{
        character_id: character_id,
        roles: packet.roles,
        instance_type: packet.instance_type,
        difficulty: packet.difficulty,
        instance_ids: packet.instance_ids || [],
        gear_score: state.session_data[:gear_score] || 0,
        language: state.session_data[:language] || "en"
      }

      case GroupFinder.join_queue(entry) do
        {:ok, position} ->
          Logger.info("Player #{character_id} joined queue for #{packet.instance_type}:#{packet.difficulty}")

          response = %ServerGroupFinderQueued{
            instance_type: packet.instance_type,
            difficulty: packet.difficulty,
            roles: packet.roles,
            queue_position: position,
            estimated_wait: estimate_wait_time(packet.instance_type, packet.roles)
          }

          {:ok, [response], state}

        {:error, :already_queued} ->
          Logger.debug("Player #{character_id} already in queue")

          response = %ServerGroupFinderResult{
            result: :error,
            error_code: :already_queued
          }

          {:ok, [response], state}

        {:error, reason} ->
          Logger.warning("Failed to join queue: #{inspect(reason)}")

          response = %ServerGroupFinderResult{
            result: :error,
            error_code: :queue_error
          }

          {:ok, [response], state}
      end
    else
      {:ok, [], state}
    end
  end

  @doc """
  Handles player leaving the group finder queue.
  """
  def handle_leave(_packet, state) do
    character_id = state.session_data[:character_id]

    if character_id do
      case GroupFinder.leave_queue(character_id) do
        :ok ->
          Logger.info("Player #{character_id} left queue")

          response = %ServerGroupFinderUpdate{
            update_type: :left_queue
          }

          {:ok, [response], state}

        {:error, :not_queued} ->
          {:ok, [], state}
      end
    else
      {:ok, [], state}
    end
  end

  @doc """
  Handles player response to a match (accept/decline).
  """
  def handle_response(packet, state) do
    character_id = state.session_data[:character_id]

    if character_id do
      case GroupFinder.respond_to_match(packet.match_id, character_id, packet.accepted) do
        :ok ->
          Logger.info("Player #{character_id} #{if packet.accepted, do: "accepted", else: "declined"} match #{packet.match_id}")
          {:ok, [], state}

        {:error, :match_not_found} ->
          Logger.debug("Match #{packet.match_id} not found for player #{character_id}")
          {:ok, [], state}

        {:error, reason} ->
          Logger.warning("Match response error: #{inspect(reason)}")
          {:ok, [], state}
      end
    else
      {:ok, [], state}
    end
  end

  @doc """
  Handles request to check queue status.
  """
  def handle_status(_packet, state) do
    character_id = state.session_data[:character_id]

    if character_id do
      case GroupFinder.get_queue_status(character_id) do
        {:ok, info} ->
          response = %ServerGroupFinderUpdate{
            update_type: :status,
            instance_type: info.instance_type,
            difficulty: info.difficulty,
            queue_position: info.position,
            estimated_wait: info.estimated_wait
          }

          {:ok, [response], state}

        {:error, :not_queued} ->
          response = %ServerGroupFinderUpdate{
            update_type: :not_queued
          }

          {:ok, [response], state}
      end
    else
      {:ok, [], state}
    end
  end

  # Estimate wait time based on content type and roles
  defp estimate_wait_time(instance_type, roles) do
    base_time = case instance_type do
      :dungeon -> 300      # 5 minutes
      :adventure -> 300    # 5 minutes
      :raid -> 900         # 15 minutes
      :expedition -> 180   # 3 minutes
      _ -> 300
    end

    # Tanks and healers get shorter queues
    role_modifier = cond do
      :tank in roles -> 0.2
      :healer in roles -> 0.4
      true -> 1.0
    end

    round(base_time * role_modifier)
  end
end
