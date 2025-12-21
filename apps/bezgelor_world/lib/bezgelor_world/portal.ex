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

  import Ecto.Query

  alias BezgelorDb.{ActionSets, Characters, Inventory, Repo}
  alias BezgelorDb.Schema.Character
  alias BezgelorCore.Zone
  alias BezgelorProtocol.ItemSlots
  alias BezgelorWorld.{Abilities, WorldManager}

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
  Broadcast a message to all online players with a type indicator.
  Types: :info, :warning, :alert
  """
  @spec broadcast_message(String.t(), atom()) :: :ok
  def broadcast_message(message, type \\ :info) do
    sessions = WorldManager.list_sessions()

    Enum.each(sessions, fn {_account_id, session} ->
      send(session.connection_pid, {:broadcast_message, message, type})
    end)

    Logger.info("Admin broadcast (#{type}): #{message}")
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
  @spec zone_player_counts() :: [
          %{zone_id: integer(), zone_name: String.t(), player_count: integer()}
        ]
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
  # Ability Defaults
  # ============================================================================

  @doc """
  Force-refresh the default action set shortcuts for a character.

  Options:
    * :spec_index - refresh only this spec index (defaults to character.active_spec)
    * :all_specs - refresh all specs (0..3)
  """
  @spec refresh_action_set_defaults(non_neg_integer(), keyword()) ::
          {:ok, map()} | {:error, :not_found}
  def refresh_action_set_defaults(character_id, opts \\ []) do
    case Repo.get(Character, character_id) do
      nil ->
        {:error, :not_found}

      character ->
        abilities = Abilities.get_class_action_set_abilities(character.class)
        spellbook = Abilities.get_class_spellbook_abilities(character.class)

        _ = Inventory.ensure_ability_items(character.id, spellbook)

        spec_indices =
          if Keyword.get(opts, :all_specs, false) do
            Enum.to_list(0..3)
          else
            [Keyword.get(opts, :spec_index, character.active_spec || 0)]
          end

        shortcuts =
          spec_indices
          |> Enum.flat_map(fn spec_index ->
            ActionSets.ensure_default_shortcuts(character.id, abilities, spec_index, force: true)
          end)

        Logger.info(
          "Admin refreshed action set defaults character_id=#{character.id} " <>
            "spec_indices=#{inspect(spec_indices)}"
        )

        {:ok, %{character_id: character.id, spec_indices: spec_indices, shortcuts: shortcuts}}
    end
  end

  @doc """
  Delete all characters.

  Defaults to soft delete; pass `hard: true` to remove all character data.
  """
  @spec delete_all_characters(keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def delete_all_characters(opts \\ []) do
    if Keyword.get(opts, :hard, false) do
      hard_delete_all_characters()
    else
      soft_delete_all_characters()
    end
  end

  defp soft_delete_all_characters do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {count, _} =
      Character
      |> where([c], is_nil(c.deleted_at))
      |> Repo.update_all(set: [deleted_at: now])

    Logger.info("Admin soft-deleted all characters count=#{count}")
    {:ok, count}
  end

  defp hard_delete_all_characters do
    tables = [
      BezgelorDb.Schema.Achievement,
      BezgelorDb.Schema.ActiveMount,
      BezgelorDb.Schema.ActivePet,
      BezgelorDb.Schema.ArenaTeamMember,
      BezgelorDb.Schema.Bag,
      BezgelorDb.Schema.BattlegroundQueue,
      BezgelorDb.Schema.CharacterActionSetShortcut,
      BezgelorDb.Schema.CharacterAppearance,
      BezgelorDb.Schema.CharacterCollection,
      BezgelorDb.Schema.CharacterCurrency,
      BezgelorDb.Schema.CharacterTradeskill,
      BezgelorDb.Schema.EventCompletion,
      BezgelorDb.Schema.EventParticipation,
      BezgelorDb.Schema.Friend,
      BezgelorDb.Schema.GroupFinderQueue,
      BezgelorDb.Schema.GuildMember,
      BezgelorDb.Schema.HousingNeighbor,
      BezgelorDb.Schema.HousingPlot,
      BezgelorDb.Schema.Ignore,
      BezgelorDb.Schema.InstanceCompletion,
      BezgelorDb.Schema.InstanceLockout,
      BezgelorDb.Schema.InventoryItem,
      BezgelorDb.Schema.LootHistory,
      BezgelorDb.Schema.MythicKeystone,
      BezgelorDb.Schema.Path,
      BezgelorDb.Schema.PathMission,
      BezgelorDb.Schema.PvpRating,
      BezgelorDb.Schema.PvpStats,
      BezgelorDb.Schema.Quest,
      BezgelorDb.Schema.QuestHistory,
      BezgelorDb.Schema.Reputation,
      BezgelorDb.Schema.SchematicDiscovery,
      BezgelorDb.Schema.TradeskillTalent,
      BezgelorDb.Schema.WorkOrder,
      BezgelorDb.Schema.Character
    ]

    result =
      Repo.transaction(fn ->
        Enum.reduce(tables, 0, fn schema, acc ->
          {deleted, _} = Repo.delete_all(schema)
          acc + deleted
        end)
      end)

    case result do
      {:ok, count} ->
        Logger.info("Admin hard-deleted all character data rows=#{count}")
        {:ok, count}

      {:error, reason} ->
        Logger.error("Admin hard-delete failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # ============================================================================
  # Character Creation
  # ============================================================================

  @doc """
  Create a character for any race/class combination.

  Options:
    * :sex - 0 (male) or 1 (female), default 0
    * :faction_id - override faction (166 Dominion, 167 Exile)
    * :creation_start - CharacterCreationStart enum (default 4)
    * :path - starting path (default 0)
    * :realm_id - override realm (default config realm_id)
    * :labels - customization label ids
    * :values - customization values (same length as labels)
    * :appearance - additional appearance attributes to merge
    * :character_creation_id - force a CharacterCreation entry for starting gear
  """
  @spec create_character(
          non_neg_integer(),
          String.t() | nil,
          non_neg_integer(),
          non_neg_integer(),
          keyword()
        ) :: {:ok, map()} | {:error, term()}
  def create_character(account_id, name, race_id, class_id, opts \\ []) do
    name = normalize_character_name(name, opts)
    sex = Keyword.get(opts, :sex, 0)
    faction_id = Keyword.get(opts, :faction_id, faction_for_race(race_id))
    creation_start = Keyword.get(opts, :creation_start, 4)
    path_id = Keyword.get(opts, :path, 0)
    realm_id = Keyword.get(opts, :realm_id, Application.get_env(:bezgelor_realm, :realm_id, 1))

    spawn = Zone.starting_location(creation_start, faction_id)

    character_attrs = %{
      name: name,
      sex: sex,
      race: race_id,
      class: class_id,
      faction_id: faction_id,
      realm_id: realm_id,
      world_id: spawn.world_id,
      world_zone_id: spawn.zone_id,
      location_x: elem(spawn.position, 0),
      location_y: elem(spawn.position, 1),
      location_z: elem(spawn.position, 2),
      rotation_x: elem(spawn.rotation, 0),
      rotation_y: elem(spawn.rotation, 1),
      rotation_z: elem(spawn.rotation, 2),
      active_path: path_id
    }

    labels = Keyword.get(opts, :labels, [])
    values = Keyword.get(opts, :values, [])
    appearance_attrs = Keyword.get(opts, :appearance, %{})
    visuals = resolve_visuals(race_id, sex, labels, values)

    appearance_attrs =
      appearance_attrs
      |> Map.put_new(:labels, labels)
      |> Map.put_new(:values, values)
      |> Map.put_new(:visuals, visuals)

    case Characters.create_character(account_id, character_attrs, appearance_attrs) do
      {:ok, character} ->
        finalize_character_setup(
          character,
          race_id,
          class_id,
          sex,
          faction_id,
          creation_start,
          opts
        )

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Create a character with an auto-generated unique name.
  """
  @spec create_character_auto(non_neg_integer(), non_neg_integer(), non_neg_integer(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def create_character_auto(account_id, race_id, class_id, opts \\ []) do
    create_character(account_id, nil, race_id, class_id, opts)
  end

  defp finalize_character_setup(
         character,
         race_id,
         class_id,
         sex,
         faction_id,
         creation_start,
         opts
       ) do
    Inventory.init_bags(character.id)

    case find_character_creation(race_id, class_id, sex, faction_id, creation_start, opts) do
      nil -> :ok
      creation_entry -> add_starting_gear(character.id, creation_entry)
    end

    spellbook_abilities = Abilities.get_class_spellbook_abilities(class_id)
    action_set_abilities = Abilities.get_class_action_set_abilities(class_id)

    ActionSets.ensure_default_shortcuts(character.id, action_set_abilities, 0, force: true)
    Inventory.ensure_ability_items(character.id, spellbook_abilities)

    Logger.info(
      "Admin created character '#{character.name}' (ID: #{character.id}) race=#{race_id} " <>
        "class=#{class_id} faction=#{faction_id}"
    )

    {:ok, character}
  end

  defp resolve_visuals(_race_id, _sex, [], []), do: []

  defp resolve_visuals(race_id, sex, labels, values) do
    customizations = Enum.zip(labels, values)
    BezgelorData.Store.get_item_visuals(race_id, sex, customizations)
  end

  defp normalize_character_name(name, opts) do
    case {name, Keyword.get(opts, :name)} do
      {nil, :auto} -> unique_name(opts)
      {nil, opt_name} when is_binary(opt_name) -> opt_name
      {nil, _} -> unique_name(opts)
      {:auto, _} -> unique_name(opts)
      {name, _} when is_binary(name) -> name
      {_, opt_name} when is_binary(opt_name) -> opt_name
      _ -> unique_name(opts)
    end
  end

  defp unique_name(opts) do
    prefix =
      opts
      |> Keyword.get(:name_prefix, "Test")
      |> String.replace(~r/[^A-Za-z0-9]/, "")
      |> case do
        "" -> "Test"
        value -> value
      end

    max_attempts = Keyword.get(opts, :max_name_attempts, 50)

    Enum.reduce_while(1..max_attempts, nil, fn _attempt, _acc ->
      name = "#{prefix}#{:rand.uniform(9_999)}"

      if Characters.name_available?(name) do
        {:halt, name}
      else
        {:cont, nil}
      end
    end) || "#{prefix}#{System.unique_integer([:positive])}"
  end

  defp find_character_creation(race_id, class_id, sex, faction_id, creation_start, opts) do
    case Keyword.get(opts, :character_creation_id) do
      nil ->
        entries =
          BezgelorData.Store.list(:character_creations)
          |> Enum.filter(fn entry ->
            entry.classId == class_id and entry.raceId == race_id and entry.sex == sex and
              entry.factionId == faction_id
          end)

        entries
        |> Enum.find(fn entry -> entry.characterCreationStartEnum == creation_start end)
        |> case do
          nil -> List.first(entries)
          entry -> entry
        end

      creation_id ->
        case BezgelorData.Store.get(:character_creations, creation_id) do
          {:ok, entry} -> entry
          :error -> nil
        end
    end
  end

  defp add_starting_gear(character_id, creation_entry) do
    item_keys = for i <- 0..15, do: item_key(i)

    item_keys
    |> Enum.map(fn key -> get_item_id(creation_entry, key) end)
    |> Enum.filter(&(&1 > 0))
    |> Enum.each(fn item_id -> add_equipped_item(character_id, item_id) end)
  end

  defp item_key(0), do: "itemId0"
  defp item_key(n) when n < 10, do: "itemId0#{n}"
  defp item_key(n), do: "itemId0#{n}"

  defp get_item_id(entry, key) when is_binary(key) do
    Map.get(entry, String.to_atom(key), 0)
  end

  defp add_equipped_item(character_id, item_id) do
    item_slot = BezgelorData.Store.get_item_slot(item_id)

    case item_slot do
      nil ->
        Logger.debug("Item #{item_id} has no slot, skipping")

      item_slot when item_slot > 0 ->
        case ItemSlots.item_slot_to_equipped(item_slot) do
          nil ->
            Logger.debug("Item #{item_id} has unmapped ItemSlot #{item_slot}, skipping")

          equipped_slot ->
            attrs = %{
              character_id: character_id,
              item_id: item_id,
              container_type: :equipped,
              bag_index: 0,
              slot: equipped_slot,
              quantity: 1,
              max_stack: 1,
              durability: 100,
              max_durability: 100
            }

            case BezgelorDb.Repo.insert(
                   BezgelorDb.Schema.InventoryItem.changeset(
                     %BezgelorDb.Schema.InventoryItem{},
                     attrs
                   )
                 ) do
              {:ok, _item} ->
                :ok

              {:error, changeset} ->
                Logger.warning(
                  "Failed to add starting item #{item_id}: #{inspect(changeset.errors)}"
                )
            end
        end

      _ ->
        :ok
    end
  end

  defp faction_for_race(1), do: 167
  defp faction_for_race(3), do: 167
  defp faction_for_race(4), do: 167
  defp faction_for_race(16), do: 167
  defp faction_for_race(2), do: 166
  defp faction_for_race(5), do: 166
  defp faction_for_race(12), do: 166
  defp faction_for_race(13), do: 166
  defp faction_for_race(_), do: 167

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

          _ ->
            []
        end

      _ ->
        []
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

  # ============================================================================
  # Server Configuration
  # ============================================================================

  alias BezgelorWorld.ServerConfig

  @doc """
  Get all config sections with their schemas and current values.
  """
  @spec get_all_settings() :: map()
  def get_all_settings do
    ServerConfig.list_sections()
  end

  @doc """
  Get a specific config section.
  """
  @spec get_settings(atom()) :: map() | nil
  def get_settings(section) do
    ServerConfig.get_section(section)
  end

  @doc """
  Update a setting in a config section.
  Returns the old value on success for audit logging.
  """
  @spec update_setting(atom(), atom(), term()) :: {:ok, term()} | {:error, term()}
  def update_setting(section, key, new_value) do
    # Get old value for audit logging
    old_value =
      case ServerConfig.get_setting(section, key) do
        {:ok, val} -> val
        _ -> nil
      end

    case ServerConfig.update_setting(section, key, new_value) do
      :ok ->
        Logger.info(
          "Admin updated setting #{section}.#{key}: #{inspect(old_value)} -> #{inspect(new_value)}"
        )

        {:ok, old_value}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ============================================================================
  # Server Restart
  # ============================================================================

  @doc """
  Restart the world server with a configurable countdown delay.
  Broadcasts warnings to players before disconnecting them.

  ## Parameters
  - delay_seconds: Countdown before restart (default 5)

  ## Returns
  - {:ok, %{players_affected: count, delay: seconds}} on success
  - {:error, :not_running} if world server is not running
  """
  @spec restart_world_server(non_neg_integer()) :: {:ok, map()} | {:error, :not_running}
  def restart_world_server(delay_seconds \\ 5) do
    unless world_server_running?() do
      {:error, :not_running}
    else
      player_count = online_player_count()

      # Spawn async task so we can return immediately to the caller
      Task.start(fn ->
        # 1. Countdown warning
        broadcast_system_message("Server restarting in #{delay_seconds} seconds...")

        Logger.warning(
          "World server restart initiated with #{delay_seconds}s delay, #{player_count} players online"
        )

        # 2. Wait the configured delay
        Process.sleep(delay_seconds * 1_000)

        # 3. Final warning immediately before stop
        broadcast_system_message("Server restarting now. Please reconnect shortly.")
        Process.sleep(500)

        # 4. Stop and restart the world server
        Logger.warning("Stopping :bezgelor_world application...")
        Application.stop(:bezgelor_world)

        Logger.info("Restarting :bezgelor_world application...")
        Application.ensure_all_started(:bezgelor_world)

        Logger.info("World server restart complete")
      end)

      {:ok, %{players_affected: player_count, delay: delay_seconds}}
    end
  end

  @doc """
  Check if the world server is running.
  """
  @spec world_server_running?() :: boolean()
  def world_server_running? do
    case Process.whereis(BezgelorWorld.WorldManager) do
      nil -> false
      _pid -> true
    end
  end
end
