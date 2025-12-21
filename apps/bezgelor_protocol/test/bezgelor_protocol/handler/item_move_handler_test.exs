defmodule BezgelorProtocol.Handler.ItemMoveHandlerTest do
  @moduledoc """
  Tests for ItemMoveHandler.

  Tests the item move handler logic including moves, swaps, and location conversion.
  """
  use ExUnit.Case, async: false

  alias BezgelorProtocol.Packets.World.ClientItemMove
  alias BezgelorDb.{Accounts, Characters, Inventory, Repo}

  @moduletag :database

  setup do
    case Repo.start_link([]) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    # Create test account and character
    email = "item_move_test#{System.unique_integer([:positive])}@test.com"
    {:ok, account} = Accounts.create_account(email, "password123")

    {:ok, character} =
      Characters.create_character(account.id, %{
        name: "ItemMover#{System.unique_integer([:positive])}",
        sex: 0,
        race: 1,
        class: 1,
        faction_id: 166,
        world_id: 1,
        world_zone_id: 1,
        realm_id: 1
      })

    # Initialize bags for the character
    {:ok, _bag} = Inventory.init_bags(character.id)

    %{character: character, account: account}
  end

  describe "inventory operations" do
    test "move item to empty slot", %{character: character} do
      # Add an item to the character's inventory at slot 0
      {:ok, [item]} = Inventory.add_item(character.id, 1000, 1, %{container_type: :bag})
      original_slot = item.slot

      # Move to slot 5
      {:ok, moved_item} = Inventory.move_item(item, :bag, 0, 5)

      assert moved_item.slot == 5
      assert moved_item.container_type == :bag
      assert Inventory.get_item_at(character.id, :bag, 0, original_slot) == nil
      assert Inventory.get_item_at(character.id, :bag, 0, 5) != nil
    end

    test "swap items between slots", %{character: character} do
      # Add two items
      {:ok, [item1]} = Inventory.add_item(character.id, 1000, 1, %{container_type: :bag})
      {:ok, [item2]} = Inventory.add_item(character.id, 1001, 1, %{container_type: :bag})

      slot1 = item1.slot
      slot2 = item2.slot

      # Swap
      {:ok, {swapped1, swapped2}} = Inventory.swap_items(item1, item2)

      assert swapped1.slot == slot2
      assert swapped2.slot == slot1

      # Verify by re-fetching
      new_at_slot1 = Inventory.get_item_at(character.id, :bag, 0, slot1)
      new_at_slot2 = Inventory.get_item_at(character.id, :bag, 0, slot2)

      assert new_at_slot1.item_id == item2.item_id
      assert new_at_slot2.item_id == item1.item_id
    end

    test "move item to occupied slot fails", %{character: character} do
      {:ok, [item1]} = Inventory.add_item(character.id, 1000, 1, %{container_type: :bag})
      {:ok, [item2]} = Inventory.add_item(character.id, 1001, 1, %{container_type: :bag})

      # Try to move item1 to item2's slot
      result = Inventory.move_item(item1, :bag, 0, item2.slot)

      assert {:error, :slot_occupied} = result
    end

    test "equip item moves to equipped container", %{character: character} do
      {:ok, [item]} = Inventory.add_item(character.id, 1000, 1, %{container_type: :bag})

      # Move to equipped slot 0 (chest)
      {:ok, equipped} = Inventory.move_item(item, :equipped, 0, 0)

      assert equipped.container_type == :equipped
      assert equipped.slot == 0
    end
  end

  describe "location_to_atom/1" do
    test "converts location integers to atoms" do
      assert ClientItemMove.location_to_atom(0) == :equipped
      assert ClientItemMove.location_to_atom(1) == :bag
      assert ClientItemMove.location_to_atom(2) == :bank
      assert ClientItemMove.location_to_atom(4) == :ability
      # Default
      assert ClientItemMove.location_to_atom(99) == :bag
    end
  end

  describe "ClientItemMove packet" do
    test "packet struct has correct fields" do
      packet = %ClientItemMove{
        from_location: 1,
        from_bag_index: 5,
        to_location: 0,
        to_bag_index: 16
      }

      assert packet.from_location == 1
      assert packet.from_bag_index == 5
      assert packet.to_location == 0
      assert packet.to_bag_index == 16
    end
  end
end
