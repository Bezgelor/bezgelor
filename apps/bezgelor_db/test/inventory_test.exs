defmodule BezgelorDb.InventoryTest do
  use ExUnit.Case

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
    email = "inv_test#{System.unique_integer([:positive])}@test.com"
    {:ok, account} = Accounts.create_account(email, "password123")

    {:ok, character} =
      Characters.create_character(account.id, %{
        name: "InvTester#{System.unique_integer([:positive])}",
        sex: 0,
        race: 0,
        class: 0,
        faction_id: 166,
        world_id: 1,
        world_zone_id: 1
      })

    # Initialize bags
    {:ok, _} = Inventory.init_bags(character.id)

    {:ok, account: account, character: character}
  end

  describe "bags" do
    test "init_bags creates backpack", %{character: character} do
      bags = Inventory.get_bags(character.id)
      assert length(bags) == 1
      assert hd(bags).bag_index == 0
      assert hd(bags).size == 16
    end

    test "equip_bag adds bag to slot", %{character: character} do
      {:ok, bag} = Inventory.equip_bag(character.id, 1, 12345, 20)

      assert bag.bag_index == 1
      assert bag.item_id == 12345
      assert bag.size == 20
    end

    test "total_capacity sums all bag sizes", %{character: character} do
      Inventory.equip_bag(character.id, 1, 100, 12)
      Inventory.equip_bag(character.id, 2, 101, 16)

      # Backpack (16) + bag1 (12) + bag2 (16) = 44
      assert Inventory.total_capacity(character.id) == 44
    end
  end

  describe "add_item" do
    test "adds non-stackable item to first empty slot", %{character: character} do
      {:ok, [item]} = Inventory.add_item(character.id, 1001, 1)

      assert item.item_id == 1001
      assert item.quantity == 1
      assert item.bag_index == 0
      assert item.slot == 0
    end

    test "adds multiple non-stackable items to different slots", %{character: character} do
      {:ok, _} = Inventory.add_item(character.id, 1001, 1)
      {:ok, [item2]} = Inventory.add_item(character.id, 1002, 1)

      assert item2.slot == 1
    end

    test "auto-stacks stackable items", %{character: character} do
      # Add 50 of a stackable item (max stack 100)
      {:ok, _} = Inventory.add_item(character.id, 2001, 50, %{max_stack: 100})

      # Add 30 more - should stack with existing
      {:ok, items} = Inventory.add_item(character.id, 2001, 30, %{max_stack: 100})

      # No new items created (all went to existing stack)
      assert items == []

      # Total should be 80
      assert Inventory.count_item(character.id, 2001) == 80
    end

    test "creates new stacks when max exceeded", %{character: character} do
      # Add 150 of item with max stack 100
      {:ok, items} = Inventory.add_item(character.id, 2001, 150, %{max_stack: 100})

      # Should create 2 stacks
      assert length(items) == 2

      # First should be full (100), second partial (50)
      all_items = Inventory.get_items(character.id)
      quantities = Enum.map(all_items, & &1.quantity) |> Enum.sort(:desc)
      assert quantities == [100, 50]
    end

    test "returns error when inventory full", %{character: character} do
      # Fill all 16 slots of backpack
      for i <- 0..15 do
        {:ok, _} = Inventory.add_item(character.id, 1000 + i, 1)
      end

      # Try to add one more
      assert {:error, :inventory_full} = Inventory.add_item(character.id, 9999, 1)
    end
  end

  describe "remove_item" do
    test "removes quantity from single stack", %{character: character} do
      Inventory.add_item(character.id, 2001, 50, %{max_stack: 100})

      {:ok, removed} = Inventory.remove_item(character.id, 2001, 20)

      assert removed == 20
      assert Inventory.count_item(character.id, 2001) == 30
    end

    test "removes item when quantity matches", %{character: character} do
      Inventory.add_item(character.id, 1001, 1)

      {:ok, removed} = Inventory.remove_item(character.id, 1001, 1)

      assert removed == 1
      assert Inventory.count_item(character.id, 1001) == 0
    end

    test "returns error for insufficient quantity", %{character: character} do
      Inventory.add_item(character.id, 2001, 10, %{max_stack: 100})

      assert {:error, :insufficient_quantity} = Inventory.remove_item(character.id, 2001, 50)
    end
  end

  describe "move_item" do
    test "moves item to empty slot", %{character: character} do
      {:ok, [item]} = Inventory.add_item(character.id, 1001, 1)

      {:ok, moved} = Inventory.move_item(item, :bag, 0, 5)

      assert moved.slot == 5
    end

    test "returns error when destination occupied", %{character: character} do
      {:ok, [item1]} = Inventory.add_item(character.id, 1001, 1)
      {:ok, _} = Inventory.add_item(character.id, 1002, 1)

      # item2 is at slot 1, try to move item1 there
      assert {:error, :slot_occupied} = Inventory.move_item(item1, :bag, 0, 1)
    end
  end

  describe "swap_items" do
    test "swaps two items", %{character: character} do
      {:ok, [item1]} = Inventory.add_item(character.id, 1001, 1)
      {:ok, [item2]} = Inventory.add_item(character.id, 1002, 1)

      # Item1 at slot 0, Item2 at slot 1
      assert item1.slot == 0
      assert item2.slot == 1

      {:ok, {swapped1, swapped2}} = Inventory.swap_items(item1, item2)

      # Now swapped
      assert swapped1.slot == 1
      assert swapped2.slot == 0
    end
  end

  describe "stack_items" do
    test "combines partial stacks", %{character: character} do
      # Create two partial stacks manually
      {:ok, [item1]} = Inventory.add_item(character.id, 2001, 30, %{max_stack: 100})
      # Add to slot 1 specifically by filling slot 0 first
      {:ok, [item2]} =
        BezgelorDb.Repo.transaction(fn ->
          attrs = %{
            character_id: character.id,
            item_id: 2001,
            container_type: :bag,
            bag_index: 0,
            slot: 1,
            quantity: 40,
            max_stack: 100
          }

          %BezgelorDb.Schema.InventoryItem{}
          |> BezgelorDb.Schema.InventoryItem.changeset(attrs)
          |> BezgelorDb.Repo.insert!()
        end)
        |> case do
          {:ok, item} -> {:ok, [item]}
        end

      {:ok, {source, target}} = Inventory.stack_items(item1, item2)

      # Source should be nil (fully merged)
      assert source == nil
      # Target should have combined quantity
      assert target.quantity == 70
    end

    test "returns error for different items", %{character: character} do
      {:ok, [item1]} = Inventory.add_item(character.id, 1001, 1)
      {:ok, [item2]} = Inventory.add_item(character.id, 1002, 1)

      assert {:error, :cannot_stack} = Inventory.stack_items(item1, item2)
    end
  end

  describe "utility functions" do
    test "count_item returns total quantity", %{character: character} do
      Inventory.add_item(character.id, 2001, 100, %{max_stack: 100})
      Inventory.add_item(character.id, 2001, 50, %{max_stack: 100})

      assert Inventory.count_item(character.id, 2001) == 150
    end

    test "has_item? checks quantity", %{character: character} do
      Inventory.add_item(character.id, 2001, 50, %{max_stack: 100})

      assert Inventory.has_item?(character.id, 2001, 30)
      assert Inventory.has_item?(character.id, 2001, 50)
      refute Inventory.has_item?(character.id, 2001, 51)
    end

    test "find_empty_slot finds first available", %{character: character} do
      # First empty should be slot 0
      assert {0, 0} = Inventory.find_empty_slot(character.id)

      # Fill slot 0
      Inventory.add_item(character.id, 1001, 1)

      # Now should be slot 1
      assert {0, 1} = Inventory.find_empty_slot(character.id)
    end
  end
end
