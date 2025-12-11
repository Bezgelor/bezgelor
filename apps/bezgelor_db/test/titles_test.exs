defmodule BezgelorDb.TitlesTest do
  use ExUnit.Case

  alias BezgelorDb.{Accounts, Repo, Titles}

  @moduletag :database

  setup do
    case Repo.start_link([]) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    email = "titles_test#{System.unique_integer([:positive])}@test.com"
    {:ok, account} = Accounts.create_account(email, "password123")

    {:ok, account: account}
  end

  describe "get_titles/1" do
    test "returns empty list for account with no titles", %{account: account} do
      assert Titles.get_titles(account.id) == []
    end

    test "returns all titles for account", %{account: account} do
      {:ok, _} = Titles.grant_title(account.id, 1001)
      {:ok, _} = Titles.grant_title(account.id, 1002)

      titles = Titles.get_titles(account.id)
      assert length(titles) == 2
    end
  end

  describe "has_title?/2" do
    test "returns false for unowned title", %{account: account} do
      refute Titles.has_title?(account.id, 9999)
    end

    test "returns true for owned title", %{account: account} do
      {:ok, _} = Titles.grant_title(account.id, 1001)
      assert Titles.has_title?(account.id, 1001)
    end
  end

  describe "grant_title/2" do
    test "creates new title", %{account: account} do
      assert {:ok, title} = Titles.grant_title(account.id, 1001)
      assert title.title_id == 1001
      assert title.account_id == account.id
      assert title.unlocked_at != nil
    end

    test "returns already_owned for duplicate", %{account: account} do
      {:ok, first} = Titles.grant_title(account.id, 1001)
      assert {:already_owned, ^first} = Titles.grant_title(account.id, 1001)
    end
  end

  describe "set_active_title/2" do
    test "sets active title when owned", %{account: account} do
      {:ok, _} = Titles.grant_title(account.id, 1001)
      assert {:ok, account} = Titles.set_active_title(account.id, 1001)
      assert account.active_title_id == 1001
    end

    test "returns error when not owned", %{account: account} do
      assert {:error, :not_owned} = Titles.set_active_title(account.id, 9999)
    end

    test "clears active title with nil", %{account: account} do
      {:ok, _} = Titles.grant_title(account.id, 1001)
      {:ok, _} = Titles.set_active_title(account.id, 1001)
      assert {:ok, account} = Titles.set_active_title(account.id, nil)
      assert account.active_title_id == nil
    end
  end

  describe "get_active_title/1" do
    test "returns nil when no active title", %{account: account} do
      assert Titles.get_active_title(account.id) == nil
    end

    test "returns active title id", %{account: account} do
      {:ok, _} = Titles.grant_title(account.id, 1001)
      {:ok, _} = Titles.set_active_title(account.id, 1001)
      assert Titles.get_active_title(account.id) == 1001
    end
  end
end
