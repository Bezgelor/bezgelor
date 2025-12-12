defmodule BezgelorPortal.Auth do
  @moduledoc """
  Authentication context for the Account Portal.

  ## Overview

  This module provides web authentication using the existing SRP6 credentials
  stored in the database. Unlike the game client flow (which uses full SRP6
  handshake), web login simply verifies the password against stored credentials.

  ## Usage

      # Authenticate a user
      case Auth.authenticate("user@example.com", "password") do
        {:ok, account} -> # success
        {:error, :invalid_credentials} -> # wrong email or password
        {:error, :account_banned} -> # permanently banned
        {:error, {:account_suspended, days}} -> # temporarily suspended
      end

      # Get current user from session
      account = Auth.get_current_account(conn)
  """

  alias BezgelorDb.{Accounts, Schema.Account}
  alias BezgelorCrypto.Password

  @session_key :current_account_id

  @doc """
  Authenticate a user by email and password.

  Verifies the password against stored SRP6 credentials and checks
  for any active suspensions or bans.

  ## Parameters

  - `email` - The user's email address
  - `password` - The user's plaintext password

  ## Returns

  - `{:ok, account}` on successful authentication
  - `{:error, :invalid_credentials}` if email not found or password wrong
  - `{:error, :account_banned}` if account is permanently banned
  - `{:error, {:account_suspended, days}}` if account is temporarily suspended
  """
  @spec authenticate(String.t(), String.t()) ::
          {:ok, Account.t()}
          | {:error, :invalid_credentials}
          | {:error, :account_banned}
          | {:error, {:account_suspended, float()}}
  def authenticate(email, password) when is_binary(email) and is_binary(password) do
    with {:ok, account} <- find_account(email),
         :ok <- verify_password(account, password),
         :ok <- check_suspension(account) do
      {:ok, account}
    end
  end

  defp find_account(email) do
    case Accounts.get_by_email(email) do
      nil -> {:error, :invalid_credentials}
      account -> {:ok, account}
    end
  end

  defp verify_password(account, password) do
    if Password.verify_password(account.email, password, account.salt, account.verifier) do
      :ok
    else
      {:error, :invalid_credentials}
    end
  end

  defp check_suspension(account) do
    Accounts.check_suspension(account)
  end

  @doc """
  Log in a user by putting their account ID in the session.

  ## Parameters

  - `conn` - The Plug connection
  - `account` - The authenticated account

  ## Returns

  Updated connection with session set.
  """
  @spec login(Plug.Conn.t(), Account.t()) :: Plug.Conn.t()
  def login(conn, %Account{id: account_id}) do
    conn
    |> Plug.Conn.put_session(@session_key, account_id)
    |> Plug.Conn.configure_session(renew: true)
  end

  @doc """
  Log out the current user by clearing the session.

  ## Parameters

  - `conn` - The Plug connection

  ## Returns

  Updated connection with session cleared.
  """
  @spec logout(Plug.Conn.t()) :: Plug.Conn.t()
  def logout(conn) do
    conn
    |> Plug.Conn.configure_session(drop: true)
  end

  @doc """
  Get the current authenticated account from the session.

  ## Parameters

  - `conn` - The Plug connection

  ## Returns

  - `Account` struct if logged in
  - `nil` if not logged in
  """
  @spec get_current_account(Plug.Conn.t()) :: Account.t() | nil
  def get_current_account(conn) do
    if account_id = Plug.Conn.get_session(conn, @session_key) do
      Accounts.get_by_id(account_id)
    end
  end

  @doc """
  Get the current account ID from the session without loading the account.

  ## Parameters

  - `conn` - The Plug connection

  ## Returns

  - Account ID (integer) if logged in
  - `nil` if not logged in
  """
  @spec get_current_account_id(Plug.Conn.t()) :: integer() | nil
  def get_current_account_id(conn) do
    Plug.Conn.get_session(conn, @session_key)
  end

  @doc """
  Check if a user is logged in.

  ## Parameters

  - `conn` - The Plug connection

  ## Returns

  `true` if logged in, `false` otherwise.
  """
  @spec logged_in?(Plug.Conn.t()) :: boolean()
  def logged_in?(conn) do
    get_current_account_id(conn) != nil
  end
end
