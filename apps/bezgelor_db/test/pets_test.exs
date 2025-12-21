defmodule BezgelorDb.PetsTest do
  use ExUnit.Case

  alias BezgelorDb.{Accounts, Characters, Collections, Pets, Repo}

  @moduletag :database

  setup do
    case Repo.start_link([]) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    email = "pet_test#{System.unique_integer([:positive])}@test.com"
    {:ok, account} = Accounts.create_account(email, "password123")

    {:ok, character} =
      Characters.create_character(account.id, %{
        name: "PetOwner#{System.unique_integer([:positive])}",
        sex: 0,
        race: 0,
        class: 0,
        faction_id: 166,
        world_id: 1,
        world_zone_id: 1
      })

    {:ok, _} = Collections.unlock_account_pet(account.id, 2001, "purchase")

    {:ok, account: account, character: character}
  end

  describe "active pet" do
    test "set_active_pet summons pet", %{account: account, character: character} do
      {:ok, pet} = Pets.set_active_pet(character.id, account.id, 2001)
      assert pet.pet_id == 2001
      assert pet.level == 1
    end

    test "get_active_pet returns current pet", %{account: account, character: character} do
      {:ok, _} = Pets.set_active_pet(character.id, account.id, 2001)
      pet = Pets.get_active_pet(character.id)
      assert pet.pet_id == 2001
    end

    test "clear_active_pet dismisses pet", %{account: account, character: character} do
      {:ok, _} = Pets.set_active_pet(character.id, account.id, 2001)
      :ok = Pets.clear_active_pet(character.id)
      assert Pets.get_active_pet(character.id) == nil
    end
  end

  describe "pet progression" do
    test "award_pet_xp increases XP", %{account: account, character: character} do
      {:ok, _} = Pets.set_active_pet(character.id, account.id, 2001)
      {:ok, pet, :xp_gained} = Pets.award_pet_xp(character.id, 50)
      assert pet.xp == 50
    end

    test "award_pet_xp triggers level up", %{account: account, character: character} do
      {:ok, _} = Pets.set_active_pet(character.id, account.id, 2001)
      # Default level curve: 100 XP for level 2
      {:ok, pet, :level_up} = Pets.award_pet_xp(character.id, 150)
      assert pet.level == 2
      # Leftover after level up
      assert pet.xp == 50
    end

    test "set_nickname changes pet name", %{account: account, character: character} do
      {:ok, _} = Pets.set_active_pet(character.id, account.id, 2001)
      {:ok, pet} = Pets.set_nickname(character.id, "Fluffy")
      assert pet.nickname == "Fluffy"
    end
  end
end
