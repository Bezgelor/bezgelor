defmodule BezgelorDb.Schema.WorkOrderTest do
  use ExUnit.Case, async: true

  alias BezgelorDb.Schema.WorkOrder

  describe "changeset/2" do
    test "valid with required fields" do
      expires = DateTime.add(DateTime.utc_now(), 86400, :second)

      attrs = %{
        character_id: 1,
        work_order_id: 100,
        profession_id: 1,
        quantity_required: 5,
        expires_at: expires
      }

      changeset = WorkOrder.changeset(%WorkOrder{}, attrs)
      assert changeset.valid?
    end

    test "defaults status to active" do
      expires = DateTime.add(DateTime.utc_now(), 86400, :second)

      attrs = %{
        character_id: 1,
        work_order_id: 100,
        profession_id: 1,
        quantity_required: 5,
        expires_at: expires
      }

      changeset = WorkOrder.changeset(%WorkOrder{}, attrs)
      assert Ecto.Changeset.get_field(changeset, :status) == :active
    end

    test "defaults quantity_completed to 0" do
      expires = DateTime.add(DateTime.utc_now(), 86400, :second)

      attrs = %{
        character_id: 1,
        work_order_id: 100,
        profession_id: 1,
        quantity_required: 5,
        expires_at: expires
      }

      changeset = WorkOrder.changeset(%WorkOrder{}, attrs)
      assert Ecto.Changeset.get_field(changeset, :quantity_completed) == 0
    end
  end

  describe "progress_changeset/2" do
    test "updates quantity_completed" do
      order = %WorkOrder{quantity_completed: 2}
      changeset = WorkOrder.progress_changeset(order, 3)
      assert Ecto.Changeset.get_change(changeset, :quantity_completed) == 3
    end
  end

  describe "complete_changeset/1" do
    test "sets status to completed" do
      order = %WorkOrder{status: :active}
      changeset = WorkOrder.complete_changeset(order)
      assert Ecto.Changeset.get_change(changeset, :status) == :completed
    end
  end

  describe "expire_changeset/1" do
    test "sets status to expired" do
      order = %WorkOrder{status: :active}
      changeset = WorkOrder.expire_changeset(order)
      assert Ecto.Changeset.get_change(changeset, :status) == :expired
    end
  end
end
