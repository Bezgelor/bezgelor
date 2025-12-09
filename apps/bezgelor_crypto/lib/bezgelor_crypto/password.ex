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
