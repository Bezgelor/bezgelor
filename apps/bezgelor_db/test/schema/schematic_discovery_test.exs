defmodule BezgelorDb.Schema.SchematicDiscoveryTest do
  use BezgelorDb.DataCase, async: true

  alias BezgelorDb.Schema.SchematicDiscovery

  describe "changeset/2 for character scope" do
    test "valid with character_id" do
      attrs = %{character_id: 1, schematic_id: 100, variant_id: 0}
      changeset = SchematicDiscovery.changeset(%SchematicDiscovery{}, attrs)
      assert changeset.valid?
    end

    test "invalid without schematic_id" do
      attrs = %{character_id: 1}
      changeset = SchematicDiscovery.changeset(%SchematicDiscovery{}, attrs)
      refute changeset.valid?
    end

    test "defaults variant_id to 0" do
      attrs = %{character_id: 1, schematic_id: 100}
      changeset = SchematicDiscovery.changeset(%SchematicDiscovery{}, attrs)
      assert Ecto.Changeset.get_field(changeset, :variant_id) == 0
    end
  end

  describe "changeset/2 for account scope" do
    test "valid with account_id" do
      attrs = %{account_id: 1, schematic_id: 100, variant_id: 0}
      changeset = SchematicDiscovery.changeset(%SchematicDiscovery{}, attrs)
      assert changeset.valid?
    end
  end

  describe "changeset/2 validation" do
    test "requires either character_id or account_id" do
      attrs = %{schematic_id: 100}
      changeset = SchematicDiscovery.changeset(%SchematicDiscovery{}, attrs)
      refute changeset.valid?
      assert "must have either character_id or account_id" in errors_on(changeset).base
    end
  end
end
