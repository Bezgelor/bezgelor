defmodule BezgelorDb.Inventory do
  @moduledoc """
  Inventory management context.

  ## Overview

  Manages character inventory including:
  - Adding/removing items with auto-stacking
  - Moving items between slots
  - Bag management
  - Equipment handling

  ## Auto-Stacking

  When adding stackable items, the system automatically:
  1. Finds existing stacks of the same item
  2. Fills partial stacks up to max_stack
  3. Creates new stacks in empty slots for overflow
  """

  import Ecto.Query
  alias BezgelorDb.Repo
  alias BezgelorDb.Schema.{Bag, InventoryItem}

  @default_backpack_size 16
  @max_bag_slots 4
  @max_bank_bags 6

  # Bag Management

  @doc "Get all bags for a character."
  @spec get_bags(integer()) :: [Bag.t()]
  def get_bags(character_id) do
    Bag
    |> where([b], b.character_id == ^character_id)
    |> order_by([b], b.bag_index)
    |> Repo.all()
  end

  @doc "Get a specific bag."
  @spec get_bag(integer(), integer()) :: Bag.t() | nil
  def get_bag(character_id, bag_index) do
    Repo.get_by(Bag, character_id: character_id, bag_index: bag_index)
  end

  @doc "Initialize character bags (create backpack)."
  @spec init_bags(integer()) :: {:ok, Bag.t()} | {:error, term()}
  def init_bags(character_id) do
    %Bag{}
    |> Bag.changeset(%{
      character_id: character_id,
      bag_index: 0,
      size: @default_backpack_size
    })
    |> Repo.insert()
  end

  @doc "Equip a bag in a slot."
  @spec equip_bag(integer(), integer(), integer(), integer()) ::
          {:ok, Bag.t()} | {:error, term()}
  def equip_bag(character_id, bag_index, item_id, size) when bag_index in 1..@max_bag_slots do
    case get_bag(character_id, bag_index) do
      nil ->
        %Bag{}
        |> Bag.changeset(%{
          character_id: character_id,
          bag_index: bag_index,
          item_id: item_id,
          size: size
        })
        |> Repo.insert()

      existing ->
        existing
        |> Bag.changeset(%{item_id: item_id, size: size})
        |> Repo.update()
    end
  end

  @doc "Get total bag capacity for a character."
  @spec total_capacity(integer()) :: integer()
  def total_capacity(character_id) do
    Bag
    |> where([b], b.character_id == ^character_id)
    |> Repo.aggregate(:sum, :size) || @default_backpack_size
  end

  # Item Management

  @doc "Get all items in character inventory."
  @spec get_items(integer()) :: [InventoryItem.t()]
  def get_items(character_id) do
    InventoryItem
    |> where([i], i.character_id == ^character_id)
    |> order_by([i], [i.container_type, i.bag_index, i.slot])
    |> Repo.all()
  end

  @doc "Get items in a specific container."
  @spec get_items(integer(), atom()) :: [InventoryItem.t()]
  def get_items(character_id, container_type) do
    InventoryItem
    |> where([i], i.character_id == ^character_id and i.container_type == ^container_type)
    |> order_by([i], [i.bag_index, i.slot])
    |> Repo.all()
  end

  @doc "Get item at a specific location."
  @spec get_item_at(integer(), atom(), integer(), integer()) :: InventoryItem.t() | nil
  def get_item_at(character_id, container_type, bag_index, slot) do
    Repo.get_by(InventoryItem,
      character_id: character_id,
      container_type: container_type,
      bag_index: bag_index,
      slot: slot
    )
  end

  @doc """
  Add item to inventory with auto-stacking.

  Returns {:ok, items} where items is list of affected items,
  or {:error, :inventory_full} if no space.
  """
  @spec add_item(integer(), integer(), integer(), map()) ::
          {:ok, [InventoryItem.t()]} | {:error, :inventory_full | term()}
  def add_item(character_id, item_id, quantity, opts \\ %{}) do
    max_stack = Map.get(opts, :max_stack, 1)
    container_type = Map.get(opts, :container_type, :bag)

    Repo.transaction(fn ->
      remaining = add_to_existing_stacks(character_id, item_id, quantity, max_stack, container_type)

      if remaining > 0 do
        case create_new_stacks(character_id, item_id, remaining, max_stack, container_type, opts) do
          {:ok, items} -> items
          {:error, reason} -> Repo.rollback(reason)
        end
      else
        # All added to existing stacks
        []
      end
    end)
  end

  @doc "Remove quantity of an item from inventory."
  @spec remove_item(integer(), integer(), integer()) ::
          {:ok, integer()} | {:error, :insufficient_quantity}
  def remove_item(character_id, item_id, quantity) do
    items =
      InventoryItem
      |> where([i], i.character_id == ^character_id and i.item_id == ^item_id)
      |> order_by([i], asc: i.quantity)  # Remove from smallest stacks first
      |> Repo.all()

    total_available = Enum.sum(Enum.map(items, & &1.quantity))

    if total_available < quantity do
      {:error, :insufficient_quantity}
    else
      Repo.transaction(fn ->
        do_remove_quantity(items, quantity)
      end)
    end
  end

  @doc "Remove a specific item instance."
  @spec remove_item_at(integer(), atom(), integer(), integer()) ::
          {:ok, InventoryItem.t()} | {:error, :not_found}
  def remove_item_at(character_id, container_type, bag_index, slot) do
    case get_item_at(character_id, container_type, bag_index, slot) do
      nil -> {:error, :not_found}
      item -> Repo.delete(item)
    end
  end

  @doc "Move item to a new location."
  @spec move_item(InventoryItem.t(), atom(), integer(), integer()) ::
          {:ok, InventoryItem.t()} | {:error, :slot_occupied | term()}
  def move_item(item, container_type, bag_index, slot) do
    # Check if destination is occupied
    case get_item_at(item.character_id, container_type, bag_index, slot) do
      nil ->
        item
        |> InventoryItem.move_changeset(%{
          container_type: container_type,
          bag_index: bag_index,
          slot: slot
        })
        |> Repo.update()

      _existing ->
        {:error, :slot_occupied}
    end
  end

  @doc "Swap two items."
  @spec swap_items(InventoryItem.t(), InventoryItem.t()) ::
          {:ok, {InventoryItem.t(), InventoryItem.t()}} | {:error, term()}
  def swap_items(item1, item2) do
    Repo.transaction(fn ->
      # Store original locations
      loc1 = {item1.container_type, item1.bag_index, item1.slot}
      loc2 = {item2.container_type, item2.bag_index, item2.slot}

      # Move item1 to temporary location
      {:ok, item1} =
        item1
        |> InventoryItem.move_changeset(%{container_type: :trade, bag_index: 99, slot: 0})
        |> Repo.update()

      # Move item2 to item1's original location
      {:ok, item2} =
        item2
        |> InventoryItem.move_changeset(%{
          container_type: elem(loc1, 0),
          bag_index: elem(loc1, 1),
          slot: elem(loc1, 2)
        })
        |> Repo.update()

      # Move item1 to item2's original location
      {:ok, item1} =
        item1
        |> InventoryItem.move_changeset(%{
          container_type: elem(loc2, 0),
          bag_index: elem(loc2, 1),
          slot: elem(loc2, 2)
        })
        |> Repo.update()

      {item1, item2}
    end)
  end

  @doc "Stack items if possible."
  @spec stack_items(InventoryItem.t(), InventoryItem.t()) ::
          {:ok, {InventoryItem.t() | nil, InventoryItem.t()}} | {:error, :cannot_stack}
  def stack_items(source, target) do
    cond do
      source.item_id != target.item_id ->
        {:error, :cannot_stack}

      target.quantity >= target.max_stack ->
        {:error, :cannot_stack}

      true ->
        space_in_target = target.max_stack - target.quantity
        to_transfer = min(source.quantity, space_in_target)

        Repo.transaction(fn ->
          # Add to target
          {:ok, target} =
            target
            |> InventoryItem.stack_changeset(%{quantity: target.quantity + to_transfer})
            |> Repo.update()

          # Remove from source
          if source.quantity <= to_transfer do
            {:ok, _} = Repo.delete(source)
            {nil, target}
          else
            {:ok, source} =
              source
              |> InventoryItem.stack_changeset(%{quantity: source.quantity - to_transfer})
              |> Repo.update()

            {source, target}
          end
        end)
    end
  end

  @doc "Count total quantity of an item in inventory."
  @spec count_item(integer(), integer()) :: integer()
  def count_item(character_id, item_id) do
    InventoryItem
    |> where([i], i.character_id == ^character_id and i.item_id == ^item_id)
    |> Repo.aggregate(:sum, :quantity) || 0
  end

  @doc "Check if character has at least quantity of an item."
  @spec has_item?(integer(), integer(), integer()) :: boolean()
  def has_item?(character_id, item_id, quantity \\ 1) do
    count_item(character_id, item_id) >= quantity
  end

  @doc "Find first empty slot in bags."
  @spec find_empty_slot(integer(), atom()) :: {integer(), integer()} | nil
  def find_empty_slot(character_id, container_type \\ :bag) do
    bags = get_bags(character_id)

    bags
    |> Enum.filter(fn bag ->
      case container_type do
        :bag -> bag.bag_index <= @max_bag_slots
        :bank -> bag.bag_index > @max_bag_slots
        _ -> true
      end
    end)
    |> Enum.find_value(fn bag ->
      occupied_slots =
        InventoryItem
        |> where([i],
          i.character_id == ^character_id and
          i.container_type == ^container_type and
          i.bag_index == ^bag.bag_index
        )
        |> select([i], i.slot)
        |> Repo.all()
        |> MapSet.new()

      empty_slot =
        0..(bag.size - 1)
        |> Enum.find(fn slot -> slot not in occupied_slots end)

      if empty_slot, do: {bag.bag_index, empty_slot}
    end)
  end

  # Private Functions

  defp add_to_existing_stacks(character_id, item_id, quantity, max_stack, container_type) do
    if max_stack <= 1 do
      quantity
    else
      # Find existing partial stacks
      partial_stacks =
        InventoryItem
        |> where([i],
          i.character_id == ^character_id and
          i.item_id == ^item_id and
          i.container_type == ^container_type and
          i.quantity < i.max_stack
        )
        |> order_by([i], desc: i.quantity)  # Fill fullest stacks first
        |> Repo.all()

      Enum.reduce_while(partial_stacks, quantity, fn stack, remaining ->
        if remaining <= 0 do
          {:halt, 0}
        else
          space = stack.max_stack - stack.quantity
          to_add = min(remaining, space)

          {:ok, _} =
            stack
            |> InventoryItem.stack_changeset(%{quantity: stack.quantity + to_add})
            |> Repo.update()

          {:cont, remaining - to_add}
        end
      end)
    end
  end

  defp create_new_stacks(character_id, item_id, quantity, max_stack, container_type, opts) do
    stacks_needed = ceil(quantity / max_stack)

    items =
      Enum.reduce_while(1..stacks_needed, {quantity, []}, fn _i, {remaining, acc} ->
        case find_empty_slot(character_id, container_type) do
          nil ->
            {:halt, {:error, :inventory_full}}

          {bag_index, slot} ->
            stack_size = min(remaining, max_stack)

            attrs =
              Map.merge(opts, %{
                character_id: character_id,
                item_id: item_id,
                container_type: container_type,
                bag_index: bag_index,
                slot: slot,
                quantity: stack_size,
                max_stack: max_stack
              })

            case %InventoryItem{} |> InventoryItem.changeset(attrs) |> Repo.insert() do
              {:ok, item} ->
                {:cont, {remaining - stack_size, [item | acc]}}

              {:error, _} = err ->
                {:halt, err}
            end
        end
      end)

    case items do
      {:error, _} = err -> err
      {_remaining, item_list} -> {:ok, Enum.reverse(item_list)}
    end
  end

  defp do_remove_quantity(items, quantity) do
    {removed, _} =
      Enum.reduce_while(items, {0, quantity}, fn item, {total_removed, remaining} ->
        if remaining <= 0 do
          {:halt, {total_removed, 0}}
        else
          to_remove = min(item.quantity, remaining)

          if to_remove >= item.quantity do
            {:ok, _} = Repo.delete(item)
          else
            {:ok, _} =
              item
              |> InventoryItem.stack_changeset(%{quantity: item.quantity - to_remove})
              |> Repo.update()
          end

          {:cont, {total_removed + to_remove, remaining - to_remove}}
        end
      end)

    removed
  end
end
