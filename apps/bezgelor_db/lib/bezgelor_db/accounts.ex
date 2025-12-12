defmodule BezgelorDb.Accounts do
  @moduledoc """
  Account management context.

  ## Overview

  This module provides the primary interface for account operations:

  - Looking up accounts by email or token
  - Creating new accounts with SRP6 credentials
  - Updating session information (game tokens, session keys)
  - Checking account suspension status

  ## Usage

      # Look up an account
      account = Accounts.get_by_email("player@example.com")

      # Create a new account
      {:ok, account} = Accounts.create_account("player@example.com", "password")

      # Update session info
      {:ok, account} = Accounts.update_game_token(account, token)

      # Check suspension
      :ok = Accounts.check_suspension(account)
  """

  import Ecto.Query

  alias BezgelorDb.Repo
  alias BezgelorDb.Schema.{Account, AccountSuspension, Character}

  @doc """
  Get an account by email address.

  Email lookup is case-insensitive.

  ## Parameters

  - `email` - The email address to look up

  ## Returns

  - `Account` struct if found
  - `nil` if not found

  ## Example

      account = Accounts.get_by_email("Player@Example.com")
  """
  @spec get_by_email(String.t()) :: Account.t() | nil
  def get_by_email(email) when is_binary(email) do
    Repo.get_by(Account, email: String.downcase(email))
  end

  @doc """
  Get an account by email and game token.

  Used by the Auth Server to validate game tokens issued by the STS Server.

  ## Parameters

  - `email` - The account email address
  - `game_token` - The game token to validate

  ## Returns

  - `Account` struct if found and token matches
  - `nil` if not found or token doesn't match

  ## Example

      account = Accounts.get_by_token("player@example.com", "abc123")
  """
  @spec get_by_token(String.t(), String.t()) :: Account.t() | nil
  def get_by_token(email, game_token) when is_binary(email) and is_binary(game_token) do
    Repo.get_by(Account,
      email: String.downcase(email),
      game_token: game_token
    )
  end

  @doc """
  Update an account's game token.

  Game tokens are issued after successful SRP6 authentication and
  validated by the Auth Server for realm selection.

  ## Parameters

  - `account` - The account to update
  - `token` - The new game token

  ## Returns

  - `{:ok, account}` on success
  - `{:error, changeset}` on failure
  """
  @spec update_game_token(Account.t(), String.t()) :: {:ok, Account.t()} | {:error, Ecto.Changeset.t()}
  def update_game_token(account, token) do
    account
    |> Account.session_changeset(%{game_token: token})
    |> Repo.update()
  end

  @doc """
  Update an account's session key.

  Session keys are used for packet encryption between the client
  and realm/world servers.

  ## Parameters

  - `account` - The account to update
  - `key` - The new session key (hex string)

  ## Returns

  - `{:ok, account}` on success
  - `{:error, changeset}` on failure
  """
  @spec update_session_key(Account.t(), String.t()) :: {:ok, Account.t()} | {:error, Ecto.Changeset.t()}
  def update_session_key(account, key) do
    account
    |> Account.session_changeset(%{session_key: key})
    |> Repo.update()
  end

  @doc """
  Get an account by email and session key.

  Used by the World Server to validate session keys issued by the Realm Server.

  ## Parameters

  - `email` - The account email address
  - `session_key` - The session key to validate (hex string)

  ## Returns

  - `Account` struct if found and session key matches
  - `nil` if not found or session key doesn't match

  ## Example

      account = Accounts.get_by_session_key("player@example.com", "ABC123...")
  """
  @spec get_by_session_key(String.t(), String.t()) :: Account.t() | nil
  def get_by_session_key(email, session_key) when is_binary(email) and is_binary(session_key) do
    Repo.get_by(Account,
      email: String.downcase(email),
      session_key: session_key
    )
  end

  @doc """
  Get an account by ID.

  ## Parameters

  - `id` - The account ID

  ## Returns

  - `Account` struct if found
  - `nil` if not found
  """
  @spec get_by_id(integer()) :: Account.t() | nil
  def get_by_id(id) when is_integer(id) do
    Repo.get(Account, id)
  end

  @doc """
  Create a new account with email and password.

  Generates SRP6 salt and verifier from the password - the password
  itself is never stored.

  ## Parameters

  - `email` - The account email address
  - `password` - The plaintext password

  ## Returns

  - `{:ok, account}` on success
  - `{:error, changeset}` on failure (e.g., duplicate email)

  ## Example

      {:ok, account} = Accounts.create_account("player@example.com", "secret123")
  """
  @spec create_account(String.t(), String.t()) :: {:ok, Account.t()} | {:error, Ecto.Changeset.t()}
  def create_account(email, password) do
    {salt, verifier} = BezgelorCrypto.Password.generate_salt_and_verifier(email, password)

    %Account{}
    |> Account.changeset(%{
      email: email,
      salt: salt,
      verifier: verifier
    })
    |> Repo.insert()
  end

  @doc """
  Check if an account has any active suspensions or bans.

  ## Parameters

  - `account` - The account to check

  ## Returns

  - `:ok` if the account is not suspended
  - `{:error, :account_banned}` if permanently banned
  - `{:error, {:account_suspended, days}}` if temporarily suspended

  ## Example

      case Accounts.check_suspension(account) do
        :ok -> # proceed with authentication
        {:error, :account_banned} -> # reject with ban message
        {:error, {:account_suspended, days}} -> # reject with suspension info
      end
  """
  @spec check_suspension(Account.t()) :: :ok | {:error, :account_banned} | {:error, {:account_suspended, float()}}
  def check_suspension(account) do
    account = Repo.preload(account, :suspensions)

    # Check for permanent ban first
    if Enum.any?(account.suspensions, &AccountSuspension.permanent?/1) do
      {:error, :account_banned}
    else
      # Check for active temporary suspension
      active_suspension = Enum.find(account.suspensions, &AccountSuspension.active?/1)

      if active_suspension do
        days = AccountSuspension.remaining_days(active_suspension)
        {:error, {:account_suspended, days}}
      else
        :ok
      end
    end
  end

  @doc """
  Create a suspension for an account.

  ## Parameters

  - `account` - The account to suspend
  - `reason` - Reason for suspension
  - `duration_days` - Number of days (nil for permanent ban)

  ## Returns

  - `{:ok, suspension}` on success
  - `{:error, changeset}` on failure
  """
  @spec create_suspension(Account.t(), String.t(), non_neg_integer() | nil) ::
          {:ok, AccountSuspension.t()} | {:error, Ecto.Changeset.t()}
  def create_suspension(account, reason, duration_days \\ nil) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    end_time = if duration_days, do: DateTime.add(now, duration_days * 86400, :second)

    %AccountSuspension{}
    |> AccountSuspension.changeset(%{
      account_id: account.id,
      reason: reason,
      start_time: now,
      end_time: end_time
    })
    |> Repo.insert()
  end

  @doc """
  Get an account by character name.

  Used for gifting items to another player by character name.

  ## Parameters

  - `character_name` - The character name to look up

  ## Returns

  - `{:ok, Account}` if found
  - `{:error, :not_found}` if no character with that name exists

  ## Example

      {:ok, account} = Accounts.get_account_by_character_name("PlayerOne")
  """
  @spec get_account_by_character_name(String.t()) :: {:ok, Account.t()} | {:error, :not_found}
  def get_account_by_character_name(character_name) when is_binary(character_name) do
    query =
      from c in Character,
        where: c.name == ^character_name,
        join: a in Account,
        on: a.id == c.account_id,
        select: a

    case Repo.one(query) do
      nil -> {:error, :not_found}
      account -> {:ok, account}
    end
  end
end
