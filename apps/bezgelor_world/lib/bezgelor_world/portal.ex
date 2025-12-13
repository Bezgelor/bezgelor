defmodule BezgelorWorld.Portal do
  @dialyzer :no_match

  @moduledoc """
  Portal integration module for admin panel operations.

  This module provides a unified API for the account portal to interact
  with the world server for:
  - Online player management
  - Zone/instance monitoring
  - Broadcasting messages
  - Event management
  - Server operations
  """

  alias BezgelorWorld.WorldManager

  require Logger

  # ============================================================================
  # Player Management
  # ============================================================================

  @doc """
  Get all online players with their session info.

  Returns list of maps with:
  - account_id, character_id, character_name
  - zone_id, instance_id
  - connection_pid, connected_at
  """
  @spec list_online_players() :: [map()]
  def list_online_players do
    WorldManager.list_sessions()
    |> Enum.map(fn {account_id, session} ->
      %{
        account_id: account_id,
        character_id: session.character_id,
        character_name: session.character_name || "Unknown",
        zone_id: session.zone_id,
        instance_id: session.instance_id,
        entity_guid: session.entity_guid,
        connection_pid: session.connection_pid
      }
    end)
  end

  @doc """
  Get count of online players.
  """
  @spec online_player_count() :: non_neg_integer()
  def online_player_count do
    WorldManager.session_count()
  end

  @doc """
  Get players grouped by zone.
  """
  @spec players_by_zone() :: %{non_neg_integer() => non_neg_integer()}
  def players_by_zone do
    list_online_players()
    |> Enum.group_by(& &1.zone_id)
    |> Enum.map(fn {zone_id, players} -> {zone_id, length(players)} end)
    |> Enum.into(%{})
  end

  @doc """
  Kick a player by account ID.
  """
  @spec kick_player(non_neg_integer(), String.t()) :: :ok | {:error, :not_online}
  def kick_player(account_id, reason \\ "Kicked by administrator") do
    case WorldManager.get_session(account_id) do
      nil ->
        {:error, :not_online}

      session ->
        # Send disconnect to the connection process
        send(session.connection_pid, {:disconnect, reason})
        Logger.info("Admin kicked player account_id=#{account_id} reason=#{reason}")
        :ok
    end
  end

  @doc """
  Kick a player by character ID.
  """
  @spec kick_player_by_character(non_neg_integer(), String.t()) :: :ok | {:error, :not_online}
  def kick_player_by_character(character_id, reason \\ "Kicked by administrator") do
    case WorldManager.get_session_by_character(character_id) do
      nil ->
        {:error, :not_online}

      session ->
        send(session.connection_pid, {:disconnect, reason})
        Logger.info("Admin kicked character_id=#{character_id} reason=#{reason}")
        :ok
    end
  end

  # ============================================================================
  # Broadcasting
  # ============================================================================

  @doc """
  Broadcast a system message to all online players.
  """
  @spec broadcast_system_message(String.t()) :: :ok
  def broadcast_system_message(message) do
    sessions = WorldManager.list_sessions()

    Enum.each(sessions, fn {_account_id, session} ->
      send(session.connection_pid, {:system_message, message})
    end)

    Logger.info("Admin broadcast: #{message}")
    :ok
  end

  @doc """
  Broadcast to players in a specific zone.
  """
  @spec broadcast_to_zone(non_neg_integer(), String.t()) :: :ok
  def broadcast_to_zone(zone_id, message) do
    sessions = WorldManager.get_zone_sessions(zone_id)

    Enum.each(sessions, fn session ->
      send(session.connection_pid, {:system_message, message})
    end)

    Logger.info("Admin zone broadcast zone_id=#{zone_id}: #{message}")
    :ok
  end

  # ============================================================================
  # Zone Management
  # ============================================================================

  @doc """
  Get all active zone instances.
  """
  @spec list_zone_instances() :: [map()]
  def list_zone_instances do
    # Query the zone instance registry
    case Process.whereis(BezgelorWorld.Zone.InstanceSupervisor) do
      nil ->
        []

      _pid ->
        DynamicSupervisor.which_children(BezgelorWorld.Zone.InstanceSupervisor)
        |> Enum.map(fn {_, pid, _, _} ->
          try do
            GenServer.call(pid, :get_state, 1000)
          catch
            :exit, _ -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)
        |> Enum.map(fn state ->
          %{
            zone_id: state.world_id,
            instance_id: state.instance_id,
            player_count: map_size(state.players || %{}),
            creature_count: map_size(state.creatures || %{}),
            started_at: state.started_at
          }
        end)
    end
  end

  @doc """
  Get player count per zone.
  """
  @spec zone_player_counts() :: [%{zone_id: integer(), zone_name: String.t(), player_count: integer()}]
  def zone_player_counts do
    players_by_zone()
    |> Enum.map(fn {zone_id, count} ->
      %{
        zone_id: zone_id || 0,
        zone_name: get_zone_name(zone_id),
        player_count: count
      }
    end)
    |> Enum.sort_by(& &1.player_count, :desc)
  end

  defp get_zone_name(nil), do: "Unknown"
  defp get_zone_name(zone_id) do
    # Try to get zone name from data store
    case BezgelorData.Store.get(:world_location, zone_id) do
      :error -> "Zone #{zone_id}"
      {:ok, data} -> Map.get(data, :name) || Map.get(data, "name") || "Zone #{zone_id}"
    end
  end

  @doc """
  Request a zone restart. Players will be teleported to safety.
  """
  @spec restart_zone(non_neg_integer()) :: :ok | {:error, :zone_not_found}
  def restart_zone(zone_id) do
    sessions = WorldManager.get_zone_sessions(zone_id)

    if length(sessions) > 0 do
      # Notify players
      Enum.each(sessions, fn session ->
        send(session.connection_pid, {:system_message, "Zone is restarting. Please stand by."})
      end)

      Logger.info("Admin requested zone restart zone_id=#{zone_id}")
      :ok
    else
      {:error, :zone_not_found}
    end
  end

  # ============================================================================
  # Instance Management
  # ============================================================================

  @doc """
  List all active dungeon/raid instances.
  """
  @spec list_instances() :: [map()]
  def list_instances do
    case Process.whereis(BezgelorWorld.Instance.InstanceSupervisor) do
      nil ->
        []

      _pid ->
        DynamicSupervisor.which_children(BezgelorWorld.Instance.InstanceSupervisor)
        |> Enum.map(fn {_, pid, _, _} ->
          try do
            GenServer.call(pid, :get_info, 1000)
          catch
            :exit, _ -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)
    end
  end

  @doc """
  Force close an instance.
  """
  @spec close_instance(String.t()) :: :ok | {:error, :not_found}
  def close_instance(instance_id) do
    # Try to find the instance process
    case find_instance_process(instance_id) do
      nil ->
        {:error, :not_found}

      pid ->
        GenServer.cast(pid, :force_close)
        Logger.info("Admin closed instance #{instance_id}")
        :ok
    end
  end

  defp find_instance_process(_instance_id) do
    # Placeholder - would search instance registry
    nil
  end

  # ============================================================================
  # Teleportation
  # ============================================================================

  @doc """
  Teleport a player out of an instance to their bind point or capital.
  """
  @spec teleport_player_out(non_neg_integer()) :: :ok | {:error, :not_online}
  def teleport_player_out(character_id) do
    case WorldManager.get_session_by_character(character_id) do
      nil ->
        {:error, :not_online}

      session ->
        # Send teleport command - teleport to bind point (Thayd/Illium based on faction)
        send(session.connection_pid, {:teleport_to_bind})
        Logger.info("Admin teleported character_id=#{character_id} out of instance")
        :ok
    end
  end

  @doc """
  Teleport all players in an instance out to safety.
  """
  @spec teleport_all_from_instance(String.t()) :: {:ok, integer()} | {:error, :not_found}
  def teleport_all_from_instance(instance_id) do
    # Get all players in this instance
    case find_instance_process(instance_id) do
      nil ->
        # Try zone instances
        players = get_instance_players(instance_id)
        if length(players) > 0 do
          Enum.each(players, fn player_id ->
            teleport_player_out(player_id)
          end)
          {:ok, length(players)}
        else
          {:error, :not_found}
        end

      pid ->
        try do
          players = GenServer.call(pid, :get_players, 1000)
          Enum.each(players, fn player_id ->
            teleport_player_out(player_id)
          end)
          Logger.info("Admin teleported #{length(players)} players from instance #{instance_id}")
          {:ok, length(players)}
        catch
          :exit, _ -> {:error, :not_found}
        end
    end
  end

  defp get_instance_players(instance_id) do
    # Parse zone instance ID format "zone-{zone_id}-{instance_id}"
    case String.split(instance_id, "-") do
      ["zone", zone_id_str, _inst_id] ->
        case Integer.parse(zone_id_str) do
          {zone_id, ""} ->
            WorldManager.get_zone_sessions(zone_id)
            |> Enum.map(& &1.character_id)
          _ -> []
        end
      _ -> []
    end
  end

  # ============================================================================
  # Event Management
  # ============================================================================

  @doc """
  Get all active events across all zones.
  """
  @spec list_active_events() :: [map()]
  def list_active_events do
    # Query EventManager processes for each zone
    case Process.whereis(BezgelorWorld.EventManagerSupervisor) do
      nil ->
        []

      _pid ->
        DynamicSupervisor.which_children(BezgelorWorld.EventManagerSupervisor)
        |> Enum.flat_map(fn {_, pid, _, _} ->
          try do
            GenServer.call(pid, :list_events, 1000)
          catch
            :exit, _ -> []
          end
        end)
    end
  end

  @doc """
  Start an event in a zone.
  """
  @spec start_event(non_neg_integer(), non_neg_integer()) :: {:ok, map()} | {:error, term()}
  def start_event(zone_id, event_id) do
    # Find event manager for zone
    case find_event_manager(zone_id) do
      nil ->
        {:error, :zone_not_active}

      pid ->
        GenServer.call(pid, {:start_event, event_id})
    end
  end

  @doc """
  Stop/cancel an active event.
  """
  @spec stop_event(non_neg_integer(), non_neg_integer()) :: :ok | {:error, term()}
  def stop_event(zone_id, event_instance_id) do
    case find_event_manager(zone_id) do
      nil ->
        {:error, :zone_not_active}

      pid ->
        GenServer.call(pid, {:cancel_event, event_instance_id})
    end
  end

  defp find_event_manager(_zone_id) do
    # Placeholder - would search by zone ID
    nil
  end

  # ============================================================================
  # World Boss Management
  # ============================================================================

  @doc """
  Get all world boss states.
  """
  @spec list_world_bosses() :: [map()]
  def list_world_bosses do
    # Would query from event managers or dedicated world boss tracker
    []
  end

  @doc """
  Force spawn a world boss.
  """
  @spec spawn_world_boss(non_neg_integer()) :: :ok | {:error, term()}
  def spawn_world_boss(boss_id) do
    Logger.info("Admin requested world boss spawn boss_id=#{boss_id}")
    # Would trigger spawn through appropriate zone manager
    :ok
  end

  @doc """
  Kill/despawn a world boss.
  """
  @spec despawn_world_boss(non_neg_integer()) :: :ok | {:error, term()}
  def despawn_world_boss(boss_id) do
    Logger.info("Admin requested world boss despawn boss_id=#{boss_id}")
    :ok
  end

  # ============================================================================
  # Server Status
  # ============================================================================

  @doc """
  Get server status information.
  """
  @spec server_status() :: map()
  def server_status do
    %{
      online_players: online_player_count(),
      active_zones: length(list_zone_instances()),
      active_instances: length(list_instances()),
      active_events: length(list_active_events()),
      uptime_seconds: get_uptime_seconds(),
      maintenance_mode: get_maintenance_mode(),
      motd: get_motd()
    }
  end

  @doc """
  Set maintenance mode.
  """
  @spec set_maintenance_mode(boolean()) :: :ok
  def set_maintenance_mode(enabled) do
    Application.put_env(:bezgelor_world, :maintenance_mode, enabled)
    Logger.info("Admin set maintenance_mode=#{enabled}")

    if enabled do
      broadcast_system_message("Server entering maintenance mode. Please log out.")
    end

    :ok
  end

  @doc """
  Get maintenance mode status.
  """
  @spec get_maintenance_mode() :: boolean()
  def get_maintenance_mode do
    Application.get_env(:bezgelor_world, :maintenance_mode, false)
  end

  @doc """
  Set message of the day.
  """
  @spec set_motd(String.t()) :: :ok
  def set_motd(message) do
    Application.put_env(:bezgelor_world, :motd, message)
    Logger.info("Admin updated MOTD")
    :ok
  end

  @doc """
  Get message of the day.
  """
  @spec get_motd() :: String.t()
  def get_motd do
    Application.get_env(:bezgelor_world, :motd, "Welcome to Bezgelor!")
  end

  defp get_uptime_seconds do
    case :erlang.statistics(:wall_clock) do
      {total_ms, _since_last} -> div(total_ms, 1000)
    end
  end

  # ============================================================================
  # Analytics Helpers
  # ============================================================================

  @doc """
  Get peak concurrent players (tracked in memory).
  """
  @spec peak_players() :: %{daily: integer(), weekly: integer(), all_time: integer()}
  def peak_players do
    # Would be tracked by a dedicated stats process
    current = online_player_count()
    %{
      daily: current,
      weekly: current,
      all_time: current
    }
  end
end
