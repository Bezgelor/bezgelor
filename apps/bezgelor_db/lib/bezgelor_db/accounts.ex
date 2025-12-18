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

  # Maximum limit for list queries to prevent abuse
  @max_query_limit 500

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
    |> Account.session_changeset(%{
      session_key: key,
      session_key_created_at: DateTime.utc_now()
    })
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

  # Session TTL: 30 minutes (reduced from 1 hour for security)
  @session_ttl_seconds 1800

  @doc """
  Validate a session key with expiration checking.

  Used by the World Server to validate session keys issued by the Realm Server.
  Rejects sessions that are older than the configured TTL (default: 1 hour).

  ## Parameters

  - `email` - The account email address
  - `session_key` - The session key to validate (hex string)

  ## Returns

  - `{:ok, account}` if session is valid and not expired
  - `{:error, :session_not_found}` if no matching session
  - `{:error, :session_expired}` if session has expired

  ## Example

      case Accounts.validate_session_key("player@example.com", "ABC123...") do
        {:ok, account} -> # proceed with authentication
        {:error, :session_expired} -> # request re-login
        {:error, :session_not_found} -> # invalid credentials
      end
  """
  @spec validate_session_key(String.t(), String.t()) ::
          {:ok, Account.t()} | {:error, :session_not_found | :session_expired}
  def validate_session_key(email, session_key) when is_binary(email) and is_binary(session_key) do
    case get_by_session_key(email, session_key) do
      nil ->
        {:error, :session_not_found}

      account ->
        if session_expired?(account) do
          # Clear the expired session key
          clear_session_key(account)
          {:error, :session_expired}
        else
          {:ok, account}
        end
    end
  end

  @doc """
  Validate a session key with account ID verification (atomic).

  This function validates the session key AND account ID in a single database
  query to prevent race conditions where the account could change between
  session validation and account ID verification.

  ## Parameters

  - `email` - The account email address
  - `session_key` - The session key to validate (hex string)
  - `account_id` - The expected account ID

  ## Returns

  - `{:ok, account}` if session is valid, not expired, and account ID matches
  - `{:error, :session_not_found}` if no matching session
  - `{:error, :session_expired}` if session has expired
  - `{:error, :account_mismatch}` if account ID doesn't match
  """
  @spec validate_session_key_with_account(String.t(), String.t(), integer()) ::
          {:ok, Account.t()} | {:error, :session_not_found | :session_expired | :account_mismatch}
  def validate_session_key_with_account(email, session_key, account_id)
      when is_binary(email) and is_binary(session_key) and is_integer(account_id) do
    # Query with all three parameters atomically
    query =
      from a in Account,
        where: a.email == ^String.downcase(email) and a.session_key == ^session_key and a.id == ^account_id

    case Repo.one(query) do
      nil ->
        # Determine specific error - check if session exists but ID mismatches
        case get_by_session_key(email, session_key) do
          nil -> {:error, :session_not_found}
          _account -> {:error, :account_mismatch}
        end

      account ->
        if session_expired?(account) do
          clear_session_key(account)
          {:error, :session_expired}
        else
          {:ok, account}
        end
    end
  end

  @doc """
  Check if a session has expired.
  """
  @spec session_expired?(Account.t()) :: boolean()
  def session_expired?(%Account{session_key_created_at: nil}), do: true

  def session_expired?(%Account{session_key_created_at: created_at}) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, created_at, :second)
    diff > @session_ttl_seconds
  end

  @doc """
  Clear the session key for an account.
  """
  @spec clear_session_key(Account.t()) :: {:ok, Account.t()} | {:error, Ecto.Changeset.t()}
  def clear_session_key(account) do
    account
    |> Account.session_changeset(%{session_key: nil, session_key_created_at: nil})
    |> Repo.update()
  end

  @doc """
  Refresh the session timestamp for sliding window expiration.

  Call this periodically during active sessions to extend the TTL.
  The session key remains the same, only the timestamp is updated.
  """
  @spec refresh_session(Account.t()) :: {:ok, Account.t()} | {:error, Ecto.Changeset.t()}
  def refresh_session(account) do
    account
    |> Account.session_changeset(%{session_key_created_at: DateTime.utc_now()})
    |> Repo.update()
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
  itself is never stored. Assigns the default Player role which includes
  Signature tier features.

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
    # Note: This function creates accounts without requiring email verification.
    # It is intended for administrative/testing use only (e.g., seeding test data).
    # Production accounts must be created via register_account/2 through the
    # web portal, which requires email verification.
    {salt, verifier} = BezgelorCrypto.Password.generate_salt_and_verifier(email, password)

    Repo.transaction(
      fn ->
        case %Account{}
             |> Account.changeset(%{email: email, salt: salt, verifier: verifier})
             |> Repo.insert() do
          {:ok, account} ->
            assign_default_role(account)
            account

          {:error, changeset} ->
            Repo.rollback(changeset)
        end
      end,
      timeout: :timer.seconds(30)
    )
  end

  @doc """
  Register a new account (for web portal).

  Creates an account with `email_verified_at: nil`. The account exists but
  should not be allowed to play until email is verified. Assigns the default
  Player role which includes Signature tier features.

  ## Parameters

  - `email` - The account email address
  - `password` - The plaintext password

  ## Returns

  - `{:ok, account}` on success
  - `{:error, changeset}` on failure (e.g., duplicate email, validation error)

  ## Example

      {:ok, account} = Accounts.register_account("player@example.com", "secret123")
      # account.email_verified_at is nil
  """
  @spec register_account(String.t(), String.t()) :: {:ok, Account.t()} | {:error, Ecto.Changeset.t()}
  def register_account(email, password) do
    {salt, verifier} = BezgelorCrypto.Password.generate_salt_and_verifier(email, password)

    Repo.transaction(
      fn ->
        case %Account{}
             |> Account.registration_changeset(%{email: email, salt: salt, verifier: verifier})
             |> Repo.insert() do
          {:ok, account} ->
            assign_default_role(account)
            account

          {:error, changeset} ->
            Repo.rollback(changeset)
        end
      end,
      timeout: :timer.seconds(30)
    )
  end

  @doc """
  Mark an account's email as verified.

  ## Parameters

  - `account` - The account to verify

  ## Returns

  - `{:ok, account}` on success
  - `{:error, changeset}` on failure
  """
  @spec verify_email(Account.t()) :: {:ok, Account.t()} | {:error, Ecto.Changeset.t()}
  def verify_email(account) do
    account
    |> Ecto.Changeset.change(%{
      email_verified_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.update()
  end

  @doc """
  Check if an account's email has been verified.

  ## Parameters

  - `account` - The account to check

  ## Returns

  `true` if email is verified, `false` otherwise.
  """
  @spec email_verified?(Account.t()) :: boolean()
  def email_verified?(%Account{email_verified_at: nil}), do: false
  def email_verified?(%Account{email_verified_at: _}), do: true

  @doc """
  Check if an email address is already registered.

  ## Parameters

  - `email` - The email address to check

  ## Returns

  `true` if the email is already registered, `false` otherwise.
  """
  @spec email_exists?(String.t()) :: boolean()
  def email_exists?(email) when is_binary(email) do
    get_by_email(email) != nil
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

  @doc """
  Update an account's password.

  Generates new SRP6 salt and verifier from the new password.

  ## Parameters

  - `account` - The account to update
  - `new_password` - The new plaintext password

  ## Returns

  - `{:ok, account}` on success
  - `{:error, changeset}` on failure

  ## Example

      {:ok, account} = Accounts.update_password(account, "new_secret123")
  """
  @spec update_password(Account.t(), String.t()) :: {:ok, Account.t()} | {:error, Ecto.Changeset.t()}
  def update_password(account, new_password) do
    {salt, verifier} = BezgelorCrypto.Password.generate_salt_and_verifier(account.email, new_password)

    account
    |> Ecto.Changeset.change(%{salt: salt, verifier: verifier})
    |> Repo.update()
  end

  @doc """
  Update an account's email address.

  ## Parameters

  - `account` - The account to update
  - `new_email` - The new email address

  ## Returns

  - `{:ok, account}` on success
  - `{:error, changeset}` on failure
  """
  @spec update_email(Account.t(), String.t()) :: {:ok, Account.t()} | {:error, Ecto.Changeset.t()}
  def update_email(account, new_email) do
    # Update email and regenerate SRP6 credentials (email is part of the salt derivation)
    # Note: This means the user will need to use the new email to log in
    # We need to keep the same password, but we don't have it stored
    # For now, just update the email - the user will need to reset their password
    # after changing email if we want to be strict about SRP6

    account
    |> Ecto.Changeset.change(%{
      email: String.downcase(new_email),
      email_verified_at: nil  # Require re-verification
    })
    |> Ecto.Changeset.unique_constraint(:email)
    |> Repo.update()
  end

  @doc """
  Soft delete an account.

  Marks the account as deleted by setting `deleted_at` timestamp.
  The account data will be anonymized after a retention period.

  ## Parameters

  - `account` - The account to delete

  ## Returns

  - `{:ok, account}` on success
  - `{:error, changeset}` on failure
  """
  @spec soft_delete_account(Account.t()) :: {:ok, Account.t()} | {:error, Ecto.Changeset.t()}
  def soft_delete_account(account) do
    account
    |> Ecto.Changeset.change(%{
      deleted_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.update()
  end

  @doc """
  Check if an account is deleted.

  ## Parameters

  - `account` - The account to check

  ## Returns

  `true` if the account is deleted, `false` otherwise.
  """
  @spec deleted?(Account.t()) :: boolean()
  def deleted?(%Account{deleted_at: nil}), do: false
  def deleted?(%Account{deleted_at: _}), do: true

  # ============================================================================
  # Default Role Assignment
  # ============================================================================

  # Default role name for new accounts
  @default_role_name "Player"

  @doc false
  defp assign_default_role(account) do
    alias BezgelorDb.Authorization

    case Authorization.get_role_by_name(@default_role_name) do
      nil ->
        # Player role doesn't exist yet (seeds not run), skip silently
        :ok

      role ->
        Authorization.assign_role(account, role, nil)
    end
  end

  @doc """
  Assign the default Player role to an existing account.

  Use this to grant Signature tier features to accounts created
  before the default role assignment was added.

  ## Parameters

  - `account` - The account to grant the role to

  ## Returns

  - `{:ok, account_role}` on success
  - `{:error, :already_assigned}` if already has role
  - `{:error, :role_not_found}` if Player role doesn't exist
  """
  @spec grant_default_role(Account.t()) ::
          {:ok, term()} | {:error, :already_assigned | :role_not_found | term()}
  def grant_default_role(account) do
    alias BezgelorDb.Authorization

    case Authorization.get_role_by_name(@default_role_name) do
      nil -> {:error, :role_not_found}
      role -> Authorization.assign_role(account, role, nil)
    end
  end

  # ============================================================================
  # Admin Statistics
  # ============================================================================

  @doc """
  Count total accounts.

  ## Options

  - `:include_deleted` - Include soft-deleted accounts (default: false)

  ## Returns

  Integer count of accounts.
  """
  @spec count_accounts(keyword()) :: integer()
  def count_accounts(opts \\ []) do
    include_deleted = Keyword.get(opts, :include_deleted, false)

    query = from(a in Account)

    query =
      if include_deleted do
        query
      else
        from(a in query, where: is_nil(a.deleted_at))
      end

    Repo.aggregate(query, :count)
  end

  @doc """
  Count total characters across all accounts.

  ## Options

  - `:include_deleted` - Include soft-deleted characters (default: false)

  ## Returns

  Integer count of characters.
  """
  @spec count_characters(keyword()) :: integer()
  def count_characters(opts \\ []) do
    include_deleted = Keyword.get(opts, :include_deleted, false)

    query = from(c in Character)

    query =
      if include_deleted do
        query
      else
        from(c in query, where: is_nil(c.deleted_at))
      end

    Repo.aggregate(query, :count)
  end

  @doc """
  List all accounts with optional filtering and pagination.

  ## Options

  - `:search` - Search term for email
  - `:limit` - Maximum results (default: 50, max: 500)
  - `:offset` - Offset for pagination (default: 0, must be non-negative)
  - `:include_deleted` - Include deleted accounts (default: false)

  ## Returns

  List of accounts.

  ## Security

  The limit is capped at #{@max_query_limit} to prevent abuse.
  Negative offsets are normalized to 0.
  """
  @spec list_accounts(keyword()) :: [Account.t()]
  def list_accounts(opts \\ []) do
    search = Keyword.get(opts, :search)
    limit = opts |> Keyword.get(:limit, 50) |> min(@max_query_limit)
    offset = opts |> Keyword.get(:offset, 0) |> max(0)
    include_deleted = Keyword.get(opts, :include_deleted, false)

    query =
      from(a in Account,
        order_by: [desc: a.inserted_at],
        limit: ^limit,
        offset: ^offset
      )

    query =
      if include_deleted do
        query
      else
        from(a in query, where: is_nil(a.deleted_at))
      end

    query =
      if search && search != "" do
        search_term = "%#{search}%"
        from(a in query, where: ilike(a.email, ^search_term))
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  List accounts with character counts for admin view.

  Includes a virtual `character_count` field.

  ## Options

  Same as `list_accounts/1`.

  ## Returns

  List of account maps with character counts.
  """
  @spec list_accounts_with_character_counts(keyword()) :: [map()]
  def list_accounts_with_character_counts(opts \\ []) do
    search = Keyword.get(opts, :search)
    limit = opts |> Keyword.get(:limit, 50) |> min(@max_query_limit)
    offset = opts |> Keyword.get(:offset, 0) |> max(0)
    include_deleted = Keyword.get(opts, :include_deleted, false)

    # Subquery to count characters per account
    character_counts =
      from(c in Character,
        where: is_nil(c.deleted_at),
        group_by: c.account_id,
        select: %{account_id: c.account_id, count: count(c.id)}
      )

    query =
      from(a in Account,
        left_join: cc in subquery(character_counts),
        on: cc.account_id == a.id,
        order_by: [desc: a.inserted_at],
        limit: ^limit,
        offset: ^offset,
        select: %{
          id: a.id,
          email: a.email,
          email_verified_at: a.email_verified_at,
          totp_enabled_at: a.totp_enabled_at,
          discord_id: a.discord_id,
          discord_username: a.discord_username,
          deleted_at: a.deleted_at,
          inserted_at: a.inserted_at,
          character_count: coalesce(cc.count, 0)
        }
      )

    query =
      if include_deleted do
        query
      else
        from([a, cc] in query, where: is_nil(a.deleted_at))
      end

    query =
      if search && search != "" do
        search_term = "%#{search}%"
        from([a, cc] in query, where: ilike(a.email, ^search_term))
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Search accounts by character name.

  Finds accounts that have a character matching the given name.

  ## Parameters

  - `character_name` - Partial character name to search for
  - `opts` - Options for pagination

  ## Returns

  List of account maps with matching character info.
  """
  @spec search_accounts_by_character(String.t(), keyword()) :: [map()]
  def search_accounts_by_character(character_name, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)
    search_term = "%#{character_name}%"

    from(c in Character,
      join: a in Account,
      on: a.id == c.account_id,
      where: ilike(c.name, ^search_term) and is_nil(c.deleted_at) and is_nil(a.deleted_at),
      order_by: [asc: c.name],
      limit: ^limit,
      offset: ^offset,
      select: %{
        account_id: a.id,
        account_email: a.email,
        character_id: c.id,
        character_name: c.name,
        character_level: c.level,
        character_class: c.class
      }
    )
    |> Repo.all()
  end

  @doc """
  Get an account with all details for admin view.

  Preloads suspensions and roles.
  """
  @spec get_account_for_admin(integer()) :: Account.t() | nil
  def get_account_for_admin(id) when is_integer(id) do
    Account
    |> where([a], a.id == ^id)
    |> preload([:suspensions, :roles])
    |> Repo.one()
  end

  @doc """
  Remove a suspension from an account.

  ## Parameters

  - `suspension` - The suspension to remove

  ## Returns

  - `{:ok, suspension}` on success
  - `{:error, changeset}` on failure
  """
  @spec remove_suspension(AccountSuspension.t()) :: {:ok, AccountSuspension.t()} | {:error, Ecto.Changeset.t()}
  def remove_suspension(suspension) do
    Repo.delete(suspension)
  end

  @doc """
  Get active suspension for an account.

  ## Returns

  The active suspension or nil if not suspended.
  """
  @spec get_active_suspension(Account.t()) :: AccountSuspension.t() | nil
  def get_active_suspension(account) do
    from(s in AccountSuspension,
      where: s.account_id == ^account.id,
      where: is_nil(s.end_time) or s.end_time > ^DateTime.utc_now(),
      order_by: [desc: s.start_time],
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Restore a soft-deleted account.
  """
  @spec restore_account(Account.t()) :: {:ok, Account.t()} | {:error, Ecto.Changeset.t()}
  def restore_account(account) do
    account
    |> Ecto.Changeset.change(%{deleted_at: nil})
    |> Repo.update()
  end

  @doc """
  List all suspensions with optional filtering.

  ## Options

  - `:active_only` - Only return currently active suspensions (default: false)
  - `:limit` - Maximum number of results
  - `:offset` - Offset for pagination
  - `:search` - Search by account email

  ## Returns

  List of suspensions with preloaded account.
  """
  @spec list_suspensions(keyword()) :: [AccountSuspension.t()]
  def list_suspensions(opts \\ []) do
    active_only = Keyword.get(opts, :active_only, false)
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)
    search = Keyword.get(opts, :search)

    query =
      from(s in AccountSuspension,
        join: a in assoc(s, :account),
        preload: [account: a],
        order_by: [desc: s.start_time],
        limit: ^limit,
        offset: ^offset
      )

    query =
      if active_only do
        now = DateTime.utc_now()
        from(s in query, where: is_nil(s.end_time) or s.end_time > ^now)
      else
        query
      end

    query =
      if search && search != "" do
        search_term = "%#{search}%"
        from([s, a] in query, where: ilike(a.email, ^search_term))
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Count all suspensions with optional filtering.
  """
  @spec count_suspensions(keyword()) :: non_neg_integer()
  def count_suspensions(opts \\ []) do
    active_only = Keyword.get(opts, :active_only, false)
    search = Keyword.get(opts, :search)

    query = from(s in AccountSuspension, join: a in assoc(s, :account))

    query =
      if active_only do
        now = DateTime.utc_now()
        from(s in query, where: is_nil(s.end_time) or s.end_time > ^now)
      else
        query
      end

    query =
      if search && search != "" do
        search_term = "%#{search}%"
        from([s, a] in query, where: ilike(a.email, ^search_term))
      else
        query
      end

    Repo.aggregate(query, :count)
  end
end
