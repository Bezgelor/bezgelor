defmodule BezgelorDb.MountsTest do
  use ExUnit.Case

  alias BezgelorDb.{Accounts, Characters, Collections, Mounts, Repo}

  @moduletag :database

  setup do
    case Repo.start_link([]) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    email = "mount_test#{System.unique_integer([:positive])}@test.com"
    {:ok, account} = Accounts.create_account(email, "password123")

    {:ok, character} =
      Characters.create_character(account.id, %{
        name: "Rider#{System.unique_integer([:positive])}",
        sex: 0,
        race: 0,
        class: 0,
        faction_id: 166,
        world_id: 1,
        world_zone_id: 1
      })

    # Unlock a mount for tests
    {:ok, _} = Collections.unlock_account_mount(account.id, 1001, "purchase")

    {:ok, account: account, character: character}
  end

  describe "active mount" do
    test "set_active_mount activates mount", %{account: account, character: character} do
      {:ok, mount} = Mounts.set_active_mount(character.id, account.id, 1001)
      assert mount.mount_id == 1001
    end

    test "get_active_mount returns current mount", %{account: account, character: character} do
      {:ok, _} = Mounts.set_active_mount(character.id, account.id, 1001)
      mount = Mounts.get_active_mount(character.id)
      assert mount.mount_id == 1001
    end

    test "set_active_mount fails if not owned", %{account: account, character: character} do
      {:error, :not_owned} = Mounts.set_active_mount(character.id, account.id, 9999)
    end

    test "clear_active_mount removes mount", %{account: account, character: character} do
      {:ok, _} = Mounts.set_active_mount(character.id, account.id, 1001)
      :ok = Mounts.clear_active_mount(character.id)
      assert Mounts.get_active_mount(character.id) == nil
    end
  end

  describe "customization" do
    test "update_customization changes mount look", %{account: account, character: character} do
      {:ok, _} = Mounts.set_active_mount(character.id, account.id, 1001)

      {:ok, mount} =
        Mounts.update_customization(character.id, %{
          "dyes" => [1, 2, 3],
          "flair" => ["flag_01"]
        })

      assert mount.customization["dyes"] == [1, 2, 3]
    end
  end
end
