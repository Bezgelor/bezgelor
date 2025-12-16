defmodule BezgelorCore.CreatureTemplateTest do
  use ExUnit.Case, async: true

  alias BezgelorCore.CreatureTemplate

  describe "get/1" do
    test "returns template by ID" do
      template = CreatureTemplate.get(1)

      assert %CreatureTemplate{} = template
      assert template.id == 1
      assert template.name == "Training Dummy"
    end

    test "returns nil for unknown ID" do
      assert nil == CreatureTemplate.get(999)
    end
  end

  describe "exists?/1" do
    test "returns true for known templates" do
      assert CreatureTemplate.exists?(1)
      assert CreatureTemplate.exists?(2)
      assert CreatureTemplate.exists?(3)
    end

    test "returns false for unknown templates" do
      refute CreatureTemplate.exists?(999)
    end
  end

  describe "all_ids/0" do
    test "returns all template IDs" do
      ids = CreatureTemplate.all_ids()

      assert 1 in ids
      assert 2 in ids
      assert 3 in ids
      assert 4 in ids
      assert 5 in ids
    end
  end

  describe "aggressive?/1" do
    test "returns true for aggressive creatures" do
      wolf = CreatureTemplate.get(2)
      assert CreatureTemplate.aggressive?(wolf)
    end

    test "returns false for passive creatures" do
      dummy = CreatureTemplate.get(1)
      refute CreatureTemplate.aggressive?(dummy)
    end

    test "returns false for defensive creatures" do
      guard = CreatureTemplate.get(4)
      refute CreatureTemplate.aggressive?(guard)
    end
  end

  describe "hostile?/1" do
    test "returns true for hostile faction" do
      wolf = CreatureTemplate.get(2)
      assert CreatureTemplate.hostile?(wolf)
    end

    test "returns false for friendly faction" do
      guard = CreatureTemplate.get(4)
      refute CreatureTemplate.hostile?(guard)
    end

    test "returns false for neutral faction" do
      merchant = CreatureTemplate.get(5)
      refute CreatureTemplate.hostile?(merchant)
    end
  end

  describe "roll_damage/1" do
    test "returns value within damage range" do
      wolf = CreatureTemplate.get(2)

      for _ <- 1..100 do
        damage = CreatureTemplate.roll_damage(wolf)
        assert damage >= wolf.damage_min
        assert damage <= wolf.damage_max
      end
    end

    test "returns 0 for creatures with no damage" do
      dummy = CreatureTemplate.get(1)
      assert CreatureTemplate.roll_damage(dummy) == 0
    end
  end

  describe "movement_duration/2" do
    test "calculates duration based on distance and speed" do
      template = %CreatureTemplate{movement_speed: 5.0}  # 5 units/second

      # 10 unit path = 2 seconds = 2000ms
      duration = CreatureTemplate.movement_duration(template, 10.0)

      assert duration == 2000
    end

    test "uses default speed when not specified" do
      template = %CreatureTemplate{}

      duration = CreatureTemplate.movement_duration(template, 10.0)

      # Default 4.0 units/sec -> 2500ms for 10 units
      assert duration == 2500
    end
  end

  describe "movement_speed/1" do
    test "returns specified speed" do
      template = %CreatureTemplate{movement_speed: 7.5}

      assert CreatureTemplate.movement_speed(template) == 7.5
    end

    test "returns default speed when not specified" do
      template = %CreatureTemplate{}

      assert CreatureTemplate.movement_speed(template) == 4.0
    end
  end

  describe "attack_range/1" do
    test "returns specified attack range" do
      template = %CreatureTemplate{attack_range: 8.0}

      assert CreatureTemplate.attack_range(template) == 8.0
    end

    test "returns melee default for non-ranged creatures" do
      template = %CreatureTemplate{is_ranged: false}

      assert CreatureTemplate.attack_range(template) == 5.0
    end

    test "returns ranged default for ranged creatures" do
      template = %CreatureTemplate{is_ranged: true}

      assert CreatureTemplate.attack_range(template) == 30.0
    end
  end

  describe "creature properties" do
    test "training dummy is passive with no damage" do
      dummy = CreatureTemplate.get(1)

      assert dummy.ai_type == :passive
      assert dummy.aggro_range == 0.0
      assert dummy.damage_min == 0
      assert dummy.damage_max == 0
    end

    test "forest wolf is aggressive with melee damage" do
      wolf = CreatureTemplate.get(2)

      assert wolf.ai_type == :aggressive
      assert wolf.aggro_range == 15.0
      assert wolf.level == 3
      assert wolf.xp_reward == 75
    end

    test "village guard is defensive and friendly" do
      guard = CreatureTemplate.get(4)

      assert guard.ai_type == :defensive
      assert guard.faction == :friendly
      assert guard.xp_reward == 0
    end
  end
end
