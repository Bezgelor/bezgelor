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

  describe "neighbor management" do
    setup %{account: account, character: character} do
      {:ok, plot} = Housing.create_plot(character.id)

      {:ok, neighbor_char} =
        Characters.create_character(account.id, %{
          name: "Neighbor#{System.unique_integer([:positive])}",
          sex: 0, race: 0, class: 0, faction_id: 166, world_id: 1, world_zone_id: 1
        })

      {:ok, plot: plot, neighbor: neighbor_char}
    end

    test "add_neighbor grants visit permission", %{plot: plot, neighbor: neighbor} do
      assert {:ok, _} = Housing.add_neighbor(plot.id, neighbor.id)
      assert Housing.is_neighbor?(plot.id, neighbor.id)
    end

    test "remove_neighbor revokes permission", %{plot: plot, neighbor: neighbor} do
      {:ok, _} = Housing.add_neighbor(plot.id, neighbor.id)
      assert :ok = Housing.remove_neighbor(plot.id, neighbor.id)
      refute Housing.is_neighbor?(plot.id, neighbor.id)
    end

    test "promote_to_roommate elevates permission", %{plot: plot, neighbor: neighbor} do
      {:ok, _} = Housing.add_neighbor(plot.id, neighbor.id)
      assert {:ok, n} = Housing.promote_to_roommate(plot.id, neighbor.id)
      assert n.is_roommate == true
    end

    test "demote_from_roommate reduces permission", %{plot: plot, neighbor: neighbor} do
      {:ok, _} = Housing.add_neighbor(plot.id, neighbor.id)
      {:ok, _} = Housing.promote_to_roommate(plot.id, neighbor.id)
      assert {:ok, n} = Housing.demote_from_roommate(plot.id, neighbor.id)
      assert n.is_roommate == false
    end

    test "list_neighbors returns all neighbors", %{plot: plot, neighbor: neighbor, account: account} do
      {:ok, neighbor2} =
        Characters.create_character(account.id, %{
          name: "Neighbor2#{System.unique_integer([:positive])}",
          sex: 0, race: 0, class: 0, faction_id: 166, world_id: 1, world_zone_id: 1
        })

      {:ok, _} = Housing.add_neighbor(plot.id, neighbor.id)
      {:ok, _} = Housing.add_neighbor(plot.id, neighbor2.id)

      neighbors = Housing.list_neighbors(plot.id)
      assert length(neighbors) == 2
    end

    test "can_visit? checks permission correctly", %{plot: plot, neighbor: neighbor, character: owner} do
      # Owner can always visit
      assert Housing.can_visit?(plot.id, owner.id)

      # Non-neighbor cannot visit private plot
      refute Housing.can_visit?(plot.id, neighbor.id)

      # Change to neighbors permission level
      {:ok, _} = Housing.set_permission_level(owner.id, :neighbors)

      # Still can't visit without being on neighbor list
      refute Housing.can_visit?(plot.id, neighbor.id)

      # Neighbor can visit after being added
      {:ok, _} = Housing.add_neighbor(plot.id, neighbor.id)
      assert Housing.can_visit?(plot.id, neighbor.id)
    end

    test "can_decorate? checks roommate permission", %{plot: plot, neighbor: neighbor, character: owner} do
      # Owner can always decorate
      assert Housing.can_decorate?(plot.id, owner.id)

      # Neighbor cannot decorate
      {:ok, _} = Housing.add_neighbor(plot.id, neighbor.id)
      refute Housing.can_decorate?(plot.id, neighbor.id)

      # Roommate can decorate
      {:ok, _} = Housing.promote_to_roommate(plot.id, neighbor.id)
      assert Housing.can_decorate?(plot.id, neighbor.id)
    end
  end
end
