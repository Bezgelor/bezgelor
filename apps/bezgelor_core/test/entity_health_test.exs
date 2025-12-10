defmodule BezgelorCore.EntityHealthTest do
  use ExUnit.Case, async: true

  alias BezgelorCore.Entity

  defp make_entity(health, max_health) do
    %Entity{
      guid: 1,
      type: :player,
      name: "Test",
      health: health,
      max_health: max_health
    }
  end

  describe "apply_damage/2" do
    test "reduces health by damage amount" do
      entity = make_entity(100, 100)
      entity = Entity.apply_damage(entity, 30)

      assert entity.health == 70
    end

    test "health cannot go below 0" do
      entity = make_entity(50, 100)
      entity = Entity.apply_damage(entity, 100)

      assert entity.health == 0
    end

    test "zero damage has no effect" do
      entity = make_entity(100, 100)
      entity = Entity.apply_damage(entity, 0)

      assert entity.health == 100
    end
  end

  describe "apply_healing/2" do
    test "increases health by healing amount" do
      entity = make_entity(50, 100)
      entity = Entity.apply_healing(entity, 30)

      assert entity.health == 80
    end

    test "health cannot exceed max_health" do
      entity = make_entity(80, 100)
      entity = Entity.apply_healing(entity, 50)

      assert entity.health == 100
    end

    test "zero healing has no effect" do
      entity = make_entity(50, 100)
      entity = Entity.apply_healing(entity, 0)

      assert entity.health == 50
    end
  end

  describe "set_health/2" do
    test "sets health to specified value" do
      entity = make_entity(100, 100)
      entity = Entity.set_health(entity, 50)

      assert entity.health == 50
    end

    test "clamps health to 0 minimum" do
      entity = make_entity(100, 100)
      entity = Entity.set_health(entity, -50)

      assert entity.health == 0
    end

    test "clamps health to max_health maximum" do
      entity = make_entity(100, 100)
      entity = Entity.set_health(entity, 150)

      assert entity.health == 100
    end
  end

  describe "dead?/1" do
    test "returns true when health is 0" do
      entity = make_entity(0, 100)
      assert Entity.dead?(entity)
    end

    test "returns false when health > 0" do
      entity = make_entity(1, 100)
      refute Entity.dead?(entity)
    end
  end

  describe "alive?/1" do
    test "returns true when health > 0" do
      entity = make_entity(1, 100)
      assert Entity.alive?(entity)
    end

    test "returns false when health is 0" do
      entity = make_entity(0, 100)
      refute Entity.alive?(entity)
    end
  end

  describe "health_percent/1" do
    test "returns percentage as float" do
      entity = make_entity(50, 100)
      assert Entity.health_percent(entity) == 0.5
    end

    test "returns 1.0 at full health" do
      entity = make_entity(100, 100)
      assert Entity.health_percent(entity) == 1.0
    end

    test "returns 0.0 at zero health" do
      entity = make_entity(0, 100)
      assert Entity.health_percent(entity) == 0.0
    end

    test "handles zero max_health" do
      entity = make_entity(0, 0)
      assert Entity.health_percent(entity) == 0.0
    end
  end

  describe "restore_health/1" do
    test "sets health to max_health" do
      entity = make_entity(30, 100)
      entity = Entity.restore_health(entity)

      assert entity.health == 100
    end
  end
end
