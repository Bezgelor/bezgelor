defmodule BezgelorProtocol.Handler.ItemCommandHandler do
  @moduledoc """
  Handler for /additem and /equipitem chat commands (GM commands).

  ## Usage

  In chat:
  - `/additem <item_id> [quantity]` - Add item(s) to inventory
  - `/ai <item_id> [quantity]` - Alias for /additem
  - `/equipitem <item_id>` - Add item directly to equipment slot
  - `/ei <item_id>` - Alias for /equipitem

  ## Examples

      /additem 12345       # Add 1x item 12345 to inventory
      /additem 12345 10    # Add 10x item 12345 to inventory
      /equipitem 12345     # Equip item 12345
  """

  @compile {:no_warn_undefined, [BezgelorData.Store, BezgelorDb.Inventory]}

  alias BezgelorDb.Inventory
  alias BezgelorData.Store

  require Logger

  @doc """
  Parse and execute additem command.

  Returns {:ok, message, items} on success, or {:error, reason} on failure.
  The caller should send ServerItemAdd packets for each item returned.
  """
  @spec handle_additem(String.t(), map()) ::
          {:ok, String.t(), [map()]} | {:error, atom() | String.t()}
  def handle_additem(args, session) do
    character_id = get_in(session, [:session_data, :character, :id])

    unless character_id do
      {:error, "No character in session"}
    else
      args
      |> String.trim()
      |> String.split(~r/\s+/)
      |> parse_additem_args()
      |> case do
        {:ok, item_id, quantity} ->
          do_additem(character_id, item_id, quantity)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Parse and execute equipitem command.

  Returns {:ok, message, item} on success, or {:error, reason} on failure.
  The caller should send ServerItemAdd packet for the equipped item.
  """
  @spec handle_equipitem(String.t(), map()) ::
          {:ok, String.t(), map()} | {:error, atom() | String.t()}
  def handle_equipitem(args, session) do
    character_id = get_in(session, [:session_data, :character, :id])

    unless character_id do
      {:error, "No character in session"}
    else
      args
      |> String.trim()
      |> parse_equipitem_args()
      |> case do
        {:ok, item_id} ->
          do_equipitem(character_id, item_id)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  # Parse additem arguments: <item_id> [quantity]
  defp parse_additem_args([item_id_str]) do
    case Integer.parse(item_id_str) do
      {item_id, ""} when item_id > 0 -> {:ok, item_id, 1}
      _ -> {:error, :invalid_item_id}
    end
  end

  defp parse_additem_args([item_id_str, quantity_str]) do
    with {item_id, ""} when item_id > 0 <- Integer.parse(item_id_str),
         {quantity, ""} when quantity > 0 and quantity <= 999 <- Integer.parse(quantity_str) do
      {:ok, item_id, quantity}
    else
      _ -> {:error, :invalid_arguments}
    end
  end

  defp parse_additem_args([]) do
    {:error, :missing_item_id}
  end

  defp parse_additem_args(_) do
    {:error, :invalid_arguments}
  end

  # Parse equipitem arguments: <item_id>
  defp parse_equipitem_args(args) do
    case Integer.parse(args) do
      {item_id, ""} when item_id > 0 -> {:ok, item_id}
      {item_id, _rest} when item_id > 0 -> {:ok, item_id}
      _ -> {:error, :invalid_item_id}
    end
  end

  # Execute additem
  defp do_additem(character_id, item_id, quantity) do
    # Verify item exists
    case Store.get_item(item_id) do
      {:ok, item} ->
        max_stack = Map.get(item, :max_stack_count, 1)

        case Inventory.add_item(character_id, item_id, quantity, %{max_stack: max_stack}) do
          {:ok, items} ->
            item_name = Map.get(item, :name, "Unknown Item")

            Logger.info(
              "GM: Added #{quantity}x #{item_name} (#{item_id}) to character #{character_id}"
            )

            {:ok, "Added #{quantity}x #{item_name} (#{item_id}) to inventory", items}

          {:error, :inventory_full} ->
            {:error, "Inventory full"}

          {:error, reason} ->
            Logger.warning("GM additem failed: #{inspect(reason)}")
            {:error, "Failed to add item: #{inspect(reason)}"}
        end

      :error ->
        {:error, "Item #{item_id} not found"}
    end
  end

  # Execute equipitem
  defp do_equipitem(character_id, item_id) do
    # Verify item exists
    case Store.get_item(item_id) do
      {:ok, item} ->
        case Inventory.add_equipped_item(character_id, item_id) do
          {:ok, inv_item} ->
            item_name = Map.get(item, :name, "Unknown Item")
            Logger.info("GM: Equipped #{item_name} (#{item_id}) on character #{character_id}")
            {:ok, "Equipped #{item_name} (#{item_id})", inv_item}

          {:error, :no_valid_slot} ->
            {:error, "Item cannot be equipped (no valid slot)"}

          {:error, :slot_occupied} ->
            {:error, "Equipment slot already occupied"}

          {:error, reason} ->
            Logger.warning("GM equipitem failed: #{inspect(reason)}")
            {:error, "Failed to equip item: #{inspect(reason)}"}
        end

      :error ->
        {:error, "Item #{item_id} not found"}
    end
  end
end
