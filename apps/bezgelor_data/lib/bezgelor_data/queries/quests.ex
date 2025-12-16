defmodule BezgelorData.Queries.Quests do
  @moduledoc """
  Query functions for quest data: quests, objectives, rewards, NPCs, vendors, gossip.
  """

  alias BezgelorData.Store

  # Quest queries

  @doc """
  Get a quest definition by ID.
  """
  @spec get_quest(non_neg_integer()) :: {:ok, map()} | :error
  def get_quest(id), do: Store.get(:quests, id)

  @doc """
  Get all quests for a zone.
  Uses secondary index for O(1) lookup.
  """
  @spec get_quests_for_zone(non_neg_integer()) :: [map()]
  def get_quests_for_zone(zone_id) do
    ids = Store.lookup_index(:quests_by_zone, zone_id)
    Store.fetch_by_ids(:quests, ids)
  end

  @doc """
  Get all quests of a specific type.
  """
  @spec get_quests_by_type(non_neg_integer()) :: [map()]
  def get_quests_by_type(type) do
    Store.list(:quests)
    |> Enum.filter(fn q -> q.type == type end)
  end

  @doc """
  Get a quest objective by ID.
  """
  @spec get_quest_objective(non_neg_integer()) :: {:ok, map()} | :error
  def get_quest_objective(id), do: Store.get(:quest_objectives, id)

  @doc """
  Get quest rewards by quest ID.
  Uses secondary index for O(1) lookup.
  """
  @spec get_quest_rewards(non_neg_integer()) :: [map()]
  def get_quest_rewards(quest_id) do
    ids = Store.lookup_index(:quest_rewards_by_quest, quest_id)
    Store.fetch_by_ids(:quest_rewards, ids)
  end

  @doc """
  Get a quest category by ID.
  """
  @spec get_quest_category(non_neg_integer()) :: {:ok, map()} | :error
  def get_quest_category(id), do: Store.get(:quest_categories, id)

  @doc """
  Get a quest hub by ID.
  """
  @spec get_quest_hub(non_neg_integer()) :: {:ok, map()} | :error
  def get_quest_hub(id), do: Store.get(:quest_hubs, id)

  @doc """
  Get quest IDs that a creature can give.
  Extracts non-zero questIdGiven00-24 fields from the full creature record.
  """
  @spec get_quests_for_creature_giver(non_neg_integer()) :: [non_neg_integer()]
  def get_quests_for_creature_giver(creature_id) do
    case get_creature_full(creature_id) do
      {:ok, creature} ->
        0..24
        |> Enum.map(fn i ->
          key = String.to_atom("questIdGiven#{String.pad_leading(Integer.to_string(i), 2, "0")}")
          Map.get(creature, key)
        end)
        |> Enum.reject(&(&1 == 0 or is_nil(&1)))

      :error ->
        []
    end
  end

  @doc """
  Get quest IDs that a creature can receive turn-ins for.
  Extracts non-zero questIdReceive00-24 fields from the full creature record.
  """
  @spec get_quests_for_creature_receiver(non_neg_integer()) :: [non_neg_integer()]
  def get_quests_for_creature_receiver(creature_id) do
    case get_creature_full(creature_id) do
      {:ok, creature} ->
        0..24
        |> Enum.map(fn i ->
          key = String.to_atom("questIdReceive#{String.pad_leading(Integer.to_string(i), 2, "0")}")
          Map.get(creature, key)
        end)
        |> Enum.reject(&(&1 == 0 or is_nil(&1)))

      :error ->
        []
    end
  end

  @doc """
  Get quest definition with all objective definitions included.
  Joins the quest with its objectives based on objective0-5 fields.
  """
  @spec get_quest_with_objectives(non_neg_integer()) :: {:ok, map()} | :error
  def get_quest_with_objectives(quest_id) do
    case Store.get(:quests, quest_id) do
      {:ok, quest} ->
        objectives =
          0..5
          |> Enum.map(fn i ->
            key = String.to_atom("objective#{i}")
            Map.get(quest, key)
          end)
          |> Enum.reject(&(&1 == 0 or is_nil(&1)))
          |> Enum.map(&Store.get(:quest_objectives, &1))
          |> Enum.filter(&match?({:ok, _}, &1))
          |> Enum.map(fn {:ok, obj} -> obj end)

        {:ok, Map.put(quest, :objectives, objectives)}

      :error ->
        :error
    end
  end

  @doc """
  Check if creature is a quest giver.
  """
  @spec creature_quest_giver?(non_neg_integer()) :: boolean()
  def creature_quest_giver?(creature_id) do
    get_quests_for_creature_giver(creature_id) != []
  end

  @doc """
  Check if creature is a quest receiver (turn-in NPC).
  """
  @spec creature_quest_receiver?(non_neg_integer()) :: boolean()
  def creature_quest_receiver?(creature_id) do
    get_quests_for_creature_receiver(creature_id) != []
  end

  # NPC/Vendor queries

  @doc """
  Get vendor data by vendor ID.
  """
  @spec get_vendor(non_neg_integer()) :: {:ok, map()} | :error
  def get_vendor(id), do: Store.get(:npc_vendors, id)

  @doc """
  Get vendor by creature ID.
  Uses secondary index for O(1) lookup.
  """
  @spec get_vendor_by_creature(non_neg_integer()) :: {:ok, map()} | :error
  def get_vendor_by_creature(creature_id) do
    case Store.lookup_index(:vendors_by_creature, creature_id) do
      [id | _] -> Store.get(:npc_vendors, id)
      [] -> :error
    end
  end

  @doc """
  Get all vendors of a specific type.
  Uses secondary index for O(1) lookup.
  """
  @spec get_vendors_by_type(String.t()) :: [map()]
  def get_vendors_by_type(vendor_type) do
    ids = Store.lookup_index(:vendors_by_type, vendor_type)
    Store.fetch_by_ids(:npc_vendors, ids)
  end

  @doc """
  Get all vendors.
  """
  @spec get_all_vendors() :: [map()]
  def get_all_vendors, do: Store.list(:npc_vendors)

  @doc """
  Get vendor inventory by vendor ID.
  """
  @spec get_vendor_inventory(non_neg_integer()) :: {:ok, map()} | :error
  def get_vendor_inventory(vendor_id), do: Store.get(:vendor_inventories, vendor_id)

  @doc """
  Get vendor inventory items for a creature.
  Returns the list of items the vendor sells, or empty list if not a vendor.
  """
  @spec get_vendor_items_for_creature(non_neg_integer()) :: [map()]
  def get_vendor_items_for_creature(creature_id) do
    case get_vendor_by_creature(creature_id) do
      {:ok, vendor} ->
        case get_vendor_inventory(vendor.id) do
          {:ok, inventory} -> inventory.items
          :error -> []
        end

      :error ->
        []
    end
  end

  @doc """
  Get creature affiliation by ID.
  """
  @spec get_creature_affiliation(non_neg_integer()) :: {:ok, map()} | :error
  def get_creature_affiliation(id), do: Store.get(:creature_affiliations, id)

  @doc """
  Get full creature data by ID.
  Returns complete creature2 record with all 173 fields.
  """
  @spec get_creature_full(non_neg_integer()) :: {:ok, map()} | :error
  def get_creature_full(id), do: Store.get(:creatures_full, id)

  # Gossip/Dialogue queries

  @doc """
  Get a gossip entry by ID.
  """
  @spec get_gossip_entry(non_neg_integer()) :: {:ok, map()} | :error
  def get_gossip_entry(id), do: Store.get(:gossip_entries, id)

  @doc """
  Get gossip entries for a gossip set.
  Uses secondary index for O(1) lookup.
  """
  @spec get_gossip_entries_for_set(non_neg_integer()) :: [map()]
  def get_gossip_entries_for_set(set_id) do
    ids = Store.lookup_index(:gossip_entries_by_set, set_id)
    Store.fetch_by_ids(:gossip_entries, ids)
  end

  @doc """
  Get a gossip set by ID.
  """
  @spec get_gossip_set(non_neg_integer()) :: {:ok, map()} | :error
  def get_gossip_set(id), do: Store.get(:gossip_sets, id)
end
