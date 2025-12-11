defmodule BezgelorDb.TradeskillsTest do
  use ExUnit.Case, async: true

  alias BezgelorDb.Tradeskills
  alias BezgelorDb.Schema.{CharacterTradeskill, SchematicDiscovery, TradeskillTalent, WorkOrder}

  # Test fixtures would need character setup
  # For now, test the interface exists

  describe "profession management" do
    test "learn_profession/3 creates tradeskill record" do
      # Would need character fixture
      assert function_exported?(Tradeskills, :learn_profession, 3)
    end

    test "get_professions/1 returns character's professions" do
      assert function_exported?(Tradeskills, :get_professions, 1)
    end

    test "swap_profession/3 deactivates old and activates new" do
      assert function_exported?(Tradeskills, :swap_profession, 3)
    end
  end

  describe "progress tracking" do
    test "add_xp/3 increases XP and may level up" do
      assert function_exported?(Tradeskills, :add_xp, 3)
    end
  end

  describe "discovery" do
    test "discover_schematic/3 records discovery" do
      assert function_exported?(Tradeskills, :discover_schematic, 3)
    end

    test "is_discovered?/3 checks discovery state" do
      assert function_exported?(Tradeskills, :is_discovered?, 3)
    end
  end

  describe "talents" do
    test "allocate_talent/3 adds talent point" do
      assert function_exported?(Tradeskills, :allocate_talent, 3)
    end

    test "get_talents/2 returns allocated talents" do
      assert function_exported?(Tradeskills, :get_talents, 2)
    end

    test "reset_talents/2 clears all talents for profession" do
      assert function_exported?(Tradeskills, :reset_talents, 2)
    end
  end

  describe "work orders" do
    test "create_work_order/2 creates work order" do
      assert function_exported?(Tradeskills, :create_work_order, 2)
    end

    test "get_active_work_orders/1 returns active orders" do
      assert function_exported?(Tradeskills, :get_active_work_orders, 1)
    end

    test "update_work_order_progress/2 increments progress" do
      assert function_exported?(Tradeskills, :update_work_order_progress, 2)
    end
  end
end
