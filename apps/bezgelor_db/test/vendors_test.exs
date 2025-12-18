defmodule BezgelorDb.VendorsTest do
  use ExUnit.Case, async: true

  alias BezgelorDb.Schema.VendorStock

  describe "VendorStock schema" do
    test "changeset validates required fields" do
      changeset = VendorStock.changeset(%VendorStock{}, %{})

      refute changeset.valid?
      assert has_error?(changeset, :vendor_id, "can't be blank")
      assert has_error?(changeset, :item_id, "can't be blank")
      assert has_error?(changeset, :quantity_remaining, "can't be blank")
    end

    test "changeset validates quantity >= 0" do
      changeset = VendorStock.changeset(%VendorStock{}, %{
        vendor_id: 1,
        item_id: 100,
        quantity_remaining: -1
      })

      refute changeset.valid?
      # Check for validation error on quantity_remaining
      assert Keyword.has_key?(changeset.errors, :quantity_remaining)
    end

    test "changeset accepts valid data" do
      changeset = VendorStock.changeset(%VendorStock{}, %{
        vendor_id: 1,
        item_id: 100,
        quantity_remaining: 5
      })

      assert changeset.valid?
    end

    test "changeset accepts zero quantity" do
      changeset = VendorStock.changeset(%VendorStock{}, %{
        vendor_id: 1,
        item_id: 100,
        quantity_remaining: 0
      })

      assert changeset.valid?
    end
  end

  # Helper to check if changeset has a specific error
  defp has_error?(changeset, field, message) do
    changeset.errors
    |> Keyword.get_values(field)
    |> Enum.any?(fn {msg, _opts} -> msg == message end)
  end
end
