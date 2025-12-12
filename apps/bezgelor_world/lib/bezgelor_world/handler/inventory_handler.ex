defmodule BezgelorWorld.Handler.InventoryHandler do
  @moduledoc """
  Handles inventory-related packets.

  Processes item moves, splits, and sends inventory updates to client.
  """

  alias BezgelorDb.Inventory
  alias BezgelorProtocol.Packets.World.{
    ClientMoveItem,
    ClientSplitStack,
    ServerInventoryList,
    ServerItemAdd,
    ServerItemRemove,
    ServerItemUpdate
  }

  require Logger

  @doc """
  Send full inventory to client (called on login).
  """
  @spec send_inventory(pid(), integer()) :: :ok
  def send_inventory(connection_pid, character_id) do
    bags = Inventory.get_bags(character_id)
    items = Inventory.get_items(character_id)

    bag_data =
      Enum.map(bags, fn bag ->
        %{bag_index: bag.bag_index, item_id: bag.item_id, size: bag.size}
      end)

    item_data =
      Enum.map(items, fn item ->
        %{
          container_type: item.container_type,
          bag_index: item.bag_index,
          slot: item.slot,
          item_id: item.item_id,
          quantity: item.quantity,
          durability: item.durability,
          bound: item.bound
        }
      end)

    packet = %ServerInventoryList{bags: bag_data, items: item_data}
    send(connection_pid, {:send_packet, packet})

    :ok
  end

  @doc """
  Initialize inventory for a new character.
  """
  @spec init_inventory(integer()) :: :ok
  def init_inventory(character_id) do
    case Inventory.init_bags(character_id) do
      {:ok, _bag} ->
        Logger.debug("Initialized inventory for character #{character_id}")
        :ok

      {:error, reason} ->
        Logger.error("Failed to init inventory: #{inspect(reason)}")
        :ok
    end
  end

  @doc """
  Handle move item request.
  """
  @spec handle_move_item(pid(), integer(), ClientMoveItem.t()) :: :ok
  def handle_move_item(connection_pid, character_id, %ClientMoveItem{} = packet) do
    src_item =
      Inventory.get_item_at(
        character_id,
        packet.src_container,
        packet.src_bag_index,
        packet.src_slot
      )

    dst_item =
      Inventory.get_item_at(
        character_id,
        packet.dst_container,
        packet.dst_bag_index,
        packet.dst_slot
      )

    result =
      cond do
        is_nil(src_item) ->
          {:error, :no_source_item}

        is_nil(dst_item) ->
          # Simple move to empty slot
          Inventory.move_item(
            src_item,
            packet.dst_container,
            packet.dst_bag_index,
            packet.dst_slot
          )

        src_item.item_id == dst_item.item_id and dst_item.quantity < dst_item.max_stack ->
          # Try to stack
          Inventory.stack_items(src_item, dst_item)

        true ->
          # Swap items
          Inventory.swap_items(src_item, dst_item)
      end

    case result do
      {:ok, _} ->
        # Send updated inventory
        send_inventory(connection_pid, character_id)

      {:error, reason} ->
        Logger.warning("Move item failed: #{inspect(reason)}")
    end

    :ok
  end

  @doc """
  Handle split stack request.
  """
  @spec handle_split_stack(pid(), integer(), ClientSplitStack.t()) :: :ok
  def handle_split_stack(connection_pid, character_id, %ClientSplitStack{} = packet) do
    src_item =
      Inventory.get_item_at(
        character_id,
        packet.src_container,
        packet.src_bag_index,
        packet.src_slot
      )

    cond do
      is_nil(src_item) ->
        Logger.warning("Split stack failed: no source item")

      src_item.quantity <= packet.quantity ->
        Logger.warning("Split stack failed: insufficient quantity")

      true ->
        # Check destination is empty
        dst_item =
          Inventory.get_item_at(
            character_id,
            packet.dst_container,
            packet.dst_bag_index,
            packet.dst_slot
          )

        if is_nil(dst_item) do
          do_split_stack(connection_pid, character_id, src_item, packet)
        else
          Logger.warning("Split stack failed: destination occupied")
        end
    end

    :ok
  end

  @doc """
  Add item to character inventory and notify client.
  """
  @spec give_item(pid(), integer(), integer(), integer(), map()) ::
          {:ok, [term()]} | {:error, term()}
  def give_item(connection_pid, character_id, item_id, quantity, opts \\ %{}) do
    case Inventory.add_item(character_id, item_id, quantity, opts) do
      {:ok, items} ->
        # Send item add packets for each new stack
        Enum.each(items, fn item ->
          packet = %ServerItemAdd{
            container_type: item.container_type,
            bag_index: item.bag_index,
            slot: item.slot,
            item_id: item.item_id,
            quantity: item.quantity,
            max_stack: item.max_stack,
            durability: item.durability,
            bound: item.bound
          }

          send(connection_pid, {:send_packet, packet})
        end)

        {:ok, items}

      {:error, :inventory_full} = err ->
        Logger.warning("Failed to give item #{item_id}: inventory full")
        err

      {:error, reason} = err ->
        Logger.error("Failed to give item #{item_id}: #{inspect(reason)}")
        err
    end
  end

  @doc """
  Remove item from character inventory and notify client.
  """
  @spec take_item(pid(), integer(), integer(), integer()) ::
          {:ok, integer()} | {:error, term()}
  def take_item(connection_pid, character_id, item_id, quantity) do
    # Get items before removal to know which slots to update
    items_before =
      Inventory.get_items(character_id)
      |> Enum.filter(&(&1.item_id == item_id))

    case Inventory.remove_item(character_id, item_id, quantity) do
      {:ok, removed} ->
        # Send updates for affected items
        items_after =
          Inventory.get_items(character_id)
          |> Enum.filter(&(&1.item_id == item_id))
          |> Map.new(&{{&1.container_type, &1.bag_index, &1.slot}, &1})

        Enum.each(items_before, fn item ->
          key = {item.container_type, item.bag_index, item.slot}

          case Map.get(items_after, key) do
            nil ->
              # Item was removed
              packet = %ServerItemRemove{
                container_type: item.container_type,
                bag_index: item.bag_index,
                slot: item.slot
              }

              send(connection_pid, {:send_packet, packet})

            updated ->
              # Item quantity changed
              if updated.quantity != item.quantity do
                packet = %ServerItemUpdate{
                  container_type: updated.container_type,
                  bag_index: updated.bag_index,
                  slot: updated.slot,
                  quantity: updated.quantity,
                  durability: updated.durability
                }

                send(connection_pid, {:send_packet, packet})
              end
          end
        end)

        {:ok, removed}

      {:error, _} = err ->
        err
    end
  end

  # Private

  defp do_split_stack(connection_pid, _character_id, src_item, packet) do
    case Inventory.split_stack(
           src_item,
           packet.quantity,
           packet.dst_container,
           packet.dst_bag_index,
           packet.dst_slot
         ) do
      {:ok, {updated_source, new_item}} ->
        # Send updates
        update_packet = %ServerItemUpdate{
          container_type: updated_source.container_type,
          bag_index: updated_source.bag_index,
          slot: updated_source.slot,
          quantity: updated_source.quantity,
          durability: updated_source.durability
        }

        add_packet = %ServerItemAdd{
          container_type: new_item.container_type,
          bag_index: new_item.bag_index,
          slot: new_item.slot,
          item_id: new_item.item_id,
          quantity: new_item.quantity,
          max_stack: new_item.max_stack,
          durability: new_item.durability,
          bound: new_item.bound
        }

        send(connection_pid, {:send_packet, update_packet})
        send(connection_pid, {:send_packet, add_packet})

      {:error, reason} ->
        Logger.warning("Split stack failed: #{inspect(reason)}")
    end
  end
end
