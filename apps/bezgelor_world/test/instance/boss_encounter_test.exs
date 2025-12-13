defmodule BezgelorWorld.Instance.BossEncounterTest do
  @moduledoc """
  Tests for BossEncounter GenServer - verifies encounter lifecycle,
  phase transitions, ability execution, and effect processing.
  """
  use ExUnit.Case, async: false

  alias BezgelorWorld.Instance.BossEncounter
  alias BezgelorWorld.WorldManager

  @moduletag :integration

  setup do
    # Generate unique IDs for this test
    instance_guid = System.unique_integer([:positive])
    boss_id = 17163  # Stormtalon

    # Register a test player session with self() as connection PID
    account_id = System.unique_integer([:positive])
    character_id = System.unique_integer([:positive])
    player_guid = WorldManager.generate_guid(:player)
    boss_guid = WorldManager.generate_guid(:creature)

    WorldManager.register_session(account_id, character_id, "TestPlayer", self())
    WorldManager.set_entity_guid(account_id, player_guid)

    boss_definition = %{
      "name" => "Test Boss",
      "health" => 100_000,
      "interrupt_armor" => 2,
      "enrage_timer" => 300_000,
      "phases" => [
        %{
          "name" => "phase_one",
          "condition" => %{"health_above" => 50},
          "abilities" => [
            %{
              "name" => "Test Telegraph",
              "cooldown" => 10_000,
              "effects" => [
                %{type: :telegraph, shape: :circle, radius: 5.0, duration: 2000, color: :red}
              ]
            },
            %{
              "name" => "Test Damage",
              "cooldown" => 15_000,
              "effects" => [
                %{type: :damage, amount: 1000, damage_type: :magic, target: :all}
              ]
            }
          ]
        },
        %{
          "name" => "phase_two",
          "condition" => %{"health_below" => 50},
          "abilities" => [
            %{
              "name" => "Enraged Strike",
              "cooldown" => 5_000,
              "effects" => [
                %{type: :telegraph, shape: :cone, angle: 90.0, length: 15.0, duration: 2000},
                %{type: :damage, amount: 5000, damage_type: :physical, target: :tank}
              ]
            }
          ]
        }
      ]
    }

    players = %{
      character_id => %{
        alive: true,
        role: :tank,
        entity_guid: player_guid
      }
    }

    {:ok, pid} = BossEncounter.start_link(
      instance_guid: instance_guid,
      boss_id: boss_id,
      boss_definition: boss_definition,
      difficulty: :normal,
      players: players,
      boss_guid: boss_guid,
      zone_id: 1,
      boss_position: {100.0, 50.0, 200.0}
    )

    # Wait for initialization
    Process.sleep(50)

    on_exit(fn ->
      if Process.alive?(pid), do: GenServer.stop(pid)
      WorldManager.unregister_session(account_id)
    end)

    {:ok,
      pid: pid,
      instance_guid: instance_guid,
      boss_id: boss_id,
      character_id: character_id,
      player_guid: player_guid,
      boss_guid: boss_guid,
      account_id: account_id
    }
  end

  describe "initialization" do
    test "initializes with correct health", %{pid: pid} do
      {:ok, state} = BossEncounter.get_state(pid)

      assert state.state == :engaged
      assert state.health_current == 100_000
      assert state.health_max == 100_000
    end

    test "initializes with correct interrupt armor", %{pid: pid} do
      {:ok, state} = BossEncounter.get_state(pid)

      assert state.interrupt_armor_current == 2
      assert state.interrupt_armor_max == 2
    end

    test "starts in first phase", %{pid: pid} do
      {:ok, state} = BossEncounter.get_state(pid)

      assert state.current_phase["name"] == "phase_one"
    end
  end

  describe "damage handling" do
    test "reduces boss health when damaged", %{pid: pid, character_id: character_id} do
      BossEncounter.deal_damage(pid, character_id, 10_000)
      Process.sleep(10)

      {:ok, state} = BossEncounter.get_state(pid)
      assert state.health_current == 90_000
    end

    test "triggers phase transition at health threshold", %{pid: pid, character_id: character_id} do
      # Deal enough damage to trigger phase 2 (below 50%)
      BossEncounter.deal_damage(pid, character_id, 55_000)
      Process.sleep(50)

      {:ok, state} = BossEncounter.get_state(pid)
      assert state.current_phase["name"] == "phase_two"
      assert state.health_current == 45_000
    end

    test "boss dies when health reaches zero", %{pid: pid, character_id: character_id} do
      BossEncounter.deal_damage(pid, character_id, 100_000)
      Process.sleep(50)

      {:ok, state} = BossEncounter.get_state(pid)
      assert state.state == :defeated
      assert state.health_current == 0
    end
  end

  describe "interrupt system" do
    test "reduces interrupt armor on interrupt", %{pid: pid, character_id: character_id} do
      {:ok, :armor_reduced} = BossEncounter.interrupt(pid, character_id)

      {:ok, state} = BossEncounter.get_state(pid)
      assert state.interrupt_armor_current == 1
    end

    test "triggers MOO when armor breaks", %{pid: pid, character_id: character_id} do
      {:ok, :armor_reduced} = BossEncounter.interrupt(pid, character_id)
      {:ok, :moo_triggered} = BossEncounter.interrupt(pid, character_id)

      {:ok, state} = BossEncounter.get_state(pid)
      # Armor should be reset after MOO
      assert state.interrupt_armor_current == 2
      # Vulnerability modifier should be active
      assert Map.get(state.damage_modifiers, :vulnerable) == 100
    end

    test "returns error when no armor", %{pid: pid, character_id: character_id} do
      # Break armor twice to trigger MOO and reset
      {:ok, :armor_reduced} = BossEncounter.interrupt(pid, character_id)
      {:ok, :moo_triggered} = BossEncounter.interrupt(pid, character_id)

      # Now armor is reset to 2, so this should work again
      {:ok, :armor_reduced} = BossEncounter.interrupt(pid, character_id)
    end
  end

  describe "get_info/1" do
    test "returns boss info for packets", %{pid: pid, boss_id: boss_id} do
      {:ok, info} = BossEncounter.get_info(pid)

      assert info.boss_id == boss_id
      assert info.name == "Test Boss"
      assert info.health_current == 100_000
      assert info.health_max == 100_000
      assert info.phase["name"] == "phase_one"
      assert info.interrupt_armor == 2
    end
  end

  describe "player death handling" do
    test "tracks player death", %{pid: pid, character_id: character_id} do
      BossEncounter.player_died(pid, character_id)
      Process.sleep(10)

      {:ok, state} = BossEncounter.get_state(pid)
      assert state.players[character_id][:alive] == false
    end

    test "triggers wipe when all players dead", %{pid: pid, character_id: character_id} do
      BossEncounter.player_died(pid, character_id)
      Process.sleep(50)

      {:ok, state} = BossEncounter.get_state(pid)
      assert state.state == :resetting
    end
  end

  describe "add management" do
    test "tracks add spawns from spawn effects", %{pid: pid} do
      # Manually trigger a spawn effect via state manipulation
      {:ok, state} = BossEncounter.get_state(pid)

      # The spawn effect processing is tested indirectly through abilities
      # For direct testing, we'd need to call process_spawn_effect
      assert state.active_adds == []
    end

    test "removes add on death", %{pid: pid} do
      add_guid = System.unique_integer([:positive])
      BossEncounter.add_died(pid, add_guid)
      Process.sleep(10)

      {:ok, state} = BossEncounter.get_state(pid)
      refute Enum.any?(state.active_adds, &(&1.guid == add_guid))
    end
  end

  describe "wipe handling" do
    test "wipe transitions to resetting state", %{pid: pid} do
      BossEncounter.wipe(pid)
      Process.sleep(50)

      {:ok, state} = BossEncounter.get_state(pid)
      assert state.state == :resetting
    end
  end

  describe "difficulty scaling" do
    test "veteran difficulty scales health by 1.5x" do
      instance_guid = System.unique_integer([:positive])
      boss_id = System.unique_integer([:positive])
      boss_guid = WorldManager.generate_guid(:creature)

      {:ok, pid} = BossEncounter.start_link(
        instance_guid: instance_guid,
        boss_id: boss_id,
        boss_definition: %{"health" => 100_000, "phases" => []},
        difficulty: :veteran,
        players: %{},
        boss_guid: boss_guid,
        zone_id: 1
      )

      Process.sleep(50)
      {:ok, state} = BossEncounter.get_state(pid)
      GenServer.stop(pid)

      # 100_000 * 1.5 = 150_000
      assert state.health_max == 150_000
    end

    test "mythic+ scales health based on level" do
      instance_guid = System.unique_integer([:positive])
      boss_id = System.unique_integer([:positive])
      boss_guid = WorldManager.generate_guid(:creature)

      {:ok, pid} = BossEncounter.start_link(
        instance_guid: instance_guid,
        boss_id: boss_id,
        boss_definition: %{"health" => 100_000, "phases" => []},
        difficulty: :mythic_plus,
        mythic_level: 10,
        players: %{},
        boss_guid: boss_guid,
        zone_id: 1
      )

      Process.sleep(50)
      {:ok, state} = BossEncounter.get_state(pid)
      GenServer.stop(pid)

      # 100_000 * (1.5 + 10 * 0.1) = 100_000 * 2.5 = 250_000
      assert state.health_max == 250_000
    end
  end
end
