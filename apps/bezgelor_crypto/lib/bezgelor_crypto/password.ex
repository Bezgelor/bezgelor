defmodule BezgelorCrypto.Password do
  @moduledoc """
  Password handling utilities for account creation and verification.

  ## Overview

  This module provides high-level functions for password operations:

  - `generate_salt_and_verifier/2` - Create salt/verifier for new accounts

  The returned values are hex-encoded strings suitable for database storage.

  ## Security

  - Passwords are never stored - only the verifier (derived value)
  - Salt is cryptographically random
  - Email is normalized to lowercase before hashing

  ## Example

      # When creating a new account
      {salt, verifier} = BezgelorCrypto.Password.generate_salt_and_verifier(
        "player@example.com",
        "their_password"
      )

      # Store salt (S) and verifier (V) in database
      # The password is NOT stored anywhere
  """

  alias BezgelorCrypto.{Random, SRP6}

  @doc """
  Verify a password against stored SRP6 credentials.

  Recomputes the verifier from the provided password and compares it
  to the stored verifier. This is used for web authentication where
  we don't need the full SRP6 handshake.

  ## Parameters

  - `email` - User's email address
  - `password` - Password to verify
  - `stored_salt` - Hex-encoded salt from database
  - `stored_verifier` - Hex-encoded verifier from database

  ## Returns

  `true` if password matches, `false` otherwise.

  ## Example

      if Password.verify_password("user@example.com", "pass", account.salt, account.verifier) do
        # Password is correct
      end
  """
  @spec verify_password(String.t(), String.t(), String.t(), String.t()) :: boolean()
  def verify_password(email, password, stored_salt, stored_verifier)
      when is_binary(email) and is_binary(password) and
           is_binary(stored_salt) and is_binary(stored_verifier) do
    # Decode the stored hex salt
    salt = Base.decode16!(stored_salt, case: :mixed)

    # Generate verifier using the provided password
    computed_verifier = SRP6.generate_verifier(salt, String.downcase(email), password)
    computed_verifier_hex = Base.encode16(computed_verifier)

    # Constant-time comparison to prevent timing attacks
    Plug.Crypto.secure_compare(computed_verifier_hex, stored_verifier)
  end

  @doc """
  Generate a random salt and SRP6 password verifier for the given credentials.

  ## Parameters

  - `email` - User's email address (will be lowercased)
  - `password` - User's plaintext password

  ## Returns

  `{salt, verifier}` tuple where both are uppercase hex strings.

  ## Example

      iex> {salt, verifier} = BezgelorCrypto.Password.generate_salt_and_verifier("a@b.com", "pass")
      iex> String.length(salt)
      32
  """
  @spec generate_salt_and_verifier(String.t(), String.t()) :: {String.t(), String.t()}
  def generate_salt_and_verifier(email, password) do
    salt = Random.bytes(16)
    verifier = SRP6.generate_verifier(salt, String.downcase(email), password)

    {
      Base.encode16(salt),
      Base.encode16(verifier)
    }
  end
end
