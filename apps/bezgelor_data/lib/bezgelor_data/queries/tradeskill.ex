defmodule BezgelorData.Queries.Tradeskill do
  @moduledoc """
  Query functions for tradeskill data: professions, schematics, talents, etc.
  """

  alias BezgelorData.Store

  # Profession queries

  @doc """
  Get a profession by ID.
  """
  @spec get_profession(non_neg_integer()) :: {:ok, map()} | :error
  def get_profession(id), do: Store.get(:tradeskill_professions, id)

  @doc """
  Get all professions of a specific type.
  """
  @spec get_professions_by_type(atom()) :: [map()]
  def get_professions_by_type(type) when type in [:crafting, :gathering] do
    type_str = Atom.to_string(type)

    Store.list(:tradeskill_professions)
    |> Enum.filter(fn p -> p.type == type_str end)
  end

  # Schematic queries

  @doc """
  Get a schematic by ID.
  """
  @spec get_schematic(non_neg_integer()) :: {:ok, map()} | :error
  def get_schematic(id), do: Store.get(:tradeskill_schematics, id)

  @doc """
  Get all schematics for a profession.

  Uses secondary index for O(1) lookup instead of scanning all schematics.
  """
  @spec get_schematics_for_profession(non_neg_integer()) :: [map()]
  def get_schematics_for_profession(profession_id) do
    ids = Store.lookup_index(:schematics_by_profession, profession_id)
    Store.fetch_by_ids(:tradeskill_schematics, ids)
  end

  @doc """
  Get schematics available at a skill level.
  """
  @spec get_available_schematics(non_neg_integer(), non_neg_integer()) :: [map()]
  def get_available_schematics(profession_id, skill_level) do
    Store.list(:tradeskill_schematics)
    |> Enum.filter(fn s ->
      s.profession_id == profession_id and s.min_level <= skill_level
    end)
  end

  # Talent queries

  @doc """
  Get a talent by ID.
  """
  @spec get_talent(non_neg_integer()) :: {:ok, map()} | :error
  def get_talent(id), do: Store.get(:tradeskill_talents, id)

  @doc """
  Get all talents for a profession.

  Uses secondary index for O(1) lookup instead of scanning all talents.
  """
  @spec get_talents_for_profession(non_neg_integer()) :: [map()]
  def get_talents_for_profession(profession_id) do
    ids = Store.lookup_index(:talents_by_profession, profession_id)

    Store.fetch_by_ids(:tradeskill_talents, ids)
    |> Enum.sort_by(fn t -> {t.tier, t.id} end)
  end

  # Additive queries

  @doc """
  Get an additive by ID.
  """
  @spec get_additive(non_neg_integer()) :: {:ok, map()} | :error
  def get_additive(id), do: Store.get(:tradeskill_additives, id)

  @doc """
  Get additive by item ID.
  """
  @spec get_additive_by_item(non_neg_integer()) :: {:ok, map()} | :error
  def get_additive_by_item(item_id) do
    case Enum.find(Store.list(:tradeskill_additives), fn a -> a.item_id == item_id end) do
      nil -> :error
      additive -> {:ok, additive}
    end
  end

  # Node type queries

  @doc """
  Get a node type by ID.
  """
  @spec get_node_type(non_neg_integer()) :: {:ok, map()} | :error
  def get_node_type(id), do: Store.get(:tradeskill_nodes, id)

  @doc """
  Get all node types for a profession.

  Uses secondary index for O(1) lookup instead of scanning all nodes.
  """
  @spec get_node_types_for_profession(non_neg_integer()) :: [map()]
  def get_node_types_for_profession(profession_id) do
    ids = Store.lookup_index(:nodes_by_profession, profession_id)
    Store.fetch_by_ids(:tradeskill_nodes, ids)
  end

  @doc """
  Get node types for a level range.
  """
  @spec get_node_types_for_level(non_neg_integer(), non_neg_integer()) :: [map()]
  def get_node_types_for_level(profession_id, level) do
    Store.list(:tradeskill_nodes)
    |> Enum.filter(fn n ->
      n.profession_id == profession_id and n.min_level <= level and n.max_level >= level
    end)
  end

  # Work order queries

  @doc """
  Get a work order template by ID.
  """
  @spec get_work_order_template(non_neg_integer()) :: {:ok, map()} | :error
  def get_work_order_template(id), do: Store.get(:tradeskill_work_orders, id)

  @doc """
  Get all work order templates for a profession.

  Uses secondary index for O(1) lookup instead of scanning all work orders.
  """
  @spec get_work_orders_for_profession(non_neg_integer()) :: [map()]
  def get_work_orders_for_profession(profession_id) do
    ids = Store.lookup_index(:work_orders_by_profession, profession_id)
    Store.fetch_by_ids(:tradeskill_work_orders, ids)
  end

  @doc """
  Get available work order templates at a skill level.
  """
  @spec get_available_work_orders(non_neg_integer(), non_neg_integer()) :: [map()]
  def get_available_work_orders(profession_id, skill_level) do
    Store.list(:tradeskill_work_orders)
    |> Enum.filter(fn wo ->
      wo.profession_id == profession_id and wo.min_level <= skill_level
    end)
  end
end
