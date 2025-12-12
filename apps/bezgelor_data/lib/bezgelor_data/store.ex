defmodule BezgelorData.Store do
  @moduledoc """
  ETS-backed storage for game data.

  Each data type gets its own ETS table for fast concurrent reads.
  Data is loaded at application startup from ETF files (compiled from JSON).
  """

  use GenServer

  require Logger

  alias BezgelorData.Compiler

  @tables [
    :creatures,
    :zones,
    :spells,
    :items,
    :texts,
    :house_types,
    :housing_decor,
    :housing_fabkits,
    :titles,
    :tradeskill_professions,
    :tradeskill_schematics,
    :tradeskill_talents,
    :tradeskill_additives,
    :tradeskill_nodes,
    :tradeskill_work_orders,
    :public_events,
    :world_bosses,
    :event_spawn_points,
    :event_loot_tables,
    :instances,
    :instance_bosses,
    :mythic_affixes,
    # PvP data
    :battlegrounds,
    :arenas,
    :warplot_plugs,
    # Spawn data
    :creature_spawns
  ]

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get an item by ID from the specified table.
  """
  @spec get(atom(), non_neg_integer()) :: {:ok, map()} | :error
  def get(table, id) do
    case :ets.lookup(table_name(table), id) do
      [{^id, data}] -> {:ok, data}
      [] -> :error
    end
  end

  @doc """
  List all items from the specified table.
  """
  @spec list(atom()) :: [map()]
  def list(table) do
    :ets.tab2list(table_name(table))
    |> Enum.map(fn {_id, data} -> data end)
  end

  @doc """
  Get the count of items in a table.
  """
  @spec count(atom()) :: non_neg_integer()
  def count(table) do
    :ets.info(table_name(table), :size)
  end

  @doc """
  Reload data from files. Used for development/testing.
  """
  @spec reload() :: :ok
  def reload do
    GenServer.call(__MODULE__, :reload)
  end

  # Tradeskill-specific queries

  @doc """
  Get a profession by ID.
  """
  @spec get_profession(non_neg_integer()) :: {:ok, map()} | :error
  def get_profession(id), do: get(:tradeskill_professions, id)

  @doc """
  Get all professions of a specific type.
  """
  @spec get_professions_by_type(atom()) :: [map()]
  def get_professions_by_type(type) when type in [:crafting, :gathering] do
    type_str = Atom.to_string(type)

    list(:tradeskill_professions)
    |> Enum.filter(fn p -> p.type == type_str end)
  end

  @doc """
  Get a schematic by ID.
  """
  @spec get_schematic(non_neg_integer()) :: {:ok, map()} | :error
  def get_schematic(id), do: get(:tradeskill_schematics, id)

  @doc """
  Get all schematics for a profession.
  """
  @spec get_schematics_for_profession(non_neg_integer()) :: [map()]
  def get_schematics_for_profession(profession_id) do
    list(:tradeskill_schematics)
    |> Enum.filter(fn s -> s.profession_id == profession_id end)
  end

  @doc """
  Get schematics available at a skill level.
  """
  @spec get_available_schematics(non_neg_integer(), non_neg_integer()) :: [map()]
  def get_available_schematics(profession_id, skill_level) do
    list(:tradeskill_schematics)
    |> Enum.filter(fn s ->
      s.profession_id == profession_id and s.min_level <= skill_level
    end)
  end

  @doc """
  Get a talent by ID.
  """
  @spec get_talent(non_neg_integer()) :: {:ok, map()} | :error
  def get_talent(id), do: get(:tradeskill_talents, id)

  @doc """
  Get all talents for a profession.
  """
  @spec get_talents_for_profession(non_neg_integer()) :: [map()]
  def get_talents_for_profession(profession_id) do
    list(:tradeskill_talents)
    |> Enum.filter(fn t -> t.profession_id == profession_id end)
    |> Enum.sort_by(fn t -> {t.tier, t.id} end)
  end

  @doc """
  Get an additive by ID.
  """
  @spec get_additive(non_neg_integer()) :: {:ok, map()} | :error
  def get_additive(id), do: get(:tradeskill_additives, id)

  @doc """
  Get additive by item ID.
  """
  @spec get_additive_by_item(non_neg_integer()) :: {:ok, map()} | :error
  def get_additive_by_item(item_id) do
    case Enum.find(list(:tradeskill_additives), fn a -> a.item_id == item_id end) do
      nil -> :error
      additive -> {:ok, additive}
    end
  end

  @doc """
  Get a node type by ID.
  """
  @spec get_node_type(non_neg_integer()) :: {:ok, map()} | :error
  def get_node_type(id), do: get(:tradeskill_nodes, id)

  @doc """
  Get all node types for a profession.
  """
  @spec get_node_types_for_profession(non_neg_integer()) :: [map()]
  def get_node_types_for_profession(profession_id) do
    list(:tradeskill_nodes)
    |> Enum.filter(fn n -> n.profession_id == profession_id end)
  end

  @doc """
  Get node types for a level range.
  """
  @spec get_node_types_for_level(non_neg_integer(), non_neg_integer()) :: [map()]
  def get_node_types_for_level(profession_id, level) do
    list(:tradeskill_nodes)
    |> Enum.filter(fn n ->
      n.profession_id == profession_id and n.min_level <= level and n.max_level >= level
    end)
  end

  @doc """
  Get a work order template by ID.
  """
  @spec get_work_order_template(non_neg_integer()) :: {:ok, map()} | :error
  def get_work_order_template(id), do: get(:tradeskill_work_orders, id)

  @doc """
  Get all work order templates for a profession.
  """
  @spec get_work_orders_for_profession(non_neg_integer()) :: [map()]
  def get_work_orders_for_profession(profession_id) do
    list(:tradeskill_work_orders)
    |> Enum.filter(fn wo -> wo.profession_id == profession_id end)
  end

  @doc """
  Get available work order templates at a skill level.
  """
  @spec get_available_work_orders(non_neg_integer(), non_neg_integer()) :: [map()]
  def get_available_work_orders(profession_id, skill_level) do
    list(:tradeskill_work_orders)
    |> Enum.filter(fn wo ->
      wo.profession_id == profession_id and wo.min_level <= skill_level
    end)
  end

  # Public Events queries

  @doc """
  Get a public event definition by ID.
  """
  @spec get_public_event(non_neg_integer()) :: {:ok, map()} | :error
  def get_public_event(id), do: get(:public_events, id)

  @doc """
  Get all public events for a zone.
  """
  @spec get_zone_public_events(non_neg_integer()) :: [map()]
  def get_zone_public_events(zone_id) do
    list(:public_events)
    |> Enum.filter(fn event -> event.zone_id == zone_id end)
  end

  @doc """
  Get a world boss definition by ID.
  """
  @spec get_world_boss(non_neg_integer()) :: {:ok, map()} | :error
  def get_world_boss(id), do: get(:world_bosses, id)

  @doc """
  Get all world bosses for a zone.
  """
  @spec get_zone_world_bosses(non_neg_integer()) :: [map()]
  def get_zone_world_bosses(zone_id) do
    list(:world_bosses)
    |> Enum.filter(fn boss -> boss.zone_id == zone_id end)
  end

  @doc """
  Get spawn points for a zone.
  """
  @spec get_event_spawn_points(non_neg_integer()) :: {:ok, map()} | :error
  def get_event_spawn_points(zone_id), do: get(:event_spawn_points, zone_id)

  @doc """
  Get specific spawn point group.
  """
  @spec get_spawn_point_group(non_neg_integer(), String.t()) :: [map()]
  def get_spawn_point_group(zone_id, group_name) do
    case get_event_spawn_points(zone_id) do
      {:ok, data} -> Map.get(data.spawn_point_groups, group_name, [])
      :error -> []
    end
  end

  @doc """
  Get an event loot table by ID.
  """
  @spec get_event_loot_table(non_neg_integer()) :: {:ok, map()} | :error
  def get_event_loot_table(id), do: get(:event_loot_tables, id)

  @doc """
  Get loot table for an event.
  """
  @spec get_loot_table_for_event(non_neg_integer()) :: {:ok, map()} | :error
  def get_loot_table_for_event(event_id) do
    case Enum.find(list(:event_loot_tables), fn lt -> lt.event_id == event_id end) do
      nil -> :error
      loot_table -> {:ok, loot_table}
    end
  end

  @doc """
  Get loot table for a world boss.
  """
  @spec get_loot_table_for_world_boss(non_neg_integer()) :: {:ok, map()} | :error
  def get_loot_table_for_world_boss(boss_id) do
    case Enum.find(list(:event_loot_tables), fn lt -> lt[:world_boss_id] == boss_id end) do
      nil -> :error
      loot_table -> {:ok, loot_table}
    end
  end

  @doc """
  Get tier drops from a loot table.
  """
  @spec get_tier_drops(non_neg_integer(), atom()) :: [map()]
  def get_tier_drops(loot_table_id, tier) when tier in [:gold, :silver, :bronze, :participation] do
    case get_event_loot_table(loot_table_id) do
      {:ok, loot_table} ->
        tier_key = Atom.to_string(tier)
        Map.get(loot_table.tier_drops, String.to_atom(tier_key), [])

      :error ->
        []
    end
  end

  # Instance/Dungeon queries

  @doc """
  Get an instance definition by ID.
  """
  @spec get_instance(non_neg_integer()) :: {:ok, map()} | :error
  def get_instance(id), do: get(:instances, id)

  @doc """
  Get all instances of a specific type.
  """
  @spec get_instances_by_type(String.t()) :: [map()]
  def get_instances_by_type(type) when type in ["dungeon", "adventure", "raid", "expedition"] do
    list(:instances)
    |> Enum.filter(fn i -> i.type == type end)
  end

  @doc """
  Get instances available for a player level.
  """
  @spec get_available_instances(non_neg_integer()) :: [map()]
  def get_available_instances(player_level) do
    list(:instances)
    |> Enum.filter(fn i -> i.min_level <= player_level and i.max_level >= player_level end)
  end

  @doc """
  Get instances with a specific difficulty.
  """
  @spec get_instances_with_difficulty(String.t()) :: [map()]
  def get_instances_with_difficulty(difficulty) do
    list(:instances)
    |> Enum.filter(fn i -> difficulty in i.difficulties end)
  end

  @doc """
  Get an instance boss definition by ID.
  """
  @spec get_instance_boss(non_neg_integer()) :: {:ok, map()} | :error
  def get_instance_boss(id), do: get(:instance_bosses, id)

  @doc """
  Get all bosses for an instance.
  """
  @spec get_bosses_for_instance(non_neg_integer()) :: [map()]
  def get_bosses_for_instance(instance_id) do
    list(:instance_bosses)
    |> Enum.filter(fn b -> b.instance_id == instance_id end)
    |> Enum.sort_by(fn b -> b.order end)
  end

  @doc """
  Get required bosses for an instance (non-optional).
  """
  @spec get_required_bosses(non_neg_integer()) :: [map()]
  def get_required_bosses(instance_id) do
    get_bosses_for_instance(instance_id)
    |> Enum.filter(fn b -> not b.is_optional end)
  end

  @doc """
  Get optional bosses for an instance.
  """
  @spec get_optional_bosses(non_neg_integer()) :: [map()]
  def get_optional_bosses(instance_id) do
    get_bosses_for_instance(instance_id)
    |> Enum.filter(fn b -> b.is_optional end)
  end

  @doc """
  Get a mythic affix by ID.
  """
  @spec get_mythic_affix(non_neg_integer()) :: {:ok, map()} | :error
  def get_mythic_affix(id), do: get(:mythic_affixes, id)

  @doc """
  Get all mythic affixes.
  """
  @spec get_all_mythic_affixes() :: [map()]
  def get_all_mythic_affixes, do: list(:mythic_affixes)

  @doc """
  Get affixes available at a keystone level.
  """
  @spec get_affixes_for_level(non_neg_integer()) :: [map()]
  def get_affixes_for_level(keystone_level) do
    list(:mythic_affixes)
    |> Enum.filter(fn a -> a.min_level <= keystone_level end)
  end

  @doc """
  Get affixes by tier.
  """
  @spec get_affixes_by_tier(non_neg_integer()) :: [map()]
  def get_affixes_by_tier(tier) when tier in 1..4 do
    list(:mythic_affixes)
    |> Enum.filter(fn a -> a.tier == tier end)
  end

  @doc """
  Get the weekly affix rotation for a given week.
  Returns nil if week is out of range or data not loaded.
  """
  @spec get_weekly_affix_rotation(non_neg_integer()) :: [map()] | nil
  def get_weekly_affix_rotation(week) when week >= 1 and week <= 12 do
    # This uses a special metadata key to store rotation data
    case :ets.lookup(table_name(:mythic_affixes), :weekly_rotation) do
      [{:weekly_rotation, rotations}] ->
        rotation = Enum.find(rotations, fn r -> r.week == week end)

        if rotation do
          Enum.map(rotation.affixes, fn affix_id ->
            case get_mythic_affix(affix_id) do
              {:ok, affix} -> affix
              :error -> nil
            end
          end)
          |> Enum.reject(&is_nil/1)
        else
          nil
        end

      [] ->
        nil
    end
  end

  def get_weekly_affix_rotation(_week), do: nil

  # PvP queries

  @doc """
  Get a battleground definition by ID.
  """
  @spec get_battleground(non_neg_integer()) :: {:ok, map()} | :error
  def get_battleground(id), do: get(:battlegrounds, id)

  @doc """
  Get all battlegrounds.
  """
  @spec get_all_battlegrounds() :: [map()]
  def get_all_battlegrounds, do: list(:battlegrounds)

  @doc """
  Get battlegrounds available for a player level.
  """
  @spec get_available_battlegrounds(non_neg_integer()) :: [map()]
  def get_available_battlegrounds(player_level) do
    list(:battlegrounds)
    |> Enum.filter(fn bg -> bg.min_level <= player_level and bg.max_level >= player_level end)
  end

  @doc """
  Get battlegrounds by type.
  """
  @spec get_battlegrounds_by_type(String.t()) :: [map()]
  def get_battlegrounds_by_type(type) do
    list(:battlegrounds)
    |> Enum.filter(fn bg -> bg.type == type end)
  end

  @doc """
  Get an arena definition by ID.
  """
  @spec get_arena(non_neg_integer()) :: {:ok, map()} | :error
  def get_arena(id), do: get(:arenas, id)

  @doc """
  Get all arenas.
  """
  @spec get_all_arenas() :: [map()]
  def get_all_arenas, do: list(:arenas)

  @doc """
  Get arenas that support a specific bracket.
  """
  @spec get_arenas_for_bracket(String.t()) :: [map()]
  def get_arenas_for_bracket(bracket) do
    list(:arenas)
    |> Enum.filter(fn arena -> bracket in arena.brackets end)
  end

  @doc """
  Get arena bracket configuration.
  Returns nil if bracket data not loaded or bracket not found.
  """
  @spec get_arena_bracket(String.t()) :: map() | nil
  def get_arena_bracket(bracket) do
    case :ets.lookup(table_name(:arenas), :brackets) do
      [{:brackets, brackets}] -> Map.get(brackets, String.to_atom(bracket))
      [] -> nil
    end
  end

  @doc """
  Get arena rating rewards configuration.
  """
  @spec get_arena_rating_rewards() :: map() | nil
  def get_arena_rating_rewards do
    case :ets.lookup(table_name(:arenas), :rating_rewards) do
      [{:rating_rewards, rewards}] -> rewards
      [] -> nil
    end
  end

  @doc """
  Get a warplot plug definition by ID.
  """
  @spec get_warplot_plug(non_neg_integer()) :: {:ok, map()} | :error
  def get_warplot_plug(id), do: get(:warplot_plugs, id)

  @doc """
  Get all warplot plugs.
  """
  @spec get_all_warplot_plugs() :: [map()]
  def get_all_warplot_plugs, do: list(:warplot_plugs)

  @doc """
  Get warplot plugs by category.
  """
  @spec get_warplot_plugs_by_category(String.t()) :: [map()]
  def get_warplot_plugs_by_category(category) do
    list(:warplot_plugs)
    |> Enum.filter(fn plug -> plug.category == category end)
  end

  @doc """
  Get warplot plug categories with descriptions.
  """
  @spec get_warplot_plug_categories() :: map() | nil
  def get_warplot_plug_categories do
    case :ets.lookup(table_name(:warplot_plugs), :categories) do
      [{:categories, categories}] -> categories
      [] -> nil
    end
  end

  @doc """
  Get warplot socket layout.
  """
  @spec get_warplot_socket_layout() :: map() | nil
  def get_warplot_socket_layout do
    case :ets.lookup(table_name(:warplot_plugs), :socket_layout) do
      [{:socket_layout, layout}] -> layout
      [] -> nil
    end
  end

  @doc """
  Get warplot settings.
  """
  @spec get_warplot_settings() :: map() | nil
  def get_warplot_settings do
    case :ets.lookup(table_name(:warplot_plugs), :warplot_settings) do
      [{:warplot_settings, settings}] -> settings
      [] -> nil
    end
  end

  # Creature Spawn queries

  @doc """
  Get creature spawns for a world/zone.
  Returns a map with creature_spawns, resource_spawns, and object_spawns.
  """
  @spec get_creature_spawns(non_neg_integer()) :: {:ok, map()} | :error
  def get_creature_spawns(world_id), do: get(:creature_spawns, world_id)

  @doc """
  Get all zone spawn data.
  """
  @spec get_all_spawn_zones() :: [map()]
  def get_all_spawn_zones, do: list(:creature_spawns)

  @doc """
  Get creature spawns for a specific area within a zone.
  """
  @spec get_spawns_in_area(non_neg_integer(), non_neg_integer()) :: [map()]
  def get_spawns_in_area(world_id, area_id) do
    case get_creature_spawns(world_id) do
      {:ok, zone_data} ->
        Enum.filter(zone_data.creature_spawns, fn spawn ->
          spawn.area_id == area_id
        end)

      :error ->
        []
    end
  end

  @doc """
  Get all spawns for a specific creature template ID across all zones.
  """
  @spec get_spawns_for_creature(non_neg_integer()) :: [map()]
  def get_spawns_for_creature(creature_id) do
    list(:creature_spawns)
    |> Enum.flat_map(fn zone_data ->
      Enum.filter(zone_data.creature_spawns, fn spawn ->
        spawn.creature_id == creature_id
      end)
    end)
  end

  @doc """
  Get resource spawns for a world/zone.
  """
  @spec get_resource_spawns(non_neg_integer()) :: [map()]
  def get_resource_spawns(world_id) do
    case get_creature_spawns(world_id) do
      {:ok, zone_data} -> zone_data.resource_spawns
      :error -> []
    end
  end

  @doc """
  Get object spawns for a world/zone.
  """
  @spec get_object_spawns(non_neg_integer()) :: [map()]
  def get_object_spawns(world_id) do
    case get_creature_spawns(world_id) do
      {:ok, zone_data} -> zone_data.object_spawns
      :error -> []
    end
  end

  @doc """
  Get spawn count for a world/zone.
  """
  @spec get_spawn_count(non_neg_integer()) :: non_neg_integer()
  def get_spawn_count(world_id) do
    case get_creature_spawns(world_id) do
      {:ok, zone_data} ->
        length(zone_data.creature_spawns) +
          length(zone_data.resource_spawns) +
          length(zone_data.object_spawns)

      :error ->
        0
    end
  end

  @doc """
  Get total spawn count across all zones.
  """
  @spec get_total_spawn_count() :: non_neg_integer()
  def get_total_spawn_count do
    list(:creature_spawns)
    |> Enum.reduce(0, fn zone_data, acc ->
      acc +
        length(zone_data.creature_spawns) +
        length(zone_data.resource_spawns) +
        length(zone_data.object_spawns)
    end)
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    # Create ETS tables
    for table <- @tables do
      :ets.new(table_name(table), [:set, :public, :named_table, read_concurrency: true])
    end

    # Load data
    load_all_data()

    {:ok, %{}}
  end

  @impl true
  def handle_call(:reload, _from, state) do
    load_all_data()
    {:reply, :ok, state}
  end

  # Private functions

  defp table_name(table), do: :"bezgelor_data_#{table}"

  defp load_all_data do
    Logger.info("Loading game data...")

    # Compile all data files if needed
    case Compiler.compile_all() do
      :ok -> Logger.debug("Data compilation complete")
      {:error, reason} -> Logger.warning("Compilation issue: #{inspect(reason)}")
    end

    # Load each table
    load_table(:creatures, "creatures.json", "creatures")
    load_table(:zones, "zones.json", "zones")
    load_table(:spells, "spells.json", "spells")
    load_table(:items, "items.json", "items")
    load_table(:texts, "texts.json", "texts")
    load_table(:house_types, "house_types.json", "house_types")
    load_table(:housing_decor, "housing_decor.json", "decor")
    load_table(:housing_fabkits, "housing_fabkits.json", "fabkits")
    load_table(:titles, "titles.json", "titles")

    # Tradeskill data
    load_table(:tradeskill_professions, "tradeskill_professions.json", "professions")
    load_table(:tradeskill_schematics, "tradeskill_schematics.json", "schematics")
    load_table(:tradeskill_talents, "tradeskill_talents.json", "talents")
    load_table(:tradeskill_additives, "tradeskill_additives.json", "additives")
    load_table(:tradeskill_nodes, "tradeskill_nodes.json", "node_types")
    load_table(:tradeskill_work_orders, "tradeskill_work_orders.json", "work_order_templates")

    # Public events data
    load_table(:public_events, "public_events.json", "public_events")
    load_table(:world_bosses, "world_bosses.json", "world_bosses")
    load_table_by_zone(:event_spawn_points, "event_spawn_points.json", "event_spawn_points")
    load_table(:event_loot_tables, "event_loot_tables.json", "event_loot_tables")

    # Instance/dungeon data
    load_table(:instances, "instances.json", "instances")
    load_table(:instance_bosses, "instance_bosses.json", "instance_bosses")
    load_mythic_affixes()

    # PvP data
    load_battlegrounds()
    load_arenas()
    load_warplot_plugs()

    # Spawn data
    load_creature_spawns()

    Logger.info("Game data loaded: #{inspect(stats())}")
  end

  defp load_table(table, json_file, key) do
    table_name = table_name(table)

    # Clear existing data
    :ets.delete_all_objects(table_name)

    case Compiler.load_data(json_file, key) do
      {:ok, items} when is_list(items) ->
        # Regular tables have lists of maps with :id
        for item <- items do
          :ets.insert(table_name, {item.id, item})
        end

        Logger.debug("Loaded #{length(items)} #{key}")

      {:ok, items} when is_map(items) ->
        # Texts table is a map of id -> string
        # Keys may be atoms (from :keys => :atoms) or strings
        for {id, text} <- items do
          int_id =
            cond do
              is_integer(id) -> id
              is_binary(id) -> String.to_integer(id)
              is_atom(id) -> id |> Atom.to_string() |> String.to_integer()
            end

          :ets.insert(table_name, {int_id, text})
        end

        Logger.debug("Loaded #{map_size(items)} #{key}")

      {:error, reason} ->
        Logger.warning("Failed to load #{key}: #{inspect(reason)}")
    end
  end

  defp load_table_by_zone(table, json_file, key) do
    table_name = table_name(table)

    # Clear existing data
    :ets.delete_all_objects(table_name)

    case Compiler.load_data(json_file, key) do
      {:ok, items} when is_list(items) ->
        # Items are indexed by zone_id
        for item <- items do
          :ets.insert(table_name, {item.zone_id, item})
        end

        Logger.debug("Loaded #{length(items)} #{key}")

      {:error, reason} ->
        Logger.warning("Failed to load #{key}: #{inspect(reason)}")
    end
  end

  defp load_mythic_affixes do
    table_name = table_name(:mythic_affixes)

    # Clear existing data
    :ets.delete_all_objects(table_name)

    json_path = Path.join(data_directory(), "mythic_affixes.json")

    case load_json_raw(json_path) do
      {:ok, data} ->
        # Load individual affixes
        affixes = Map.get(data, :mythic_affixes, [])

        for affix <- affixes do
          :ets.insert(table_name, {affix.id, affix})
        end

        # Store weekly rotation as metadata
        if rotation_data = Map.get(data, :weekly_rotation) do
          rotations = Map.get(rotation_data, :rotations, [])
          :ets.insert(table_name, {:weekly_rotation, rotations})
        end

        Logger.debug("Loaded #{length(affixes)} mythic affixes")

      {:error, reason} ->
        Logger.warning("Failed to load mythic affixes: #{inspect(reason)}")
    end
  end

  defp load_json_raw(path) do
    with {:ok, content} <- File.read(path),
         {:ok, data} <- Jason.decode(content, keys: :atoms) do
      {:ok, data}
    end
  end

  defp load_battlegrounds do
    table_name = table_name(:battlegrounds)

    # Clear existing data
    :ets.delete_all_objects(table_name)

    json_path = Path.join(data_directory(), "battlegrounds.json")

    case load_json_raw(json_path) do
      {:ok, data} ->
        # Load regular battlegrounds
        battlegrounds = Map.get(data, :battlegrounds, [])

        for bg <- battlegrounds do
          :ets.insert(table_name, {bg.id, bg})
        end

        # Load rated battlegrounds (with offset IDs starting at 100)
        rated_bgs = Map.get(data, :rated_battlegrounds, [])

        for rbg <- rated_bgs do
          :ets.insert(table_name, {rbg.id, rbg})
        end

        Logger.debug("Loaded #{length(battlegrounds) + length(rated_bgs)} battlegrounds")

      {:error, reason} ->
        Logger.warning("Failed to load battlegrounds: #{inspect(reason)}")
    end
  end

  defp load_arenas do
    table_name = table_name(:arenas)

    # Clear existing data
    :ets.delete_all_objects(table_name)

    json_path = Path.join(data_directory(), "arenas.json")

    case load_json_raw(json_path) do
      {:ok, data} ->
        # Load arena definitions
        arenas = Map.get(data, :arenas, [])

        for arena <- arenas do
          :ets.insert(table_name, {arena.id, arena})
        end

        # Store bracket configuration as metadata
        if brackets = Map.get(data, :brackets) do
          :ets.insert(table_name, {:brackets, brackets})
        end

        # Store rating rewards as metadata
        if rating_rewards = Map.get(data, :rating_rewards) do
          :ets.insert(table_name, {:rating_rewards, rating_rewards})
        end

        Logger.debug("Loaded #{length(arenas)} arenas")

      {:error, reason} ->
        Logger.warning("Failed to load arenas: #{inspect(reason)}")
    end
  end

  defp load_warplot_plugs do
    table_name = table_name(:warplot_plugs)

    # Clear existing data
    :ets.delete_all_objects(table_name)

    json_path = Path.join(data_directory(), "warplot_plugs.json")

    case load_json_raw(json_path) do
      {:ok, data} ->
        # Load plug definitions
        plugs = Map.get(data, :plugs, [])

        for plug <- plugs do
          :ets.insert(table_name, {plug.id, plug})
        end

        # Store categories as metadata
        if categories = Map.get(data, :categories) do
          :ets.insert(table_name, {:categories, categories})
        end

        # Store socket layout as metadata
        if socket_layout = Map.get(data, :socket_layout) do
          :ets.insert(table_name, {:socket_layout, socket_layout})
        end

        # Store warplot settings as metadata
        if warplot_settings = Map.get(data, :warplot_settings) do
          :ets.insert(table_name, {:warplot_settings, warplot_settings})
        end

        Logger.debug("Loaded #{length(plugs)} warplot plugs")

      {:error, reason} ->
        Logger.warning("Failed to load warplot plugs: #{inspect(reason)}")
    end
  end

  defp load_creature_spawns do
    table_name = table_name(:creature_spawns)

    # Clear existing data
    :ets.delete_all_objects(table_name)

    json_path = Path.join(data_directory(), "creature_spawns.json")

    case load_json_raw(json_path) do
      {:ok, data} ->
        # Load zone spawn data, keyed by world_id
        zone_spawns = Map.get(data, :zone_spawns, [])

        for zone_data <- zone_spawns do
          world_id = zone_data.world_id
          :ets.insert(table_name, {world_id, zone_data})
        end

        total_creatures =
          Enum.reduce(zone_spawns, 0, fn z, acc -> acc + length(z.creature_spawns) end)

        total_resources =
          Enum.reduce(zone_spawns, 0, fn z, acc -> acc + length(z.resource_spawns) end)

        total_objects =
          Enum.reduce(zone_spawns, 0, fn z, acc -> acc + length(z.object_spawns) end)

        Logger.debug(
          "Loaded #{length(zone_spawns)} zone spawn data (#{total_creatures} creatures, #{total_resources} resources, #{total_objects} objects)"
        )

      {:error, reason} ->
        Logger.warning("Failed to load creature spawns: #{inspect(reason)}")
    end
  end

  defp data_directory do
    Application.app_dir(:bezgelor_data, "priv/data")
  end

  defp stats do
    for table <- @tables, into: %{} do
      {table, count(table)}
    end
  end
end
