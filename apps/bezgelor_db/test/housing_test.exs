defmodule BezgelorDb.HousingTest do
  use ExUnit.Case

  alias BezgelorDb.{Accounts, Characters, Housing, Repo}

  @moduletag :database

  setup do
    case Repo.start_link([]) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    email = "housing_test#{System.unique_integer([:positive])}@test.com"
    {:ok, account} = Accounts.create_account(email, "password123")

    {:ok, character} =
      Characters.create_character(account.id, %{
        name: "HomeOwner#{System.unique_integer([:positive])}",
        sex: 0, race: 0, class: 0, faction_id: 166, world_id: 1, world_zone_id: 1
      })

    {:ok, account: account, character: character}
  end

  describe "plot lifecycle" do
    test "create_plot creates new plot for character", %{character: character} do
      assert {:ok, plot} = Housing.create_plot(character.id)
      assert plot.character_id == character.id
      assert plot.house_type_id == 1
      assert plot.permission_level == :private
    end

    test "create_plot fails for duplicate character", %{character: character} do
      {:ok, _} = Housing.create_plot(character.id)
      assert {:error, _} = Housing.create_plot(character.id)
    end

    test "get_plot returns plot with preloads", %{character: character} do
      {:ok, _} = Housing.create_plot(character.id)
      assert {:ok, plot} = Housing.get_plot(character.id)
      assert plot.character_id == character.id
      assert is_list(plot.decor)
      assert is_list(plot.fabkits)
    end

    test "get_plot returns error for nonexistent", %{character: _character} do
      assert :error = Housing.get_plot(999999)
    end

    test "upgrade_house changes house type", %{character: character} do
      {:ok, _} = Housing.create_plot(character.id)
      assert {:ok, plot} = Housing.upgrade_house(character.id, 2)
      assert plot.house_type_id == 2
    end

    test "update_plot_theme changes theme settings", %{character: character} do
      {:ok, _} = Housing.create_plot(character.id)
      assert {:ok, plot} = Housing.update_plot_theme(character.id, %{sky_id: 5, plot_name: "My Palace"})
      assert plot.sky_id == 5
      assert plot.plot_name == "My Palace"
    end

    test "set_permission_level changes permission", %{character: character} do
      {:ok, _} = Housing.create_plot(character.id)
      assert {:ok, plot} = Housing.set_permission_level(character.id, :public)
      assert plot.permission_level == :public
    end
  end
end
