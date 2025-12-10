defmodule BezgelorCore.ExperienceTest do
  use ExUnit.Case, async: true

  alias BezgelorCore.Experience

  describe "xp_for_level/1" do
    test "returns 0 for level 1" do
      assert Experience.xp_for_level(1) == 0
    end

    test "returns 0 for level 0 or less" do
      assert Experience.xp_for_level(0) == 0
      assert Experience.xp_for_level(-1) == 0
    end

    test "follows quadratic formula" do
      # base * level^2 where base = 100
      assert Experience.xp_for_level(2) == 400
      assert Experience.xp_for_level(5) == 2500
      assert Experience.xp_for_level(10) == 10000
    end
  end

  describe "xp_to_next_level/1" do
    test "returns difference between levels" do
      # Level 1 -> 2: 400 - 0 = 400
      assert Experience.xp_to_next_level(1) == 400

      # Level 2 -> 3: 900 - 400 = 500
      assert Experience.xp_to_next_level(2) == 500

      # Level 5 -> 6: 3600 - 2500 = 1100
      assert Experience.xp_to_next_level(5) == 1100
    end

    test "returns 0 at max level" do
      max_level = Experience.max_level()
      assert Experience.xp_to_next_level(max_level) == 0
    end
  end

  describe "xp_from_kill/3" do
    test "full XP for same-level creature" do
      assert Experience.xp_from_kill(5, 5, 100) == 100
    end

    test "bonus XP for higher-level creatures" do
      # +2-4 levels = 110%
      assert Experience.xp_from_kill(5, 7, 100) == 110
      # +5 or more = 120%
      assert Experience.xp_from_kill(5, 10, 100) == 120
    end

    test "reduced XP for lower-level creatures" do
      # -3 to -4 levels = 50%
      assert Experience.xp_from_kill(10, 7, 100) == 50
      # -5 or more = 10% (gray)
      assert Experience.xp_from_kill(10, 4, 100) == 10
    end

    test "handles level difference edge cases" do
      # Exactly +1 level
      assert Experience.xp_from_kill(5, 6, 100) == 100
      # Exactly -2 levels
      assert Experience.xp_from_kill(5, 3, 100) == 100
    end
  end

  describe "check_level_up/2" do
    test "no change when XP is below threshold" do
      result = Experience.check_level_up(1, 300)
      assert {:no_change, 1, 300} = result
    end

    test "levels up when XP reaches threshold" do
      # Level 1 -> 2 requires 400 XP
      result = Experience.check_level_up(1, 400)
      assert {:level_up, 2, 0} = result
    end

    test "carries over excess XP" do
      # Level 1 -> 2 requires 400 XP, 500 given
      result = Experience.check_level_up(1, 500)
      assert {:level_up, 2, 100} = result
    end

    test "handles multiple level-ups" do
      # Level 1 -> 2 (400) -> 3 (500) = 900 total, give 1000
      result = Experience.check_level_up(1, 1000)
      assert {:level_up, 3, 100} = result
    end

    test "no change at max level" do
      max_level = Experience.max_level()
      result = Experience.check_level_up(max_level, 999_999)
      assert {:no_change, ^max_level, 999_999} = result
    end
  end

  describe "apply_xp/3" do
    test "adds XP without level up" do
      {level, xp, leveled} = Experience.apply_xp(1, 100, 100)

      assert level == 1
      assert xp == 200
      refute leveled
    end

    test "triggers level up" do
      {level, xp, leveled} = Experience.apply_xp(1, 0, 500)

      assert level == 2
      assert xp == 100
      assert leveled
    end

    test "handles multiple level-ups from one XP gain" do
      {level, xp, leveled} = Experience.apply_xp(1, 0, 1000)

      assert level == 3
      assert xp == 100
      assert leveled
    end
  end

  describe "health_for_level/1" do
    test "base health at level 1" do
      assert Experience.health_for_level(1) == 100
    end

    test "increases with level" do
      # 100 + (level-1) * 20
      assert Experience.health_for_level(2) == 120
      assert Experience.health_for_level(5) == 180
      assert Experience.health_for_level(10) == 280
    end
  end

  describe "level_progress/2" do
    test "returns 0.0 at start of level" do
      assert Experience.level_progress(1, 0) == 0.0
    end

    test "returns percentage towards next level" do
      # Level 1 needs 400 XP, at 200 = 50%
      assert Experience.level_progress(1, 200) == 0.5
    end

    test "returns 1.0 at max level" do
      max_level = Experience.max_level()
      assert Experience.level_progress(max_level, 0) == 1.0
    end
  end

  describe "at_max_level?/1" do
    test "returns false below max level" do
      refute Experience.at_max_level?(1)
      refute Experience.at_max_level?(30)
    end

    test "returns true at or above max level" do
      max_level = Experience.max_level()
      assert Experience.at_max_level?(max_level)
      assert Experience.at_max_level?(max_level + 1)
    end
  end
end
