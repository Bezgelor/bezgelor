defmodule BezgelorDb.Schema.AccountTest do
  use ExUnit.Case, async: true

  alias BezgelorDb.Schema.Account

  describe "changeset/2" do
    test "valid changeset with required fields" do
      attrs = %{
        email: "test@example.com",
        salt: "0102030405060708090A0B0C0D0E0F10",
        verifier: "ABCDEF1234567890"
      }

      changeset = Account.changeset(%Account{}, attrs)
      assert changeset.valid?
    end

    test "invalid without email" do
      attrs = %{salt: "abc", verifier: "def"}
      changeset = Account.changeset(%Account{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).email
    end

    test "invalid with bad email format" do
      attrs = %{email: "notanemail", salt: "abc", verifier: "def"}
      changeset = Account.changeset(%Account{}, attrs)
      refute changeset.valid?
      assert "has invalid format" in errors_on(changeset).email
    end

    test "lowercases email" do
      attrs = %{
        email: "TEST@EXAMPLE.COM",
        salt: "0102030405060708090A0B0C0D0E0F10",
        verifier: "ABCDEF1234567890"
      }

      changeset = Account.changeset(%Account{}, attrs)
      assert changeset.changes.email == "test@example.com"
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
