defmodule BezgelorDb.ReputationTest do
  use ExUnit.Case

  alias BezgelorDb.{Accounts, Characters, Repo, Reputation}

  @moduletag :database

  setup do
    case Repo.start_link([]) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    # Create test account and character
    email = "rep_test#{System.unique_integer([:positive])}@test.com"
    {:ok, account} = Accounts.create_account(email, "password123")

    {:ok, character} =
      Characters.create_character(account.id, %{
        name: "RepTester#{System.unique_integer([:positive])}",
        sex: 0,
        race: 0,
        class: 0,
        faction_id: 166,
        world_id: 1,
        world_zone_id: 1
      })

    {:ok, account: account, character: character}
  end

  describe "get_reputations/1" do
    test "returns empty list for character with no reputation", %{character: character} do
      assert Reputation.get_reputations(character.id) == []
    end

    test "returns all reputations for character", %{character: character} do
      Reputation.set_reputation(character.id, 100, 1000)
      Reputation.set_reputation(character.id, 101, 5000)

      reps = Reputation.get_reputations(character.id)
      assert length(reps) == 2
    end
  end

  describe "get_standing/2" do
    test "returns 0 for unknown faction", %{character: character} do
      assert Reputation.get_standing(character.id, 999) == 0
    end

    test "returns correct standing", %{character: character} do
      Reputation.set_reputation(character.id, 100, 5000)
      assert Reputation.get_standing(character.id, 100) == 5000
    end
  end

  describe "get_level/2" do
    test "returns neutral for unknown faction", %{character: character} do
      assert Reputation.get_level(character.id, 999) == :neutral
    end

    test "returns correct level based on standing", %{character: character} do
      # Friendly: 3000-9000
      Reputation.set_reputation(character.id, 100, 5000)
      assert Reputation.get_level(character.id, 100) == :friendly

      # Honored: 9000-21000
      Reputation.set_reputation(character.id, 100, 15000)
      assert Reputation.get_level(character.id, 100) == :honored

      # Hostile: -6000 to -3000
      Reputation.set_reputation(character.id, 101, -4000)
      assert Reputation.get_level(character.id, 101) == :hostile
    end
  end

  describe "modify_reputation/3" do
    test "creates new reputation if none exists", %{character: character} do
      {:ok, rep} = Reputation.modify_reputation(character.id, 100, 500)
      assert rep.standing == 500
    end

    test "adds to existing reputation", %{character: character} do
      Reputation.set_reputation(character.id, 100, 1000)
      {:ok, rep} = Reputation.modify_reputation(character.id, 100, 500)
      assert rep.standing == 1500
    end

    test "subtracts from existing reputation", %{character: character} do
      Reputation.set_reputation(character.id, 100, 1000)
      {:ok, rep} = Reputation.modify_reputation(character.id, 100, -500)
      assert rep.standing == 500
    end

    test "clamps to max standing", %{character: character} do
      {:ok, rep} = Reputation.modify_reputation(character.id, 100, 100_000)
      assert rep.standing == 42000
    end

    test "clamps to min standing", %{character: character} do
      {:ok, rep} = Reputation.modify_reputation(character.id, 100, -100_000)
      assert rep.standing == -42000
    end
  end

  describe "set_reputation/3" do
    test "creates new reputation", %{character: character} do
      {:ok, rep} = Reputation.set_reputation(character.id, 100, 5000)
      assert rep.standing == 5000
    end

    test "updates existing reputation", %{character: character} do
      Reputation.set_reputation(character.id, 100, 1000)
      {:ok, rep} = Reputation.set_reputation(character.id, 100, 9999)
      assert rep.standing == 9999
    end
  end

  describe "meets_requirement?/3" do
    test "returns true when requirement is met", %{character: character} do
      Reputation.set_reputation(character.id, 100, 10000)
      assert Reputation.meets_requirement?(character.id, 100, :friendly)
      assert Reputation.meets_requirement?(character.id, 100, :honored)
    end

    test "returns false when requirement is not met", %{character: character} do
      Reputation.set_reputation(character.id, 100, 5000)
      refute Reputation.meets_requirement?(character.id, 100, :honored)
    end
  end

  describe "get_vendor_discount/2" do
    test "returns 0 for neutral reputation", %{character: character} do
      Reputation.set_reputation(character.id, 100, 1000)
      assert Reputation.get_vendor_discount(character.id, 100) == 0.0
    end

    test "returns correct discount for friendly", %{character: character} do
      Reputation.set_reputation(character.id, 100, 5000)
      assert Reputation.get_vendor_discount(character.id, 100) == 0.05
    end

    test "returns correct discount for exalted", %{character: character} do
      Reputation.set_reputation(character.id, 100, 42000)
      assert Reputation.get_vendor_discount(character.id, 100) == 0.20
    end
  end

  describe "can_purchase?/2" do
    test "returns false for hostile reputation", %{character: character} do
      Reputation.set_reputation(character.id, 100, -4000)
      refute Reputation.can_purchase?(character.id, 100)
    end

    test "returns false for unfriendly reputation", %{character: character} do
      Reputation.set_reputation(character.id, 100, -1000)
      refute Reputation.can_purchase?(character.id, 100)
    end

    test "returns true for neutral reputation", %{character: character} do
      Reputation.set_reputation(character.id, 100, 1000)
      assert Reputation.can_purchase?(character.id, 100)
    end
  end

  describe "can_interact?/2" do
    test "returns false for hated reputation", %{character: character} do
      Reputation.set_reputation(character.id, 100, -40000)
      refute Reputation.can_interact?(character.id, 100)
    end

    test "returns true for unfriendly reputation", %{character: character} do
      Reputation.set_reputation(character.id, 100, -1000)
      assert Reputation.can_interact?(character.id, 100)
    end
  end
end
