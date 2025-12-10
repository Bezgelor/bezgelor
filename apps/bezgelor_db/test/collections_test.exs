defmodule BezgelorDb.CollectionsTest do
  use ExUnit.Case

  alias BezgelorDb.{Accounts, Characters, Collections, Repo}

  @moduletag :database

  setup do
    case Repo.start_link([]) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    email = "collection_test#{System.unique_integer([:positive])}@test.com"
    {:ok, account} = Accounts.create_account(email, "password123")

    {:ok, character} =
      Characters.create_character(account.id, %{
        name: "Collector#{System.unique_integer([:positive])}",
        sex: 0, race: 0, class: 0, faction_id: 166, world_id: 1, world_zone_id: 1
      })

    {:ok, account: account, character: character}
  end

  describe "account collections" do
    test "unlock_account_mount adds mount", %{account: account} do
      {:ok, collection} = Collections.unlock_account_mount(account.id, 1001, "purchase")
      assert collection.collectible_id == 1001
    end

    test "get_account_mounts returns mounts", %{account: account} do
      {:ok, _} = Collections.unlock_account_mount(account.id, 1001, "purchase")
      {:ok, _} = Collections.unlock_account_mount(account.id, 1002, "achievement")

      mounts = Collections.get_account_mounts(account.id)
      assert length(mounts) == 2
    end

    test "owns_mount? checks ownership", %{account: account, character: character} do
      refute Collections.owns_mount?(account.id, character.id, 1001)

      {:ok, _} = Collections.unlock_account_mount(account.id, 1001, "purchase")

      assert Collections.owns_mount?(account.id, character.id, 1001)
    end
  end

  describe "character collections" do
    test "unlock_character_mount adds mount", %{character: character} do
      {:ok, collection} = Collections.unlock_character_mount(character.id, 2001, "quest")
      assert collection.collectible_id == 2001
    end

    test "get_all_mounts merges account and character", %{account: account, character: character} do
      {:ok, _} = Collections.unlock_account_mount(account.id, 1001, "purchase")
      {:ok, _} = Collections.unlock_character_mount(character.id, 2001, "quest")

      mounts = Collections.get_all_mounts(account.id, character.id)
      assert length(mounts) == 2
    end
  end

  describe "pets" do
    test "unlock_account_pet adds pet", %{account: account} do
      {:ok, collection} = Collections.unlock_account_pet(account.id, 3001, "purchase")
      assert collection.collectible_id == 3001
    end

    test "owns_pet? checks ownership", %{account: account, character: character} do
      refute Collections.owns_pet?(account.id, character.id, 3001)

      {:ok, _} = Collections.unlock_character_pet(character.id, 3001, "drop")

      assert Collections.owns_pet?(account.id, character.id, 3001)
    end
  end
end
