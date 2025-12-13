defmodule BezgelorWorld.Handler.AchievementHandler do
  @moduledoc """
  Handles achievement events and client notifications.

  ## Real-Time Processing

  This handler subscribes to PubSub events for the character and
  processes achievement criteria in real-time using an event-indexed
  lookup for O(1) achievement matching. When an achievement is
  completed, the client is immediately notified.

  ## Index-Based Lookup

  Achievement definitions are loaded into ETS at startup and indexed
  by event type and target. For example:
  - `{:kill, creature_id}` => [achievement defs]
  - `{:quest_complete, quest_id}` => [achievement defs]
  - `{:kill, :any}` => [counter achievements that track any kill]

  ## Supported Events

  - `{:kill, creature_id}` - Kill a specific creature or any creature
  - `{:quest_complete, quest_id}` - Complete a specific quest
  - `{:zone_explore, zone_id}` - Explore a zone
  - `{:dungeon_complete, instance_id}` - Complete a dungeon/raid
  - `{:path_mission, mission_id}` - Complete a path mission
  - `{:tradeskill, item_id}` - Craft or gather items
  - `{:challenge_complete, challenge_id}` - Complete a challenge
  - `{:pvp, action}` - PvP actions (kill, win, etc.)
  - `{:datacube, datacube_id}` - Discover a datacube
  - `{:level_up, new_level}` - Level up
  - `{:achievement, completed_id}` - Meta achievement trigger

  ## Usage

  Start the handler when a character logs in:

      AchievementHandler.start_link(connection_pid, character_id, account_id: account_id)

  Events are processed automatically via PubSub subscription.
  """

  use GenServer
  use Bitwise

  alias BezgelorData.{AchievementIndex, Store}
  alias BezgelorDb.Achievements

  alias BezgelorProtocol.Packets.World.{
    ServerAchievementList,
    ServerAchievementUpdate,
    ServerAchievementEarned
  }

  alias BezgelorWorld.Handler.TitleHandler

  require Logger

  defstruct [:connection_pid, :character_id, :account_id]

  @doc "Start achievement handler for a character."
  def start_link(connection_pid, character_id, opts \\ []) do
    account_id = Keyword.get(opts, :account_id)
    GenServer.start_link(__MODULE__, {connection_pid, character_id, account_id})
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
  def init({connection_pid, character_id, account_id}) do
    # Subscribe to achievement events
    :ok = Achievements.subscribe(character_id)

    state = %__MODULE__{
      connection_pid: connection_pid,
      character_id: character_id,
      account_id: account_id
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
    case Store.get_achievement(achievement_id) do
      {:ok, achievement} ->
        def_map = build_def_map_from_achievement(achievement)
        check_and_update(state, achievement_id, def_map)

      :error ->
        :ok
    end

    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    Achievements.unsubscribe(state.character_id)
    :ok
  end

  # Event Processing - Uses AchievementIndex for O(1) lookup

  defp process_event({:kill, creature_id}, state) do
    AchievementIndex.lookup(:kill, creature_id)
    |> Enum.each(fn def_map ->
      process_achievement(state, def_map, 1)
    end)
  end

  defp process_event({:quest_complete, quest_id}, state) do
    AchievementIndex.lookup(:quest_complete, quest_id)
    |> Enum.each(fn def_map ->
      process_achievement(state, def_map, 1)
    end)
  end

  defp process_event({:zone_explore, zone_id}, state) do
    AchievementIndex.lookup(:zone_explore, zone_id)
    |> Enum.each(fn def_map ->
      process_achievement(state, def_map, 1)
    end)
  end

  defp process_event({:dungeon_complete, instance_id}, state) do
    AchievementIndex.lookup(:dungeon_complete, instance_id)
    |> Enum.each(fn def_map ->
      process_achievement(state, def_map, 1)
    end)
  end

  defp process_event({:path_mission, mission_id}, state) do
    AchievementIndex.lookup(:path_mission, mission_id)
    |> Enum.each(fn def_map ->
      process_achievement(state, def_map, 1)
    end)
  end

  defp process_event({:tradeskill, item_id}, state) do
    AchievementIndex.lookup(:tradeskill, item_id)
    |> Enum.each(fn def_map ->
      process_achievement(state, def_map, 1)
    end)
  end

  defp process_event({:tradeskill, _action, item_id, count}, state) do
    AchievementIndex.lookup(:tradeskill, item_id)
    |> Enum.each(fn def_map ->
      process_achievement(state, def_map, count)
    end)
  end

  defp process_event({:challenge_complete, challenge_id}, state) do
    AchievementIndex.lookup(:challenge_complete, challenge_id)
    |> Enum.each(fn def_map ->
      process_achievement(state, def_map, 1)
    end)
  end

  defp process_event({:pvp, action}, state) do
    AchievementIndex.lookup(:pvp, action)
    |> Enum.each(fn def_map ->
      process_achievement(state, def_map, 1)
    end)
  end

  defp process_event({:pvp, action, _data}, state) do
    AchievementIndex.lookup(:pvp, action)
    |> Enum.each(fn def_map ->
      process_achievement(state, def_map, 1)
    end)
  end

  defp process_event({:datacube, datacube_id}, state) do
    AchievementIndex.lookup(:datacube, datacube_id)
    |> Enum.each(fn def_map ->
      process_achievement(state, def_map, 1)
    end)
  end

  defp process_event({:housing, action}, state) do
    AchievementIndex.lookup(:housing, action)
    |> Enum.each(fn def_map ->
      process_achievement(state, def_map, 1)
    end)
  end

  defp process_event({:social, action}, state) do
    AchievementIndex.lookup(:social, action)
    |> Enum.each(fn def_map ->
      process_achievement(state, def_map, 1)
    end)
  end

  defp process_event({:adventure_complete, adventure_id}, state) do
    AchievementIndex.lookup(:adventure_complete, adventure_id)
    |> Enum.each(fn def_map ->
      process_achievement(state, def_map, 1)
    end)
  end

  defp process_event({:event, event_id}, state) do
    AchievementIndex.lookup(:event, event_id)
    |> Enum.each(fn def_map ->
      process_achievement(state, def_map, 1)
    end)
  end

  defp process_event({:mount, mount_id}, state) do
    AchievementIndex.lookup(:mount, mount_id)
    |> Enum.each(fn def_map ->
      process_achievement(state, def_map, 1)
    end)
  end

  defp process_event({:level_up, new_level}, state) do
    AchievementIndex.lookup(:progression, :any)
    |> Enum.filter(fn def_map -> def_map.target <= new_level end)
    |> Enum.each(fn def_map ->
      process_achievement(state, def_map, new_level)
    end)
  end

  defp process_event({:item_collect, item_id, count}, state) do
    # Legacy support for item collection
    AchievementIndex.lookup(:tradeskill, item_id)
    |> Enum.each(fn def_map ->
      process_achievement(state, def_map, count)
    end)
  end

  defp process_event({:achievement, completed_id}, state) do
    # Meta achievements - check if completing this unlocks others
    AchievementIndex.lookup(:meta, :any)
    |> Enum.each(fn def_map ->
      check_meta_achievement(state, def_map, completed_id)
    end)
  end

  defp process_event(_event, _state), do: :ok

  # Unified Achievement Processing

  defp process_achievement(state, def_map, amount) do
    cond do
      def_map.has_checklist ->
        process_checklist_achievement(state, def_map, amount)

      def_map.target > 1 ->
        # Counter achievement
        case Achievements.increment_progress(
               state.character_id,
               def_map.id,
               amount,
               def_map.target,
               def_map.points
             ) do
          {:ok, ach, :completed} ->
            send_earned(state, ach, def_map)

          {:ok, ach, :progress} ->
            send_update(state.connection_pid, ach)

          _ ->
            :ok
        end

      true ->
        # Instant completion
        case Achievements.complete(state.character_id, def_map.id, def_map.points) do
          {:ok, ach, :completed} ->
            send_earned(state, ach, def_map)

          _ ->
            :ok
        end
    end
  end

  # Checklist/Bitfield Achievement Processing

  defp process_checklist_achievement(state, def_map, object_id) do
    checklists = Store.get_achievement_checklists(def_map.id)

    # Find matching checklist item by objectId
    case Enum.find(checklists, fn c -> Map.get(c, :objectId, 0) == object_id end) do
      nil ->
        :ok

      checklist_item ->
        bit_position = Map.get(checklist_item, :bit, 0)
        total_bits = length(checklists)

        case Achievements.get_achievement(state.character_id, def_map.id) do
          nil ->
            # First progress - create with bit set
            new_bits = 1 <<< bit_position
            all_bits = (1 <<< total_bits) - 1

            case Achievements.update_progress(
                   state.character_id,
                   def_map.id,
                   new_bits,
                   all_bits,
                   def_map.points
                 ) do
              {:ok, ach, :completed} ->
                send_earned(state, ach, def_map)

              {:ok, ach, :progress} ->
                send_update(state.connection_pid, ach)

              _ ->
                :ok
            end

          ach when ach.completed ->
            :ok

          ach ->
            # Set the bit using bitwise OR
            current_bits = ach.progress || 0
            new_bits = Bitwise.bor(current_bits, 1 <<< bit_position)
            all_bits = (1 <<< total_bits) - 1

            case Achievements.update_progress(
                   state.character_id,
                   def_map.id,
                   new_bits,
                   all_bits,
                   def_map.points
                 ) do
              {:ok, updated, :completed} ->
                send_earned(state, updated, def_map)

              {:ok, updated, :progress} ->
                send_update(state.connection_pid, updated)

              _ ->
                :ok
            end
        end
    end
  end

  # Meta Achievement Processing

  defp check_meta_achievement(state, def_map, _completed_achievement_id) do
    # Meta achievements have required achievements stored in checklist
    checklists = Store.get_achievement_checklists(def_map.id)

    if checklists != [] do
      # Check if all required achievements are complete
      required_ids = Enum.map(checklists, fn c -> Map.get(c, :objectId, 0) end)

      all_complete =
        Enum.all?(required_ids, fn req_id ->
          Achievements.completed?(state.character_id, req_id)
        end)

      if all_complete do
        case Achievements.complete(state.character_id, def_map.id, def_map.points) do
          {:ok, ach, :completed} ->
            send_earned(state, ach, def_map)

          _ ->
            :ok
        end
      end
    end
  end

  defp check_and_update(state, achievement_id, def_map) do
    case Achievements.get_achievement(state.character_id, achievement_id) do
      nil ->
        :ok

      ach ->
        if not ach.completed and ach.progress >= def_map.target do
          case Achievements.complete(state.character_id, achievement_id, def_map.points) do
            {:ok, updated, :completed} ->
              send_earned(state, updated, def_map)

            _ ->
              :ok
          end
        end
    end
  end

  defp build_def_map_from_achievement(achievement) do
    %{
      id: Map.get(achievement, :id) || Map.get(achievement, :ID),
      target: Map.get(achievement, :value, 1),
      points: Map.get(achievement, :achievementPointEnum, 0) |> points_for_enum(),
      title_id: Map.get(achievement, :characterTitleId, 0),
      has_checklist: Store.get_achievement_checklists(achievement.id) != []
    }
  end

  defp points_for_enum(0), do: 0
  defp points_for_enum(1), do: 5
  defp points_for_enum(2), do: 10
  defp points_for_enum(3), do: 25
  defp points_for_enum(_), do: 0

  # Packet Sending

  defp send_update(connection_pid, achievement) do
    packet = %ServerAchievementUpdate{
      achievement_id: achievement.achievement_id,
      progress: achievement.progress
    }

    send(connection_pid, {:send_packet, packet})
  end

  defp send_earned(state, achievement, def_map) do
    packet = %ServerAchievementEarned{
      achievement_id: achievement.achievement_id,
      points: achievement.points_awarded,
      completed_at: achievement.completed_at
    }

    send(state.connection_pid, {:send_packet, packet})

    Logger.info(
      "Achievement #{achievement.achievement_id} earned! (#{achievement.points_awarded} points)"
    )

    # Grant title if achievement has one
    title_id = Map.get(def_map, :title_id, 0)

    if title_id > 0 and state.account_id do
      TitleHandler.grant_title(state.connection_pid, state.account_id, title_id)
    end

    # Broadcast for meta achievements
    Achievements.broadcast(state.character_id, {:achievement, achievement.achievement_id})
  end
end
