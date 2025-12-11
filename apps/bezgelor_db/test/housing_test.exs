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

  describe "decor management" do
    setup %{character: character} do
      {:ok, plot} = Housing.create_plot(character.id)
      {:ok, plot: plot}
    end

    test "place_decor adds item to plot", %{plot: plot} do
      assert {:ok, decor} = Housing.place_decor(plot.id, %{
        decor_id: 1001,
        pos_x: 10.5, pos_y: 0.0, pos_z: 5.0,
        is_exterior: true
      })
      assert decor.plot_id == plot.id
      assert decor.decor_id == 1001
      assert decor.pos_x == 10.5
    end

    test "move_decor updates position and rotation", %{plot: plot} do
      {:ok, decor} = Housing.place_decor(plot.id, %{decor_id: 1001})

      assert {:ok, moved} = Housing.move_decor(decor.id, %{
        pos_x: 20.0, pos_y: 5.0, pos_z: 10.0,
        rot_yaw: 90.0, scale: 1.5
      })
      assert moved.pos_x == 20.0
      assert moved.rot_yaw == 90.0
      assert moved.scale == 1.5
    end

    test "remove_decor deletes item", %{plot: plot} do
      {:ok, decor} = Housing.place_decor(plot.id, %{decor_id: 1001})
      assert :ok = Housing.remove_decor(decor.id)
      assert :error = Housing.get_decor(decor.id)
    end

    test "list_decor returns all decor for plot", %{plot: plot} do
      {:ok, _} = Housing.place_decor(plot.id, %{decor_id: 1001, is_exterior: true})
      {:ok, _} = Housing.place_decor(plot.id, %{decor_id: 1002, is_exterior: false})

      decor = Housing.list_decor(plot.id)
      assert length(decor) == 2
    end

    test "list_decor filters by interior/exterior", %{plot: plot} do
      {:ok, _} = Housing.place_decor(plot.id, %{decor_id: 1001, is_exterior: true})
      {:ok, _} = Housing.place_decor(plot.id, %{decor_id: 1002, is_exterior: false})

      exterior = Housing.list_decor(plot.id, :exterior)
      interior = Housing.list_decor(plot.id, :interior)

      assert length(exterior) == 1
      assert length(interior) == 1
    end

    test "count_decor returns count", %{plot: plot} do
      {:ok, _} = Housing.place_decor(plot.id, %{decor_id: 1001})
      {:ok, _} = Housing.place_decor(plot.id, %{decor_id: 1002})

      assert Housing.count_decor(plot.id) == 2
    end
  end

  describe "fabkit management" do
    setup %{character: character} do
      {:ok, plot} = Housing.create_plot(character.id)
      {:ok, plot: plot}
    end

    test "install_fabkit adds to socket", %{plot: plot} do
      assert {:ok, fabkit} = Housing.install_fabkit(plot.id, %{
        socket_index: 0,
        fabkit_id: 2001
      })
      assert fabkit.plot_id == plot.id
      assert fabkit.socket_index == 0
      assert fabkit.fabkit_id == 2001
    end

    test "install_fabkit fails for occupied socket", %{plot: plot} do
      {:ok, _} = Housing.install_fabkit(plot.id, %{socket_index: 0, fabkit_id: 2001})
      assert {:error, _} = Housing.install_fabkit(plot.id, %{socket_index: 0, fabkit_id: 2002})
    end

    test "install_fabkit validates socket range", %{plot: plot} do
      assert {:error, _} = Housing.install_fabkit(plot.id, %{socket_index: 6, fabkit_id: 2001})
      assert {:error, _} = Housing.install_fabkit(plot.id, %{socket_index: -1, fabkit_id: 2001})
    end

    test "remove_fabkit clears socket", %{plot: plot} do
      {:ok, fabkit} = Housing.install_fabkit(plot.id, %{socket_index: 0, fabkit_id: 2001})
      assert :ok = Housing.remove_fabkit(fabkit.id)
      assert :error = Housing.get_fabkit(fabkit.id)
    end

    test "update_fabkit_state modifies state map", %{plot: plot} do
      {:ok, fabkit} = Housing.install_fabkit(plot.id, %{socket_index: 0, fabkit_id: 2001})

      assert {:ok, updated} = Housing.update_fabkit_state(fabkit.id, %{
        "last_harvest" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "harvest_count" => 5
      })
      assert updated.state["harvest_count"] == 5
    end

    test "get_fabkit_at_socket returns fabkit or nil", %{plot: plot} do
      {:ok, _} = Housing.install_fabkit(plot.id, %{socket_index: 2, fabkit_id: 2001})

      assert {:ok, _} = Housing.get_fabkit_at_socket(plot.id, 2)
      assert :error = Housing.get_fabkit_at_socket(plot.id, 0)
    end

    test "list_fabkits returns all fabkits for plot", %{plot: plot} do
      {:ok, _} = Housing.install_fabkit(plot.id, %{socket_index: 0, fabkit_id: 2001})
      {:ok, _} = Housing.install_fabkit(plot.id, %{socket_index: 4, fabkit_id: 2002})

      fabkits = Housing.list_fabkits(plot.id)
      assert length(fabkits) == 2
    end
  end
end
