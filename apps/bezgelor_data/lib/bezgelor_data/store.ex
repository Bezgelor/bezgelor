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
    :event_spawn_points
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

  defp stats do
    for table <- @tables, into: %{} do
      {table, count(table)}
    end
  end
end
