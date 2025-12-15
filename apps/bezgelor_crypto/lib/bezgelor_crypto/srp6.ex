defmodule BezgelorCrypto.SRP6 do
  @moduledoc """
  SRP6 (Secure Remote Password) authentication protocol implementation.

  ## Overview

  SRP6 is a zero-knowledge password proof protocol. The server never stores
  or receives the actual password - only a verifier derived from it.

  This implementation matches WildStar's SRP6 variant:
  - 1024-bit safe prime (N)
  - Generator g = 2
  - SHA256 for hashing
  - Custom byte ordering for compatibility

  ## Authentication Flow

  1. **Registration:** Client sends email, server generates salt, client sends
     verifier (derived from salt + email + password)

  2. **Login:**
     - Server sends salt (s) and server public key (B)
     - Client computes client public key (A) and evidence (M1)
     - Server verifies M1, computes session key and server evidence (M2)
     - Client verifies M2

  ## Example

      # Registration - generate salt and verifier
      salt = BezgelorCrypto.Random.bytes(16)
      verifier = BezgelorCrypto.SRP6.generate_verifier(salt, email, password)
      # Store salt and verifier in database

      # Login - server side
      {:ok, server} = BezgelorCrypto.SRP6.new_server(email, salt, verifier)
      {:ok, server_b, server} = BezgelorCrypto.SRP6.server_credentials(server)
      # Send server_b to client...
  """

  alias BezgelorCrypto.Random

  # WildStar's 1024-bit safe prime N (big-endian byte representation)
  @n_bytes <<
    0xE3, 0x06, 0xEB, 0xC0, 0x2F, 0x1D, 0xC6, 0x9F, 0x5B, 0x43, 0x76, 0x83, 0xFE, 0x38, 0x51, 0xFD,
    0x9A, 0xAA, 0x6E, 0x97, 0xF4, 0xCB, 0xD4, 0x2F, 0xC0, 0x6C, 0x72, 0x05, 0x3C, 0xBC, 0xED, 0x68,
    0xEC, 0x57, 0x0E, 0x66, 0x66, 0xF5, 0x29, 0xC5, 0x85, 0x18, 0xCF, 0x7B, 0x29, 0x9B, 0x55, 0x82,
    0x49, 0x5D, 0xB1, 0x69, 0xAD, 0xF4, 0x8E, 0xCE, 0xB6, 0xD6, 0x54, 0x61, 0xB4, 0xD7, 0xC7, 0x5D,
    0xD1, 0xDA, 0x89, 0x60, 0x1D, 0x5C, 0x49, 0x8E, 0xE4, 0x8B, 0xB9, 0x50, 0xE2, 0xD8, 0xD5, 0xE0,
    0xE0, 0xC6, 0x92, 0xD6, 0x13, 0x48, 0x3B, 0x38, 0xD3, 0x81, 0xEA, 0x96, 0x74, 0xDF, 0x74, 0xD6,
    0x76, 0x65, 0x25, 0x9C, 0x4C, 0x31, 0xA2, 0x9E, 0x0B, 0x3C, 0xFF, 0x75, 0x87, 0x61, 0x72, 0x60,
    0xE8, 0xC5, 0x8F, 0xFA, 0x0A, 0xF8, 0x33, 0x9C, 0xD6, 0x8D, 0xB3, 0xAD, 0xB9, 0x0A, 0xAF, 0xEE
  >>

  @g 2

  # Computed at compile time
  @n :binary.decode_unsigned(@n_bytes, :little)

  @typedoc "SRP6 server state during authentication"
  @type server :: %{
          identity: binary(),
          salt: binary(),
          verifier: non_neg_integer(),
          private_b: non_neg_integer(),
          public_b: non_neg_integer() | nil,
          public_a: non_neg_integer() | nil,
          u: non_neg_integer() | nil,
          s: non_neg_integer() | nil,
          session_key: binary() | nil,
          m1: non_neg_integer() | nil
        }

  @doc "Returns the generator g (always 2)"
  @spec g() :: non_neg_integer()
  def g, do: @g

  @doc "Returns the 1024-bit safe prime N"
  @spec n() :: non_neg_integer()
  def n, do: @n

  @doc """
  Generate a password verifier from salt and credentials.

  This is stored in the database instead of the password.

  ## Parameters

  - `salt` - Random 16-byte salt
  - `identity` - User's email (lowercase)
  - `password` - User's plaintext password

  ## Returns

  Binary verifier value.
  """
  @spec generate_verifier(binary(), String.t(), String.t()) :: binary()
  def generate_verifier(salt, identity, password) when is_binary(salt) do
    # P = SHA256(identity:password)
    credentials = "#{String.downcase(identity)}:#{password}"
    p = :crypto.hash(:sha256, credentials)

    # x = H(s, P) with padding
    x = hash_integers(true, [
      :binary.decode_unsigned(salt, :little),
      :binary.decode_unsigned(p, :little)
    ])

    # v = g^x mod N
    v = mod_pow(@g, x, @n)
    int_to_bytes(v)
  end

  @doc """
  Create a new server-side SRP6 session.

  ## Parameters

  - `identity` - User's email
  - `salt` - Salt from database (binary)
  - `verifier` - Verifier from database (binary)
  """
  @spec new_server(String.t(), binary(), binary()) :: {:ok, server()}
  def new_server(identity, salt, verifier) when is_binary(salt) and is_binary(verifier) do
    b = Random.big_integer(128)

    server = %{
      identity: identity,
      salt: salt,
      verifier: :binary.decode_unsigned(verifier, :little),
      private_b: b,
      public_b: nil,
      public_a: nil,
      u: nil,
      s: nil,
      session_key: nil,
      m1: nil
    }

    {:ok, server}
  end

  @doc """
  Generate server credentials (public key B) to send to client.

  B = (k*v + g^b) mod N
  where k = H(N, g)
  """
  @spec server_credentials(server()) :: {:ok, binary(), server()}
  def server_credentials(%{private_b: b, verifier: v} = server) do
    k = hash_integers(true, [@n, @g])
    public_b = rem(k * v + mod_pow(@g, b, @n), @n)

    server = %{server | public_b: public_b}
    {:ok, int_to_bytes(public_b), server}
  end

  @doc """
  Process client's public key A and calculate shared secret.

  Returns error if A mod N == 0 (invalid).
  """
  @spec calculate_secret(server(), binary()) :: {:ok, server()} | {:error, :invalid_public_key}
  def calculate_secret(server, client_a_bytes) when is_binary(client_a_bytes) do
    a = :binary.decode_unsigned(client_a_bytes, :little)

    if rem(a, @n) == 0 do
      {:error, :invalid_public_key}
    else
      %{private_b: b, public_b: public_b, verifier: v} = server

      # u = H(A, B)
      u = hash_integers(true, [a, public_b])

      # S = (A * v^u)^b mod N
      s = mod_pow(a * mod_pow(v, u, @n), b, @n)

      server = %{server | public_a: a, u: u, s: s}
      {:ok, server}
    end
  end

  @doc """
  Calculate the session key K from the shared secret S.

  Uses SHA_Interleave from RFC2945.
  """
  @spec calculate_session_key(server()) :: {:ok, binary(), server()}
  def calculate_session_key(%{s: s} = server) when s != nil do
    k = sha_interleave(s)
    server = %{server | session_key: k}
    {:ok, k, server}
  end

  @doc """
  Verify client's evidence message M1.

  M1 = H(H(N) XOR H(g), H(I), s, A, B, K)
  """
  @spec verify_client_evidence(server(), binary()) :: {:ok, server()} | {:error, :invalid_evidence}
  def verify_client_evidence(server, client_m1_bytes) when is_binary(client_m1_bytes) do
    %{
      identity: identity,
      salt: salt,
      public_a: a,
      public_b: public_b,
      session_key: k
    } = server

    # H(N) XOR H(g)
    h_n = hash_integers(false, [@n])
    h_g = hash_integers(false, [@g])
    h_n_bytes = int_to_bytes_padded(h_n, 32)
    h_g_bytes = int_to_bytes_padded(h_g, 32)
    xor_ng = :crypto.exor(h_n_bytes, h_g_bytes)

    # H(I)
    h_identity = :crypto.hash(:sha256, identity)

    # Expected M1
    expected_m1 = hash_integers(false, [
      :binary.decode_unsigned(xor_ng, :little),
      :binary.decode_unsigned(h_identity, :little),
      :binary.decode_unsigned(salt, :little),
      a,
      public_b,
      :binary.decode_unsigned(k, :little)
    ])

    client_m1 = :binary.decode_unsigned(client_m1_bytes, :little)

    if client_m1 == expected_m1 do
      # Store original M1 bytes for M2 calculation (not integer)
      {:ok, %{server | m1: client_m1_bytes}}
    else
      {:error, :invalid_evidence}
    end
  end

  @doc """
  Calculate server evidence message M2 to send to client.

  M2 = H(A, M1, K) with NexusForever's specific byte handling:
  1. Hash(true, A, M1, K) - reverses hash output
  2. Convert to bytes via BigInteger
  3. ReverseBytesAsUInt32 on final output

  The two reversals effectively cancel out for 32-byte hashes,
  but we match NexusForever exactly for compatibility.
  """
  @spec server_evidence(server()) :: {:ok, binary()}
  def server_evidence(%{public_a: a, m1: m1, session_key: k}) do
    # m1 is stored as bytes, convert to integer for hash_integers
    m1_int = :binary.decode_unsigned(m1, :little)
    k_int = :binary.decode_unsigned(k, :little)

    # Match NexusForever exactly:
    # M2 = Hash(true, A, M1, K)  - hash with reversal on output
    m2_int = hash_integers(true, [a, m1_int, k_int])
    m2_bytes = int_to_bytes_padded(m2_int, 32)

    # Then: ReverseBytesAsUInt32(M2Bytes) on the output
    m2_final = reverse_bytes_as_uint32(m2_bytes)

    {:ok, m2_final}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  # Modular exponentiation: base^exp mod mod
  defp mod_pow(base, exp, mod) do
    :crypto.mod_pow(base, exp, mod)
    |> :binary.decode_unsigned()
  end

  # Hash multiple big integers with optional uint32 reversal
  defp hash_integers(reverse?, integers) do
    data =
      integers
      |> Enum.map(fn int ->
        bytes = int_to_bytes(int)
        # Pad to 4-byte boundary
        padding = rem(4 - rem(byte_size(bytes), 4), 4)
        bytes <> :binary.copy(<<0>>, padding)
      end)
      |> IO.iodata_to_binary()

    hash = :crypto.hash(:sha256, data)

    hash =
      if reverse? do
        reverse_bytes_as_uint32(hash)
      else
        hash
      end

    :binary.decode_unsigned(hash, :little)
  end

  # SHA_Interleave from RFC2945 (variable length version)
  defp sha_interleave(s) do
    s_bytes = int_to_bytes(s)

    # Reverse to big-endian for processing
    t = :binary.bin_to_list(s_bytes) |> Enum.reverse()

    # Find first non-zero and calculate length
    first_zero = Enum.find_index(s_bytes |> :binary.bin_to_list(), &(&1 == 0)) || byte_size(s_bytes)
    len = if first_zero < length(t) - 4, do: length(t) - first_zero, else: 4

    # Split into even/odd bytes
    e = for i <- 0..(div(len, 2) - 1), do: Enum.at(t, i * 2)
    f = for i <- 0..(div(len, 2) - 1), do: Enum.at(t, i * 2 + 1)

    g = :crypto.hash(:sha256, :binary.list_to_bin(e))
    h = :crypto.hash(:sha256, :binary.list_to_bin(f))

    # Interleave G and H
    k =
      for i <- 0..(byte_size(g) + byte_size(h) - 1) do
        if rem(i, 2) == 0 do
          :binary.at(g, div(i, 2))
        else
          :binary.at(h, div(i, 2))
        end
      end

    :binary.list_to_bin(k)
  end

  # Convert integer to little-endian binary
  defp int_to_bytes(0), do: <<0>>

  defp int_to_bytes(int) when is_integer(int) and int > 0 do
    :binary.encode_unsigned(int, :little)
  end

  # Convert integer to little-endian binary with specific size
  defp int_to_bytes_padded(int, size) do
    bytes = int_to_bytes(int)
    padding = size - byte_size(bytes)

    if padding > 0 do
      bytes <> :binary.copy(<<0>>, padding)
    else
      binary_part(bytes, 0, size)
    end
  end

  # Reverse 4-byte chunk ORDER (matches WildStar client's SRP6 implementation)
  # [A,B,C,D, E,F,G,H] -> [E,F,G,H, A,B,C,D]
  defp reverse_bytes_as_uint32(bytes) do
    bytes
    |> :binary.bin_to_list()
    |> Enum.chunk_every(4)
    |> Enum.reverse()
    |> List.flatten()
    |> :binary.list_to_bin()
  end
end
