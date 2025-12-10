defmodule BezgelorWorld.Handler.PathHandler do
  @moduledoc """
  Handles path missions and progression.

  ## Path Types

  - Soldier (0): Combat-focused, holdouts, assassination
  - Settler (1): Building depots, buffing areas
  - Scientist (2): Scanning, lore discovery
  - Explorer (3): Exploration, jumping puzzles, cartography

  ## Usage

      # Send full path data on login
      PathHandler.send_path_data(connection_pid, character_id)

      # Award XP from mission completion
      PathHandler.award_xp(connection_pid, character_id, 250)

      # Update mission progress
      PathHandler.update_mission(connection_pid, character_id, mission_id, %{"kills" => 5})
  """

  alias BezgelorDb.Paths
  alias BezgelorProtocol.Packets.World.{
    ServerPathData,
    ServerPathXp,
    ServerPathLevelUp,
    ServerPathMissionUpdate,
    ServerPathMissionComplete
  }

  require Logger

  @doc "Send full path data to client."
  @spec send_path_data(pid(), integer()) :: :ok
  def send_path_data(connection_pid, character_id) do
    case Paths.get_path(character_id) do
      nil ->
        Logger.debug("No path initialized for character #{character_id}")
        :ok

      path ->
        missions = Paths.get_active_missions(character_id)

        packet = %ServerPathData{
          path_type: path.path_type,
          path_level: path.path_level,
          path_xp: path.path_xp,
          unlocked_abilities: path.unlocked_abilities,
          missions: missions
        }

        send(connection_pid, {:send_packet, packet})
        :ok
    end
  end

  @doc "Award path XP and notify client."
  @spec award_xp(pid(), integer(), integer()) :: :ok | {:error, term()}
  def award_xp(connection_pid, character_id, xp_amount) do
    case Paths.award_xp(character_id, xp_amount) do
      {:ok, path, :level_up} ->
        # Send XP notification
        xp_packet = %ServerPathXp{
          xp_gained: xp_amount,
          total_xp: path.path_xp
        }

        send(connection_pid, {:send_packet, xp_packet})

        # Send level up notification
        level_packet = %ServerPathLevelUp{new_level: path.path_level}
        send(connection_pid, {:send_packet, level_packet})

        Logger.info("Path level up! Character #{character_id} is now level #{path.path_level}")
        :ok

      {:ok, path, :xp_gained} ->
        packet = %ServerPathXp{
          xp_gained: xp_amount,
          total_xp: path.path_xp
        }

        send(connection_pid, {:send_packet, packet})
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Accept a mission."
  @spec accept_mission(pid(), integer(), integer()) :: :ok | {:error, term()}
  def accept_mission(connection_pid, character_id, mission_id) do
    case Paths.accept_mission(character_id, mission_id) do
      {:ok, mission} ->
        packet = %ServerPathMissionUpdate{
          mission_id: mission_id,
          progress: mission.progress
        }

        send(connection_pid, {:send_packet, packet})
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Update mission progress."
  @spec update_mission(pid(), integer(), integer(), map()) :: :ok | {:error, term()}
  def update_mission(connection_pid, character_id, mission_id, progress_update) do
    case Paths.update_progress(character_id, mission_id, progress_update) do
      {:ok, mission} ->
        packet = %ServerPathMissionUpdate{
          mission_id: mission_id,
          progress: mission.progress
        }

        send(connection_pid, {:send_packet, packet})
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Increment a mission counter."
  @spec increment_mission_counter(pid(), integer(), integer(), String.t(), integer(), integer()) ::
          :ok | {:error, term()}
  def increment_mission_counter(
        connection_pid,
        character_id,
        mission_id,
        counter_key,
        amount \\ 1,
        target \\ nil
      ) do
    case Paths.increment_counter(character_id, mission_id, counter_key, amount, target) do
      {:ok, mission, _result} ->
        packet = %ServerPathMissionUpdate{
          mission_id: mission_id,
          progress: mission.progress
        }

        send(connection_pid, {:send_packet, packet})
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Complete a mission with XP reward."
  @spec complete_mission(pid(), integer(), integer(), integer()) :: :ok | {:error, term()}
  def complete_mission(connection_pid, character_id, mission_id, xp_reward \\ 100) do
    case Paths.complete_mission(character_id, mission_id) do
      {:ok, _mission} ->
        # Send completion notification
        complete_packet = %ServerPathMissionComplete{
          mission_id: mission_id,
          xp_reward: xp_reward
        }

        send(connection_pid, {:send_packet, complete_packet})

        # Award the XP
        award_xp(connection_pid, character_id, xp_reward)
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Abandon a mission."
  @spec abandon_mission(integer(), integer()) :: :ok | {:error, term()}
  def abandon_mission(character_id, mission_id) do
    Paths.abandon_mission(character_id, mission_id)
  end
end
