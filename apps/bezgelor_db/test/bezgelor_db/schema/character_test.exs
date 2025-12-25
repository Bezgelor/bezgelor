defmodule BezgelorDb.Schema.CharacterTest do
  use ExUnit.Case, async: true

  alias BezgelorDb.Schema.Character

  describe "changeset/2" do
    test "valid changeset with required fields" do
      attrs = %{
        account_id: 1,
        realm_id: 1,
        name: "TestCharacter",
        sex: 0,
        race: 1,
        class: 1,
        faction_id: 166,
        world_id: 870,
        world_zone_id: 6
      }

      changeset = Character.changeset(%Character{}, attrs)
      assert changeset.valid?
    end

    test "invalid with name too short" do
      attrs = %{
        account_id: 1,
        realm_id: 1,
        name: "AB",
        sex: 0,
        race: 1,
        class: 1,
        faction_id: 166,
        world_id: 870,
        world_zone_id: 6
      }

      changeset = Character.changeset(%Character{}, attrs)
      refute changeset.valid?
      assert "should be at least 3 character(s)" in errors_on(changeset).name
    end

    test "invalid with name too long" do
      attrs = %{
        account_id: 1,
        realm_id: 1,
        name: String.duplicate("a", 25),
        sex: 0,
        race: 1,
        class: 1,
        faction_id: 166,
        world_id: 870,
        world_zone_id: 6
      }

      changeset = Character.changeset(%Character{}, attrs)
      refute changeset.valid?
      assert "should be at most 24 character(s)" in errors_on(changeset).name
    end
  end

  describe "position_changeset/2" do
    test "updates position fields" do
      character = %Character{
        location_x: 0.0,
        location_y: 0.0,
        location_z: 0.0
      }

      attrs = %{location_x: 100.5, location_y: 50.0, location_z: 200.75}
      changeset = Character.position_changeset(character, attrs)

      assert changeset.valid?
      assert changeset.changes.location_x == 100.5
      assert changeset.changes.location_y == 50.0
      assert changeset.changes.location_z == 200.75
    end
  end

  # Helper to extract error messages
  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
