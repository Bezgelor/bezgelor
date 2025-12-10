defmodule BezgelorCore.Loot do
  @moduledoc """
  Loot table definitions and roll mechanics.

  Loot tables define what items can drop from creatures.
  Each entry has a chance to drop and a quantity range.

  ## Loot Entry Structure

  - `item_id` - The item template ID
  - `chance` - Drop chance (1-100)
  - `min` - Minimum quantity
  - `max` - Maximum quantity

  ## Special Items

  - Item ID 0 is reserved for gold/currency drops
  """

  @type loot_entry :: %{
          item_id: non_neg_integer(),
          chance: 1..100,
          min: pos_integer(),
          max: pos_integer()
        }

  @type t :: %__MODULE__{
          id: non_neg_integer(),
          entries: [loot_entry()]
        }

  defstruct [
    :id,
    entries: []
  ]

  @doc """
  Get a loot table by ID.
  """
  @spec get(non_neg_integer()) :: t() | nil
  def get(id), do: Map.get(tables(), id)

  @doc """
  Check if a loot table exists.
  """
  @spec exists?(non_neg_integer()) :: boolean()
  def exists?(id), do: Map.has_key?(tables(), id)

  @doc """
  Roll loot from a table.

  Returns a list of {item_id, quantity} tuples for items that dropped.
  """
  @spec roll(non_neg_integer()) :: [{non_neg_integer(), non_neg_integer()}]
  def roll(table_id) do
    case get(table_id) do
      nil ->
        []

      %__MODULE__{entries: entries} ->
        entries
        |> Enum.filter(&roll_chance?/1)
        |> Enum.map(&roll_quantity/1)
    end
  end

  @doc """
  Roll loot directly from a loot table struct.
  """
  @spec roll_table(t()) :: [{non_neg_integer(), non_neg_integer()}]
  def roll_table(%__MODULE__{entries: entries}) do
    entries
    |> Enum.filter(&roll_chance?/1)
    |> Enum.map(&roll_quantity/1)
  end

  defp roll_chance?(%{chance: chance}) do
    :rand.uniform(100) <= chance
  end

  defp roll_quantity(%{item_id: item_id, min: min_qty, max: max_qty}) do
    quantity = if min_qty == max_qty, do: min_qty, else: Enum.random(min_qty..max_qty)
    {item_id, quantity}
  end

  @doc """
  Get total gold value from loot drops.

  Gold is represented by item_id 0.
  """
  @spec gold_from_drops([{non_neg_integer(), non_neg_integer()}]) :: non_neg_integer()
  def gold_from_drops(drops) do
    drops
    |> Enum.filter(fn {item_id, _} -> item_id == 0 end)
    |> Enum.reduce(0, fn {_, amount}, acc -> acc + amount end)
  end

  @doc """
  Get non-gold items from loot drops.
  """
  @spec items_from_drops([{non_neg_integer(), non_neg_integer()}]) ::
          [{non_neg_integer(), non_neg_integer()}]
  def items_from_drops(drops) do
    Enum.reject(drops, fn {item_id, _} -> item_id == 0 end)
  end

  @doc """
  Check if drops contain any items.
  """
  @spec has_items?([{non_neg_integer(), non_neg_integer()}]) :: boolean()
  def has_items?(drops), do: items_from_drops(drops) != []

  @doc """
  Check if drops contain gold.
  """
  @spec has_gold?([{non_neg_integer(), non_neg_integer()}]) :: boolean()
  def has_gold?(drops), do: gold_from_drops(drops) > 0

  # Test loot tables
  defp tables do
    %{
      # Forest Wolf loot
      1 => %__MODULE__{
        id: 1,
        entries: [
          # Gold (always drops 1-5)
          %{item_id: 0, chance: 100, min: 1, max: 5},
          # Wolf Pelt (50% chance)
          %{item_id: 101, chance: 50, min: 1, max: 1},
          # Wolf Fang (25% chance)
          %{item_id: 102, chance: 25, min: 1, max: 2}
        ]
      },
      # Cave Spider loot
      2 => %__MODULE__{
        id: 2,
        entries: [
          # Gold (always drops 2-8)
          %{item_id: 0, chance: 100, min: 2, max: 8},
          # Spider Silk (75% chance)
          %{item_id: 201, chance: 75, min: 1, max: 3},
          # Spider Venom Sac (30% chance)
          %{item_id: 202, chance: 30, min: 1, max: 1},
          # Rare: Spider Eye (5% chance)
          %{item_id: 203, chance: 5, min: 1, max: 1}
        ]
      },
      # Generic trash mob loot
      3 => %__MODULE__{
        id: 3,
        entries: [
          # Gold (always drops 1-3)
          %{item_id: 0, chance: 100, min: 1, max: 3}
        ]
      }
    }
  end
end
