defmodule BezgelorCrypto.Random do
  import Bitwise

  @moduledoc """
  Cryptographically secure random number generation.

  ## Overview

  This module wraps Erlang's `:crypto.strong_rand_bytes/1` to provide
  secure random data for cryptographic operations like:

  - Generating SRP6 salt values
  - Creating session tokens
  - Generating random private keys

  All functions use the operating system's cryptographically secure
  random number generator (CSPRNG).

  ## Example

      # Generate 16 random bytes for a salt
      salt = BezgelorCrypto.Random.bytes(16)

      # Generate a random UUID
      session_id = BezgelorCrypto.Random.uuid()
  """

  @doc """
  Generate `count` cryptographically secure random bytes.

  ## Example

      iex> bytes = BezgelorCrypto.Random.bytes(32)
      iex> byte_size(bytes)
      32
  """
  @spec bytes(non_neg_integer()) :: binary()
  def bytes(count) when is_integer(count) and count >= 0 do
    :crypto.strong_rand_bytes(count)
  end

  @doc """
  Generate a random UUID (version 4).

  Returns a lowercase string in standard UUID format:
  `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`
  """
  @spec uuid() :: String.t()
  def uuid do
    <<a::32, b::16, c::16, d::16, e::48>> = bytes(16)

    # Set version (4) and variant bits per RFC 4122
    c_with_version = (c &&& 0x0FFF) ||| 0x4000
    d_with_variant = (d &&& 0x3FFF) ||| 0x8000

    :io_lib.format(
      "~8.16.0b-~4.16.0b-~4.16.0b-~4.16.0b-~12.16.0b",
      [a, b, c_with_version, d_with_variant, e]
    )
    |> IO.iodata_to_binary()
    |> String.downcase()
  end

  @doc """
  Generate a random positive integer from `byte_count` random bytes.

  The result is always positive (unsigned).

  ## Example

      # Generate a 128-bit random integer
      iex> int = BezgelorCrypto.Random.big_integer(16)
      iex> is_integer(int) and int > 0
      true
  """
  @spec big_integer(non_neg_integer()) :: non_neg_integer()
  def big_integer(byte_count) when is_integer(byte_count) and byte_count > 0 do
    bytes(byte_count)
    |> :binary.decode_unsigned(:little)
  end
end
