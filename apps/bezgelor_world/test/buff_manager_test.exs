defmodule BezgelorWorld.BuffManagerTest do
  use ExUnit.Case, async: false

  alias BezgelorWorld.BuffManager
  alias BezgelorCore.BuffDebuff

  setup do
    # Start BuffManager if not already running (may be started by application)
    case GenServer.whereis(BuffManager) do
      nil -> start_supervised!(BuffManager)
      _pid -> :already_running
    end

    # Clear any existing state from previous tests
    BuffManager.clear_entity(12345)
    BuffManager.clear_entity(67890)
    BuffManager.clear_entity(99999)
    :ok
  end

  describe "apply_buff/3" do
    test "applies buff to entity and returns expiration timer ref" do
      buff =
        BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :absorb, amount: 100, duration: 10_000})

      {:ok, timer_ref} = BuffManager.apply_buff(12345, buff, 67890)

      assert is_reference(timer_ref)
      assert BuffManager.has_buff?(12345, 1)
    end
  end

  describe "remove_buff/2" do
    test "removes buff from entity" do
      buff =
        BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :absorb, amount: 100, duration: 10_000})

      {:ok, _} = BuffManager.apply_buff(12345, buff, 67890)
      :ok = BuffManager.remove_buff(12345, 1)

      refute BuffManager.has_buff?(12345, 1)
    end

    test "returns error if buff not found" do
      assert {:error, :not_found} = BuffManager.remove_buff(12345, 999)
    end
  end

  describe "has_buff?/2" do
    test "returns true if entity has buff" do
      buff =
        BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :absorb, amount: 100, duration: 10_000})

      {:ok, _} = BuffManager.apply_buff(12345, buff, 67890)

      assert BuffManager.has_buff?(12345, 1)
    end

    test "returns false if entity does not have buff" do
      refute BuffManager.has_buff?(12345, 999)
    end
  end

  describe "get_entity_buffs/1" do
    test "returns list of active buffs" do
      buff1 =
        BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :absorb, amount: 100, duration: 10_000})

      buff2 =
        BuffDebuff.new(%{
          id: 2,
          spell_id: 5,
          buff_type: :stat_modifier,
          stat: :power,
          amount: 50,
          duration: 10_000
        })

      {:ok, _} = BuffManager.apply_buff(12345, buff1, 67890)
      {:ok, _} = BuffManager.apply_buff(12345, buff2, 67890)

      buffs = BuffManager.get_entity_buffs(12345)
      assert length(buffs) == 2
    end

    test "returns empty list for entity with no buffs" do
      assert BuffManager.get_entity_buffs(99999) == []
    end
  end

  describe "get_stat_modifier/2" do
    test "returns total stat modifier" do
      buff1 =
        BuffDebuff.new(%{
          id: 1,
          spell_id: 4,
          buff_type: :stat_modifier,
          stat: :power,
          amount: 50,
          duration: 10_000
        })

      buff2 =
        BuffDebuff.new(%{
          id: 2,
          spell_id: 5,
          buff_type: :stat_modifier,
          stat: :power,
          amount: 25,
          duration: 10_000
        })

      {:ok, _} = BuffManager.apply_buff(12345, buff1, 67890)
      {:ok, _} = BuffManager.apply_buff(12345, buff2, 67890)

      assert BuffManager.get_stat_modifier(12345, :power) == 75
    end
  end

  describe "consume_absorb/2" do
    test "consumes absorb shields" do
      buff =
        BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :absorb, amount: 100, duration: 10_000})

      {:ok, _} = BuffManager.apply_buff(12345, buff, 67890)
      {absorbed, remaining} = BuffManager.consume_absorb(12345, 30)

      assert absorbed == 30
      assert remaining == 0
    end
  end

  describe "clear_entity/1" do
    test "removes all buffs from entity" do
      buff1 =
        BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :absorb, amount: 100, duration: 10_000})

      buff2 =
        BuffDebuff.new(%{
          id: 2,
          spell_id: 5,
          buff_type: :stat_modifier,
          stat: :power,
          amount: 50,
          duration: 10_000
        })

      {:ok, _} = BuffManager.apply_buff(12345, buff1, 67890)
      {:ok, _} = BuffManager.apply_buff(12345, buff2, 67890)
      :ok = BuffManager.clear_entity(12345)

      assert BuffManager.get_entity_buffs(12345) == []
    end
  end

  describe "buff expiration" do
    @tag :slow
    test "buff expires and is removed after duration" do
      # Use short duration for test
      buff = BuffDebuff.new(%{id: 1, spell_id: 4, buff_type: :absorb, amount: 100, duration: 50})

      {:ok, _} = BuffManager.apply_buff(12345, buff, 67890)
      assert BuffManager.has_buff?(12345, 1)

      # Wait for expiration + buffer
      Process.sleep(100)

      refute BuffManager.has_buff?(12345, 1)
    end
  end
end
