defmodule BezgelorDb.AccountsTest do
  use ExUnit.Case
  alias BezgelorDb.{Accounts, Repo}
  alias BezgelorDb.Schema.Account

  # Note: These tests require a running database with sandbox
  # They will be skipped if Repo is not available
  @moduletag :database

  setup do
    # Start the repo for testing if not already started
    case Repo.start_link([]) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    # Use a transaction for each test and roll back at the end
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    :ok
  end

  describe "get_by_email/1" do
    test "returns nil when account does not exist" do
      assert Accounts.get_by_email("nonexistent@test.com") == nil
    end

    test "finds account by email (case insensitive)" do
      email = "test#{System.unique_integer([:positive])}@example.com"
      {:ok, account} = create_test_account(email)

      # Should find with exact case
      found = Accounts.get_by_email(email)
      assert found.id == account.id

      # Should find with uppercase
      found_upper = Accounts.get_by_email(String.upcase(email))
      assert found_upper.id == account.id
    end
  end

  describe "get_by_token/2" do
    test "returns nil when token doesn't match" do
      email = "token_test#{System.unique_integer([:positive])}@example.com"
      {:ok, _account} = create_test_account(email)

      assert Accounts.get_by_token(email, "wrong_token") == nil
    end

    test "finds account by email and token" do
      email = "token_test2#{System.unique_integer([:positive])}@example.com"
      token = "test_game_token_#{System.unique_integer()}"
      {:ok, account} = create_test_account(email)
      {:ok, account} = Accounts.update_game_token(account, token)

      found = Accounts.get_by_token(email, token)
      assert found.id == account.id
      assert found.game_token == token
    end
  end

  describe "update_game_token/2" do
    test "updates account game token" do
      email = "game_token_test#{System.unique_integer([:positive])}@example.com"
      {:ok, account} = create_test_account(email)

      token = "new_game_token_#{System.unique_integer()}"
      {:ok, updated} = Accounts.update_game_token(account, token)

      assert updated.game_token == token
    end
  end

  describe "update_session_key/2" do
    test "updates account session key" do
      email = "session_test#{System.unique_integer([:positive])}@example.com"
      {:ok, account} = create_test_account(email)

      key = "session_key_#{System.unique_integer()}"
      {:ok, updated} = Accounts.update_session_key(account, key)

      assert updated.session_key == key
    end
  end

  describe "create_account/2" do
    test "creates account with salt and verifier" do
      email = "new#{System.unique_integer([:positive])}@example.com"
      password = "test_password123"

      {:ok, account} = Accounts.create_account(email, password)

      assert account.email == String.downcase(email)
      assert account.salt != nil
      assert account.verifier != nil
      # 16 bytes hex encoded
      assert String.length(account.salt) == 32
    end

    test "fails with duplicate email" do
      email = "dup#{System.unique_integer([:positive])}@example.com"

      {:ok, _} = Accounts.create_account(email, "pass1")
      {:error, changeset} = Accounts.create_account(email, "pass2")

      assert changeset.errors[:email] != nil
    end
  end

  # Helper to create test accounts
  defp create_test_account(email) do
    salt = Base.encode16(:crypto.strong_rand_bytes(16))
    verifier = Base.encode16(:crypto.strong_rand_bytes(128))

    %Account{}
    |> Account.changeset(%{
      email: email,
      salt: salt,
      verifier: verifier
    })
    |> Repo.insert()
  end
end
