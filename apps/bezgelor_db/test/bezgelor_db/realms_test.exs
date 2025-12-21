defmodule BezgelorDb.RealmsTest do
  use ExUnit.Case, async: false

  alias BezgelorDb.{Realms, Repo}

  @moduletag :database

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    :ok
  end

  describe "list_realms/0" do
    test "returns empty list when no realms" do
      assert Realms.list_realms() == []
    end

    test "returns all realms" do
      {:ok, _} =
        Realms.create_realm(%{name: "Realm1", address: "127.0.0.1", port: 24000, type: :pve})

      {:ok, _} =
        Realms.create_realm(%{name: "Realm2", address: "127.0.0.2", port: 24001, type: :pvp})

      realms = Realms.list_realms()
      assert length(realms) == 2
    end
  end

  describe "list_online_realms/0" do
    test "returns only online realms" do
      {:ok, _} =
        Realms.create_realm(%{
          name: "Online",
          address: "127.0.0.1",
          port: 24000,
          type: :pve,
          online: true
        })

      {:ok, _} =
        Realms.create_realm(%{
          name: "Offline",
          address: "127.0.0.2",
          port: 24001,
          type: :pve,
          online: false
        })

      realms = Realms.list_online_realms()
      assert length(realms) == 1
      assert hd(realms).name == "Online"
    end
  end

  describe "get_first_online_realm/0" do
    test "returns nil when no online realms" do
      {:ok, _} =
        Realms.create_realm(%{
          name: "Offline",
          address: "127.0.0.1",
          port: 24000,
          type: :pve,
          online: false
        })

      assert Realms.get_first_online_realm() == nil
    end

    test "returns an online realm" do
      {:ok, realm} =
        Realms.create_realm(%{
          name: "Online",
          address: "127.0.0.1",
          port: 24000,
          type: :pve,
          online: true
        })

      result = Realms.get_first_online_realm()
      assert result.id == realm.id
    end
  end

  describe "get_realm/1" do
    test "returns realm by id" do
      {:ok, realm} =
        Realms.create_realm(%{name: "Test", address: "127.0.0.1", port: 24000, type: :pve})

      result = Realms.get_realm(realm.id)
      assert result.name == "Test"
    end

    test "returns nil for non-existent id" do
      assert Realms.get_realm(999) == nil
    end
  end

  describe "get_realm_by_name/1" do
    test "returns realm by name" do
      {:ok, realm} =
        Realms.create_realm(%{name: "Nexus", address: "127.0.0.1", port: 24000, type: :pve})

      result = Realms.get_realm_by_name("Nexus")
      assert result.id == realm.id
    end

    test "returns nil for non-existent name" do
      assert Realms.get_realm_by_name("NonExistent") == nil
    end
  end

  describe "create_realm/1" do
    test "creates a valid realm" do
      attrs = %{name: "NewRealm", address: "192.168.1.1", port: 24000, type: :pve}

      assert {:ok, realm} = Realms.create_realm(attrs)
      assert realm.name == "NewRealm"
      assert realm.address == "192.168.1.1"
      assert realm.port == 24000
      assert realm.type == :pve
      assert realm.online == false
      assert realm.flags == 0
    end

    test "creates pvp realm" do
      attrs = %{name: "PvPRealm", address: "127.0.0.1", port: 24000, type: :pvp}

      assert {:ok, realm} = Realms.create_realm(attrs)
      assert realm.type == :pvp
    end

    test "fails with duplicate name" do
      attrs = %{name: "Duplicate", address: "127.0.0.1", port: 24000, type: :pve}

      {:ok, _} = Realms.create_realm(attrs)
      assert {:error, changeset} = Realms.create_realm(attrs)
      assert "has already been taken" in errors_on(changeset).name
    end

    test "fails with invalid port" do
      attrs = %{name: "InvalidPort", address: "127.0.0.1", port: 0, type: :pve}

      assert {:error, changeset} = Realms.create_realm(attrs)
      assert "must be greater than 0" in errors_on(changeset).port
    end

    test "fails with missing required fields" do
      assert {:error, changeset} = Realms.create_realm(%{})
      errors = errors_on(changeset)
      assert "can't be blank" in errors.name
      assert "can't be blank" in errors.address
      assert "can't be blank" in errors.port
      assert "can't be blank" in errors.type
    end
  end

  describe "update_realm/2" do
    test "updates realm attributes" do
      {:ok, realm} =
        Realms.create_realm(%{name: "Original", address: "127.0.0.1", port: 24000, type: :pve})

      assert {:ok, updated} = Realms.update_realm(realm, %{name: "Updated", port: 24001})
      assert updated.name == "Updated"
      assert updated.port == 24001
    end
  end

  describe "delete_realm/1" do
    test "deletes a realm" do
      {:ok, realm} =
        Realms.create_realm(%{name: "ToDelete", address: "127.0.0.1", port: 24000, type: :pve})

      assert {:ok, _} = Realms.delete_realm(realm)
      assert Realms.get_realm(realm.id) == nil
    end
  end

  describe "set_online/2" do
    test "sets realm online" do
      {:ok, realm} =
        Realms.create_realm(%{
          name: "Offline",
          address: "127.0.0.1",
          port: 24000,
          type: :pve,
          online: false
        })

      assert {:ok, updated} = Realms.set_online(realm, true)
      assert updated.online == true
    end

    test "sets realm offline" do
      {:ok, realm} =
        Realms.create_realm(%{
          name: "Online",
          address: "127.0.0.1",
          port: 24000,
          type: :pve,
          online: true
        })

      assert {:ok, updated} = Realms.set_online(realm, false)
      assert updated.online == false
    end
  end

  describe "ip_to_uint32/1" do
    test "converts localhost correctly" do
      # 127.0.0.1 in big-endian = 0x7F000001 = 2130706433
      assert Realms.ip_to_uint32("127.0.0.1") == 2_130_706_433
    end

    test "converts 192.168.1.1 correctly" do
      # 192.168.1.1 in big-endian = 0xC0A80101 = 3232235777
      assert Realms.ip_to_uint32("192.168.1.1") == 3_232_235_777
    end

    test "converts 0.0.0.0 correctly" do
      assert Realms.ip_to_uint32("0.0.0.0") == 0
    end
  end

  # Helper function to extract errors from changeset
  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
