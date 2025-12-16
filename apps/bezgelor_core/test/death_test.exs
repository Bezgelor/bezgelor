defmodule BezgelorCore.DeathTest do
  use ExUnit.Case, async: true

  alias BezgelorCore.Death

  describe "durability_loss/1" do
    test "returns 0% for levels 1-9" do
      assert Death.durability_loss(1) == 0.0
      assert Death.durability_loss(5) == 0.0
      assert Death.durability_loss(9) == 0.0
    end

    test "returns 5% for levels 10-29" do
      assert Death.durability_loss(10) == 5.0
      assert Death.durability_loss(20) == 5.0
      assert Death.durability_loss(29) == 5.0
    end

    test "returns 10% for levels 30-49" do
      assert Death.durability_loss(30) == 10.0
      assert Death.durability_loss(40) == 10.0
      assert Death.durability_loss(49) == 10.0
    end

    test "returns 15% for level 50+" do
      assert Death.durability_loss(50) == 15.0
      assert Death.durability_loss(60) == 15.0
    end
  end

  describe "respawn_health_percent/1" do
    test "returns 50% for levels 1-19" do
      assert Death.respawn_health_percent(1) == 50.0
      assert Death.respawn_health_percent(10) == 50.0
      assert Death.respawn_health_percent(19) == 50.0
    end

    test "returns 35% for levels 20-39" do
      assert Death.respawn_health_percent(20) == 35.0
      assert Death.respawn_health_percent(30) == 35.0
      assert Death.respawn_health_percent(39) == 35.0
    end

    test "returns 25% for level 40+" do
      assert Death.respawn_health_percent(40) == 25.0
      assert Death.respawn_health_percent(50) == 25.0
    end
  end

  describe "resurrection_health/2" do
    test "calculates health from resurrection spell percentage" do
      max_health = 10000

      # 35% resurrection (common)
      assert Death.resurrection_health(max_health, 35.0) == 3500

      # 60% resurrection (stronger spell)
      assert Death.resurrection_health(max_health, 60.0) == 6000

      # 100% resurrection (full)
      assert Death.resurrection_health(max_health, 100.0) == 10000
    end

    test "clamps health to valid range" do
      assert Death.resurrection_health(10000, 0.0) == 0
      assert Death.resurrection_health(10000, 150.0) == 10000
    end
  end

  describe "is_player_guid?/1" do
    test "returns true for player GUIDs (high bits set)" do
      # Player GUIDs have the high type bits set to 0x10
      player_guid = 0x1000000000000001
      assert Death.is_player_guid?(player_guid) == true
    end

    test "returns false for creature GUIDs" do
      # Creature GUIDs have type 0x04
      creature_guid = 0x0400000000000001
      assert Death.is_player_guid?(creature_guid) == false
    end

    test "returns false for other entity types" do
      # Vehicle GUIDs, NPC GUIDs, etc.
      vehicle_guid = 0x0800000000000001
      assert Death.is_player_guid?(vehicle_guid) == false
    end
  end

  describe "death_type/1" do
    test "returns :combat for combat death" do
      assert Death.death_type(:combat) == 0
    end

    test "returns :fall for fall death" do
      assert Death.death_type(:fall) == 1
    end

    test "returns :drown for drowning" do
      assert Death.death_type(:drown) == 2
    end

    test "returns :environment for environmental death" do
      assert Death.death_type(:environment) == 3
    end
  end

  describe "respawn_grace_period_ms/0" do
    test "returns the respawn grace period in milliseconds" do
      # 30 second grace period before forced respawn
      assert Death.respawn_grace_period_ms() == 30_000
    end
  end
end
