defmodule BezgelorWorld.Handler.InventoryHandler do
  @moduledoc """
  Handles inventory-related packets.

  Processes item moves, splits, and sends inventory updates to client.
  """

  import Bitwise

  alias BezgelorDb.Inventory
  alias BezgelorProtocol.Packets.World.{
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
          # Use database item ID as unique guid
          guid = item.id || generate_item_guid(item)

          packet = %ServerItemAdd{
            guid: guid,
            item_id: item.item_id,
            location: item.container_type,
            bag_index: item.slot,
            stack_count: item.quantity || 1,
            durability: item.durability || 100,
            reason: :no_reason
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

        guid = new_item.id || generate_item_guid(new_item)

        add_packet = %ServerItemAdd{
          guid: guid,
          item_id: new_item.item_id,
          location: new_item.container_type,
          bag_index: new_item.slot,
          stack_count: new_item.quantity || 1,
          durability: new_item.durability || 100,
          reason: :no_reason
        }

        send(connection_pid, {:send_packet, update_packet})
        send(connection_pid, {:send_packet, add_packet})

      {:error, reason} ->
        Logger.warning("Split stack failed: #{inspect(reason)}")
    end
  end

  # Generate a unique item guid if database ID not available
  defp generate_item_guid(item) do
    container_int =
      case item.container_type do
        :equipped -> 0
        :bag -> 1
        :inventory -> 1
        :bank -> 2
        _ -> 1
      end

    # Combine container, bag_index, and slot into a unique ID
    (container_int <<< 48) ||| ((item.bag_index || 0) <<< 32) ||| (item.slot || 0)
  end
end
