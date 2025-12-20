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

  @doc """
  Ensure ability items exist for the character.

  Abilities are stored as items in the :ability container with bag_index
  set to the ability slot and slot set to 0.
  """
  @spec ensure_ability_items(integer(), [map()]) :: [InventoryItem.t()]
  def ensure_ability_items(character_id, abilities) when is_list(abilities) do
    Enum.each(abilities, fn ability ->
      attrs = %{
        character_id: character_id,
        item_id: ability.spell_id,
        container_type: :ability,
        bag_index: ability.slot,
        slot: 0,
        quantity: 1,
        max_stack: 1,
        durability: 100,
        max_durability: 100
      }

      %InventoryItem{}
      |> InventoryItem.changeset(attrs)
      |> Repo.insert(
        on_conflict: [
          set: [
            item_id: attrs.item_id,
            quantity: attrs.quantity,
            max_stack: attrs.max_stack,
            durability: attrs.durability,
            max_durability: attrs.max_durability
          ]
        ],
        conflict_target: [:character_id, :container_type, :bag_index, :slot]
      )
    end)

    get_items(character_id, :ability)
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
      remaining =
        add_to_existing_stacks(character_id, item_id, quantity, max_stack, container_type)

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
      # Remove from smallest stacks first
      |> order_by([i], asc: i.quantity)
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

  @doc """
  Admin function to remove a specific inventory item by its database ID.

  Requires both the character ID and the inventory item ID to ensure
  the item belongs to the correct character.
  """
  @spec admin_remove_item(integer(), integer()) ::
          {:ok, InventoryItem.t()} | {:error, :not_found}
  def admin_remove_item(character_id, inventory_item_id) do
    case Repo.get_by(InventoryItem, id: inventory_item_id, character_id: character_id) do
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

  @doc """
  Split a stack into two parts.

  Takes a source item and creates a new stack at the destination location
  with the specified quantity. Updates the source stack's quantity accordingly.

  ## Parameters
    - source_item: The item to split from
    - character_id: The character ID (for ownership verification)
    - quantity: Amount to split off to the new stack
    - dest_container: Destination container type
    - dest_bag_index: Destination bag index
    - dest_slot: Destination slot

  ## Returns
    - `{:ok, {updated_source, new_stack}}` on success
    - `{:error, :invalid_quantity}` if quantity is invalid
    - `{:error, :slot_occupied}` if destination is occupied
  """
  @spec split_stack(InventoryItem.t(), integer(), atom(), integer(), integer()) ::
          {:ok, {InventoryItem.t(), InventoryItem.t()}} | {:error, atom()}
  def split_stack(source_item, quantity, dest_container, dest_bag_index, dest_slot) do
    cond do
      quantity <= 0 or quantity >= source_item.quantity ->
        {:error, :invalid_quantity}

      get_item_at(source_item.character_id, dest_container, dest_bag_index, dest_slot) != nil ->
        {:error, :slot_occupied}

      true ->
        Repo.transaction(fn ->
          # Reduce source stack
          new_src_quantity = source_item.quantity - quantity

          {:ok, updated_source} =
            source_item
            |> InventoryItem.stack_changeset(%{quantity: new_src_quantity})
            |> Repo.update()

          # Create new stack at destination
          attrs = %{
            character_id: source_item.character_id,
            item_id: source_item.item_id,
            container_type: dest_container,
            bag_index: dest_bag_index,
            slot: dest_slot,
            quantity: quantity,
            max_stack: source_item.max_stack,
            durability: source_item.durability,
            bound: source_item.bound
          }

          {:ok, new_item} =
            %InventoryItem{}
            |> InventoryItem.changeset(attrs)
            |> Repo.insert()

          {updated_source, new_item}
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

  @doc """
  Find first empty slot in bags.

  Uses a single query with join to avoid N+1 queries.
  """
  @spec find_empty_slot(integer(), atom()) :: {integer(), integer()} | nil
  def find_empty_slot(character_id, container_type \\ :bag) do
    # Single query: get all bags and their occupied slots in one shot
    # This replaces the previous N+1 pattern (1 query for bags + N queries for items)
    query =
      from(b in Bag,
        left_join: i in InventoryItem,
        on:
          i.character_id == b.character_id and
            i.bag_index == b.bag_index and
            i.container_type == ^container_type,
        where: b.character_id == ^character_id,
        select: {b, i.slot}
      )

    results = Repo.all(query)

    # Group slots by bag
    bags_with_slots =
      results
      |> Enum.group_by(fn {bag, _slot} -> bag end, fn {_bag, slot} -> slot end)

    # Filter bags by container type and find first with empty slot
    bags_with_slots
    |> Enum.filter(fn {bag, _slots} ->
      case container_type do
        :bag -> bag.bag_index <= @max_bag_slots
        :bank -> bag.bag_index > @max_bag_slots
        _ -> true
      end
    end)
    |> Enum.sort_by(fn {bag, _slots} -> bag.bag_index end)
    |> Enum.find_value(fn {bag, slots} ->
      occupied_slots = slots |> Enum.reject(&is_nil/1) |> MapSet.new()

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
        |> where(
          [i],
          i.character_id == ^character_id and
            i.item_id == ^item_id and
            i.container_type == ^container_type and
            i.quantity < i.max_stack
        )
        # Fill fullest stacks first
        |> order_by([i], desc: i.quantity)
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

  # ============================================================================
  # Currency Management
  # ============================================================================

  alias BezgelorDb.Schema.CharacterCurrency

  @doc """
  Get all currencies for a character.

  Returns a list of currency maps with type, name, amount, and icon.
  Creates currency record if it doesn't exist.
  """
  @spec get_currencies(integer()) :: [map()]
  def get_currencies(character_id) do
    currency = get_or_create_currency(character_id)

    CharacterCurrency.currency_fields()
    |> Enum.map(fn field ->
      info = CharacterCurrency.currency_info(field)
      amount = Map.get(currency, field, 0)

      %{
        type: field,
        name: info.name,
        amount: amount,
        icon: info.icon,
        max: info[:max]
      }
    end)
  end

  @doc """
  Get or create a character's currency record.
  """
  @spec get_or_create_currency(integer()) :: CharacterCurrency.t()
  def get_or_create_currency(character_id) do
    case Repo.get_by(CharacterCurrency, character_id: character_id) do
      nil ->
        {:ok, currency} =
          %CharacterCurrency{}
          |> CharacterCurrency.changeset(%{character_id: character_id})
          |> Repo.insert()

        currency

      currency ->
        currency
    end
  end

  @doc """
  Modify a character's currency amount.

  ## Parameters

  - `character_id` - The character ID
  - `currency_type` - Currency type atom (e.g., :gold, :elder_gems)
  - `amount` - Amount to add (positive) or remove (negative)

  ## Returns

  - `{:ok, currency}` on success
  - `{:error, :insufficient_funds}` if trying to remove more than available
  - `{:error, :invalid_currency}` if currency type is invalid
  """
  @spec modify_currency(integer(), atom(), integer()) ::
          {:ok, CharacterCurrency.t()} | {:error, atom()}
  def modify_currency(character_id, currency_type, amount) when is_atom(currency_type) do
    if currency_type in CharacterCurrency.currency_fields() do
      currency = get_or_create_currency(character_id)

      case CharacterCurrency.modify_changeset(currency, currency_type, amount) do
        {:ok, changeset} -> Repo.update(changeset)
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :invalid_currency}
    end
  end

  # Support integer currency_id for backwards compatibility
  def modify_currency(character_id, currency_id, amount) when is_integer(currency_id) do
    # Map legacy integer IDs to currency types
    currency_type =
      case currency_id do
        1 -> :gold
        2 -> :elder_gems
        3 -> :renown
        4 -> :prestige
        5 -> :glory
        6 -> :crafting_vouchers
        7 -> :war_coins
        8 -> :shade_silver
        9 -> :protostar_promissory_notes
        _ -> nil
      end

    if currency_type do
      modify_currency(character_id, currency_type, amount)
    else
      {:error, :invalid_currency}
    end
  end

  @doc """
  Get a specific currency amount for a character.
  """
  @spec get_currency(integer(), atom()) :: integer()
  def get_currency(character_id, currency_type) when is_atom(currency_type) do
    currency = get_or_create_currency(character_id)
    Map.get(currency, currency_type, 0)
  end

  @doc """
  Add a specific amount of currency to a character.

  This is a convenience wrapper around `modify_currency/3` for adding currency.
  """
  @spec add_currency(integer(), atom(), non_neg_integer()) ::
          {:ok, CharacterCurrency.t()} | {:error, atom()}
  def add_currency(character_id, currency_type, amount)
      when is_atom(currency_type) and amount >= 0 do
    modify_currency(character_id, currency_type, amount)
  end

  @doc """
  Spend a specific amount of currency from a character.

  Returns `{:ok, currency}` if successful, `{:error, :insufficient_funds}` if
  the character doesn't have enough of that currency.
  """
  @spec spend_currency(integer(), atom(), non_neg_integer()) ::
          {:ok, CharacterCurrency.t()} | {:error, atom()}
  def spend_currency(character_id, currency_type, amount)
      when is_atom(currency_type) and amount >= 0 do
    current = get_currency(character_id, currency_type)

    if current >= amount do
      modify_currency(character_id, currency_type, -amount)
    else
      {:error, :insufficient_funds}
    end
  end

  # ============================================================================
  # Durability Management
  # ============================================================================

  @doc """
  Apply death durability loss to all equipped items.

  Reduces durability of equipped gear based on character level.
  Uses BezgelorCore.Death.durability_loss/1 to calculate percentage.

  Returns the number of items affected.
  """
  @spec apply_death_durability_loss(integer(), integer()) :: {:ok, non_neg_integer()}
  def apply_death_durability_loss(character_id, level) do
    loss_percent = BezgelorCore.Death.durability_loss(level)

    if loss_percent > 0 do
      # Get all equipped items
      equipped_items = get_items(character_id, :equipped)

      # Update each item's durability
      affected_count =
        Enum.reduce(equipped_items, 0, fn item, count ->
          if item.max_durability > 0 do
            durability_loss = round(item.max_durability * loss_percent / 100.0)
            new_durability = max(0, item.durability - durability_loss)

            {:ok, _} =
              item
              |> InventoryItem.changeset(%{durability: new_durability})
              |> Repo.update()

            count + 1
          else
            count
          end
        end)

      {:ok, affected_count}
    else
      {:ok, 0}
    end
  end

  @doc """
  Update durability for a specific item.
  """
  @spec update_durability(integer(), integer()) ::
          {:ok, InventoryItem.t()} | {:error, term()}
  def update_durability(item_id, new_durability) when new_durability >= 0 do
    case Repo.get(InventoryItem, item_id) do
      nil ->
        {:error, :not_found}

      item ->
        clamped = min(new_durability, item.max_durability)

        item
        |> InventoryItem.changeset(%{durability: clamped})
        |> Repo.update()
    end
  end

  @doc """
  Repair item to full durability.
  """
  @spec repair_item(integer()) :: {:ok, InventoryItem.t()} | {:error, term()}
  def repair_item(item_id) do
    case Repo.get(InventoryItem, item_id) do
      nil ->
        {:error, :not_found}

      item ->
        item
        |> InventoryItem.changeset(%{durability: item.max_durability})
        |> Repo.update()
    end
  end

  @doc """
  Repair all equipped items for a character.

  Returns the total repair cost (0 for now, future: calculate based on item level).
  """
  @spec repair_all_equipped(integer()) :: {:ok, integer()}
  def repair_all_equipped(character_id) do
    equipped_items = get_items(character_id, :equipped)

    Enum.each(equipped_items, fn item ->
      if item.durability < item.max_durability do
        {:ok, _} =
          item
          |> InventoryItem.changeset(%{durability: item.max_durability})
          |> Repo.update()
      end
    end)

    # TODO: Calculate repair cost
    {:ok, 0}
  end
end
