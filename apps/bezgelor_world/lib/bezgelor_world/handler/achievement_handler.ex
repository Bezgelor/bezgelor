defmodule BezgelorWorld.Handler.AchievementHandler do
  @moduledoc """
  Handles achievement events and client notifications.

  ## Real-Time Processing

  This handler subscribes to PubSub events for the character and
  processes achievement criteria in real-time. When an achievement
  is completed, the client is immediately notified.

  ## Usage

  Start the handler when a character logs in:

      AchievementHandler.start_link(connection_pid, character_id)

  Events are processed automatically via PubSub subscription.
  """

  use GenServer

  alias BezgelorDb.Achievements
  alias BezgelorProtocol.Packets.World.{
    ServerAchievementList,
    ServerAchievementUpdate,
    ServerAchievementEarned
  }

  alias BezgelorWorld.Handler.TitleHandler

  require Logger

  defstruct [:connection_pid, :character_id, :account_id, :achievement_defs]

  @doc "Start achievement handler for a character."
  def start_link(connection_pid, character_id, opts \\ []) do
    account_id = Keyword.get(opts, :account_id)
    achievement_defs = Keyword.get(opts, :achievement_defs, %{})
    GenServer.start_link(__MODULE__, {connection_pid, character_id, account_id, achievement_defs})
  end

  @doc "Send full achievement list to client."
  @spec send_achievement_list(pid(), integer()) :: :ok
  def send_achievement_list(connection_pid, character_id) do
    achievements = Achievements.get_achievements(character_id)
    total_points = Achievements.total_points(character_id)

    packet = %ServerAchievementList{
      total_points: total_points,
      achievements: achievements
    }

    send(connection_pid, {:send_packet, packet})
    :ok
  end

  @doc "Manually trigger an achievement check (for non-event achievements)."
  def check_achievement(handler_pid, achievement_id) do
    GenServer.cast(handler_pid, {:check_achievement, achievement_id})
  end

  # GenServer Callbacks

  @impl true
  def init({connection_pid, character_id, account_id, achievement_defs}) do
    # Subscribe to achievement events
    :ok = Achievements.subscribe(character_id)

    state = %__MODULE__{
      connection_pid: connection_pid,
      character_id: character_id,
      account_id: account_id,
      achievement_defs: achievement_defs
    }

    Logger.debug("AchievementHandler started for character #{character_id}")
    {:ok, state}
  end

  @impl true
  def handle_info({:achievement_event, event}, state) do
    process_event(event, state)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:check_achievement, achievement_id}, state) do
    case Map.get(state.achievement_defs, achievement_id) do
      nil ->
        :ok

      def_data ->
        check_and_update(state, achievement_id, def_data)
    end

    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    Achievements.unsubscribe(state.character_id)
    :ok
  end

  # Event Processing

  defp process_event({:kill, creature_id}, state) do
    # Find achievements tracking this creature kill
    process_kill_achievements(state, creature_id)
  end

  defp process_event({:quest_complete, quest_id}, state) do
    # Find achievements tracking quest completion
    process_quest_achievements(state, quest_id)
  end

  defp process_event({:item_collect, item_id, count}, state) do
    # Find achievements tracking item collection
    process_item_achievements(state, item_id, count)
  end

  defp process_event({:level_up, new_level}, state) do
    # Find achievements for reaching levels
    process_level_achievements(state, new_level)
  end

  defp process_event({:achievement, completed_id}, state) do
    # Meta achievements - check if completing this unlocks others
    process_meta_achievements(state, completed_id)
  end

  defp process_event(_event, _state), do: :ok

  # Achievement Type Processors

  defp process_kill_achievements(state, creature_id) do
    # Find all kill achievements for this creature in definitions
    state.achievement_defs
    |> Enum.filter(fn {_id, def} ->
      def[:type] == :kill and def[:creature_id] == creature_id
    end)
    |> Enum.each(fn {achievement_id, def} ->
      target = def[:target] || 1
      points = def[:points] || 10

      case Achievements.increment_progress(
             state.character_id,
             achievement_id,
             1,
             target,
             points
           ) do
        {:ok, ach, :completed} ->
          send_earned(state, ach)

        {:ok, ach, :progress} ->
          send_update(state.connection_pid, ach)

        _ ->
          :ok
      end
    end)
  end

  defp process_quest_achievements(state, quest_id) do
    state.achievement_defs
    |> Enum.filter(fn {_id, def} ->
      def[:type] == :quest and def[:quest_id] == quest_id
    end)
    |> Enum.each(fn {achievement_id, def} ->
      points = def[:points] || 10

      case Achievements.complete(state.character_id, achievement_id, points) do
        {:ok, ach, :completed} ->
          send_earned(state, ach)

        _ ->
          :ok
      end
    end)
  end

  defp process_item_achievements(state, item_id, count) do
    state.achievement_defs
    |> Enum.filter(fn {_id, def} ->
      def[:type] == :item and def[:item_id] == item_id
    end)
    |> Enum.each(fn {achievement_id, def} ->
      target = def[:target] || 1
      points = def[:points] || 10

      case Achievements.increment_progress(
             state.character_id,
             achievement_id,
             count,
             target,
             points
           ) do
        {:ok, ach, :completed} ->
          send_earned(state, ach)

        {:ok, ach, :progress} ->
          send_update(state.connection_pid, ach)

        _ ->
          :ok
      end
    end)
  end

  defp process_level_achievements(state, new_level) do
    state.achievement_defs
    |> Enum.filter(fn {_id, def} ->
      def[:type] == :level and def[:level] <= new_level
    end)
    |> Enum.each(fn {achievement_id, def} ->
      points = def[:points] || 10

      case Achievements.complete(state.character_id, achievement_id, points) do
        {:ok, ach, :completed} ->
          send_earned(state, ach)

        _ ->
          :ok
      end
    end)
  end

  defp process_meta_achievements(state, completed_achievement_id) do
    state.achievement_defs
    |> Enum.filter(fn {_id, def} ->
      def[:type] == :meta and completed_achievement_id in (def[:required_achievements] || [])
    end)
    |> Enum.each(fn {achievement_id, def} ->
      required = def[:required_achievements] || []
      points = def[:points] || 25

      all_complete =
        Enum.all?(required, fn req_id ->
          Achievements.completed?(state.character_id, req_id)
        end)

      if all_complete do
        case Achievements.complete(state.character_id, achievement_id, points) do
          {:ok, ach, :completed} ->
            send_earned(state, ach)

          _ ->
            :ok
        end
      end
    end)
  end

  defp check_and_update(state, achievement_id, def_data) do
    target = def_data[:target] || 1
    points = def_data[:points] || 10

    case Achievements.get_achievement(state.character_id, achievement_id) do
      nil ->
        :ok

      ach ->
        if not ach.completed and ach.progress >= target do
          case Achievements.complete(state.character_id, achievement_id, points) do
            {:ok, updated, :completed} ->
              send_earned(state, updated)

            _ ->
              :ok
          end
        end
    end
  end

  # Packet Sending

  defp send_update(connection_pid, achievement) do
    packet = %ServerAchievementUpdate{
      achievement_id: achievement.achievement_id,
      progress: achievement.progress
    }

    send(connection_pid, {:send_packet, packet})
  end

  defp send_earned(state, achievement) do
    packet = %ServerAchievementEarned{
      achievement_id: achievement.achievement_id,
      points: achievement.points_awarded,
      completed_at: achievement.completed_at
    }

    send(state.connection_pid, {:send_packet, packet})

    Logger.info("Achievement #{achievement.achievement_id} earned! (#{achievement.points_awarded} points)")

    # Check for title unlocks (titles are account-wide)
    if state.account_id do
      TitleHandler.check_achievement_titles(
        state.connection_pid,
        state.account_id,
        achievement.achievement_id
      )
    end
  end
end
