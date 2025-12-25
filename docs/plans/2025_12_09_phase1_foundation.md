# Phase 1: Foundation Implementation Plan

**Status:** ✅ Complete

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create the Bezgelor umbrella project structure with core utilities, cryptography, and database schemas.

**Architecture:** Elixir umbrella application with separate apps for core utilities, cryptography, and database access. Each app has its own supervision tree and can be tested independently.

**Tech Stack:** Elixir 1.16+, Phoenix 1.7 (minimal), Ecto 3.11, PostgreSQL

---

## Task 1: Create Umbrella Project Structure

**Files:**
- Create: `mix.exs` (umbrella root)
- Create: `apps/` directory structure
- Create: `.formatter.exs`
- Create: `.gitignore`

**Step 1: Create the umbrella project**

Run:
```bash
cd .
rm -rf .git docs  # Clean slate, we'll recreate
mix new bezgelor --umbrella
```

Expected: Creates umbrella project structure with `apps/` directory.

**Step 2: Verify structure exists**

Run:
```bash
ls -la .
ls -la ./apps
```

Expected: See `mix.exs`, `apps/`, `config/` directories.

**Step 3: Recreate docs directory and restore design document**

Run:
```bash
mkdir -p ./docs/plans
```

Then restore the design document from git reflog or rewrite it.

**Step 4: Initialize git and commit**

Run:
```bash
cd .
git init
git add .
git commit -m "chore: Initialize Bezgelor umbrella project"
```

Expected: Initial commit created.

---

## Task 2: Create bezgelor_core App

**Files:**
- Create: `apps/bezgelor_core/mix.exs`
- Create: `apps/bezgelor_core/lib/bezgelor_core.ex`
- Create: `apps/bezgelor_core/lib/bezgelor_core/application.ex`

**Step 1: Generate the core app**

Run:
```bash
cd ./apps
mix new bezgelor_core --sup
```

Expected: Creates `bezgelor_core` app with supervision tree.

**Step 2: Verify app structure**

Run:
```bash
ls -la ./apps/bezgelor_core/lib/bezgelor_core/
```

Expected: See `application.ex`.

**Step 3: Commit**

Run:
```bash
cd .
git add apps/bezgelor_core
git commit -m "chore: Add bezgelor_core app skeleton"
```

---

## Task 3: Add Core Types Module

**Files:**
- Create: `apps/bezgelor_core/lib/bezgelor_core/types.ex`
- Test: `apps/bezgelor_core/test/bezgelor_core/types_test.exs`

**Step 1: Write the test for Vector3 type**

Create file `apps/bezgelor_core/test/bezgelor_core/types_test.exs`:

```elixir
defmodule BezgelorCore.TypesTest do
  use ExUnit.Case, async: true

  alias BezgelorCore.Types.Vector3

  describe "Vector3" do
    test "creates a vector with x, y, z coordinates" do
      vec = %Vector3{x: 1.0, y: 2.0, z: 3.0}
      assert vec.x == 1.0
      assert vec.y == 2.0
      assert vec.z == 3.0
    end

    test "defaults to origin (0, 0, 0)" do
      vec = %Vector3{}
      assert vec.x == 0.0
      assert vec.y == 0.0
      assert vec.z == 0.0
    end

    test "calculates distance between two vectors" do
      v1 = %Vector3{x: 0.0, y: 0.0, z: 0.0}
      v2 = %Vector3{x: 3.0, y: 4.0, z: 0.0}
      assert Vector3.distance(v1, v2) == 5.0
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run:
```bash
cd .
mix test apps/bezgelor_core/test/bezgelor_core/types_test.exs
```

Expected: FAIL - `BezgelorCore.Types.Vector3` module not found.

**Step 3: Write the Vector3 implementation**

Create file `apps/bezgelor_core/lib/bezgelor_core/types.ex`:

```elixir
defmodule BezgelorCore.Types do
  @moduledoc """
  Common types used throughout Bezgelor.

  ## Overview

  This module defines core data structures that represent game concepts:
  - `Vector3` - 3D coordinates for positions and rotations
  - More types will be added as needed
  """
end

defmodule BezgelorCore.Types.Vector3 do
  @moduledoc """
  A 3D vector representing a position or direction in the game world.

  ## Fields

  - `x` - X coordinate (east/west)
  - `y` - Y coordinate (up/down, height)
  - `z` - Z coordinate (north/south)

  ## Example

      iex> vec = %BezgelorCore.Types.Vector3{x: 100.0, y: 50.0, z: 200.0}
      iex> vec.x
      100.0
  """

  @type t :: %__MODULE__{
          x: float(),
          y: float(),
          z: float()
        }

  defstruct x: 0.0, y: 0.0, z: 0.0

  @doc """
  Calculate the Euclidean distance between two vectors.

  ## Example

      iex> v1 = %BezgelorCore.Types.Vector3{x: 0.0, y: 0.0, z: 0.0}
      iex> v2 = %BezgelorCore.Types.Vector3{x: 3.0, y: 4.0, z: 0.0}
      iex> BezgelorCore.Types.Vector3.distance(v1, v2)
      5.0
  """
  @spec distance(t(), t()) :: float()
  def distance(%__MODULE__{} = v1, %__MODULE__{} = v2) do
    dx = v2.x - v1.x
    dy = v2.y - v1.y
    dz = v2.z - v1.z
    :math.sqrt(dx * dx + dy * dy + dz * dz)
  end
end
```

**Step 4: Run test to verify it passes**

Run:
```bash
cd .
mix test apps/bezgelor_core/test/bezgelor_core/types_test.exs
```

Expected: PASS - 3 tests, 0 failures.

**Step 5: Commit**

Run:
```bash
cd .
git add apps/bezgelor_core/lib/bezgelor_core/types.ex
git add apps/bezgelor_core/test/bezgelor_core/types_test.exs
git commit -m "feat(core): Add Vector3 type with distance calculation"
```

---

## Task 4: Add Core Config Module

**Files:**
- Create: `apps/bezgelor_core/lib/bezgelor_core/config.ex`
- Modify: `config/config.exs`
- Test: `apps/bezgelor_core/test/bezgelor_core/config_test.exs`

**Step 1: Write the test for config access**

Create file `apps/bezgelor_core/test/bezgelor_core/config_test.exs`:

```elixir
defmodule BezgelorCore.ConfigTest do
  use ExUnit.Case, async: true

  alias BezgelorCore.Config

  describe "get/2" do
    test "retrieves application config value" do
      # Application.put_env is used in test setup
      Application.put_env(:bezgelor_core, :test_key, "test_value")
      assert Config.get(:bezgelor_core, :test_key) == "test_value"
    end

    test "returns default when key missing" do
      assert Config.get(:bezgelor_core, :missing_key, "default") == "default"
    end
  end

  describe "get!/2" do
    test "raises when key is missing" do
      assert_raise KeyError, fn ->
        Config.get!(:bezgelor_core, :definitely_missing)
      end
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run:
```bash
cd .
mix test apps/bezgelor_core/test/bezgelor_core/config_test.exs
```

Expected: FAIL - `BezgelorCore.Config` module not found.

**Step 3: Write the Config implementation**

Create file `apps/bezgelor_core/lib/bezgelor_core/config.ex`:

```elixir
defmodule BezgelorCore.Config do
  @moduledoc """
  Configuration access utilities for Bezgelor applications.

  ## Overview

  This module provides a consistent interface for accessing application
  configuration. It wraps `Application.get_env/3` with additional features:

  - `get/3` - Get config with optional default
  - `get!/2` - Get config or raise if missing

  ## Example

      # In config/config.exs:
      config :bezgelor_core,
        server_name: "Bezgelor",
        max_players: 1000

      # In code:
      BezgelorCore.Config.get(:bezgelor_core, :server_name)
      # => "Bezgelor"
  """

  @doc """
  Get a configuration value for the given application and key.

  Returns `default` if the key is not found (defaults to `nil`).
  """
  @spec get(atom(), atom(), term()) :: term()
  def get(app, key, default \\ nil) do
    Application.get_env(app, key, default)
  end

  @doc """
  Get a configuration value, raising if not found.

  Raises `KeyError` if the configuration key does not exist.
  """
  @spec get!(atom(), atom()) :: term()
  def get!(app, key) do
    case Application.fetch_env(app, key) do
      {:ok, value} -> value
      :error -> raise KeyError, key: key, term: app
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run:
```bash
cd .
mix test apps/bezgelor_core/test/bezgelor_core/config_test.exs
```

Expected: PASS - 3 tests, 0 failures.

**Step 5: Commit**

Run:
```bash
cd .
git add apps/bezgelor_core/lib/bezgelor_core/config.ex
git add apps/bezgelor_core/test/bezgelor_core/config_test.exs
git commit -m "feat(core): Add Config module for application configuration"
```

---

## Task 5: Create bezgelor_crypto App

**Files:**
- Create: `apps/bezgelor_crypto/mix.exs`
- Create: `apps/bezgelor_crypto/lib/bezgelor_crypto.ex`

**Step 1: Generate the crypto app**

Run:
```bash
cd ./apps
mix new bezgelor_crypto
```

Expected: Creates `bezgelor_crypto` app.

**Step 2: Commit**

Run:
```bash
cd .
git add apps/bezgelor_crypto
git commit -m "chore: Add bezgelor_crypto app skeleton"
```

---

## Task 6: Implement RandomProvider

**Files:**
- Create: `apps/bezgelor_crypto/lib/bezgelor_crypto/random.ex`
- Test: `apps/bezgelor_crypto/test/bezgelor_crypto/random_test.exs`

**Step 1: Write the test**

Create file `apps/bezgelor_crypto/test/bezgelor_crypto/random_test.exs`:

```elixir
defmodule BezgelorCrypto.RandomTest do
  use ExUnit.Case, async: true

  alias BezgelorCrypto.Random

  describe "bytes/1" do
    test "generates bytes of requested length" do
      bytes = Random.bytes(16)
      assert byte_size(bytes) == 16
    end

    test "generates different bytes each call" do
      bytes1 = Random.bytes(16)
      bytes2 = Random.bytes(16)
      assert bytes1 != bytes2
    end
  end

  describe "uuid/0" do
    test "generates valid UUID format" do
      uuid = Random.uuid()
      # UUID format: 8-4-4-4-12 hex chars
      assert String.match?(uuid, ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/)
    end
  end

  describe "big_integer/1" do
    test "generates positive integer of specified byte size" do
      int = Random.big_integer(16)
      assert is_integer(int)
      assert int > 0
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run:
```bash
cd .
mix test apps/bezgelor_crypto/test/bezgelor_crypto/random_test.exs
```

Expected: FAIL - `BezgelorCrypto.Random` module not found.

**Step 3: Write the Random implementation**

Create file `apps/bezgelor_crypto/lib/bezgelor_crypto/random.ex`:

```elixir
defmodule BezgelorCrypto.Random do
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
```

**Step 4: Run test to verify it passes**

Run:
```bash
cd .
mix test apps/bezgelor_crypto/test/bezgelor_crypto/random_test.exs
```

Expected: PASS - 4 tests, 0 failures.

**Step 5: Commit**

Run:
```bash
cd .
git add apps/bezgelor_crypto/lib/bezgelor_crypto/random.ex
git add apps/bezgelor_crypto/test/bezgelor_crypto/random_test.exs
git commit -m "feat(crypto): Add Random module for secure random generation"
```

---

## Task 7: Implement SRP6 Provider

**Files:**
- Create: `apps/bezgelor_crypto/lib/bezgelor_crypto/srp6.ex`
- Test: `apps/bezgelor_crypto/test/bezgelor_crypto/srp6_test.exs`

**Step 1: Write the test for verifier generation**

Create file `apps/bezgelor_crypto/test/bezgelor_crypto/srp6_test.exs`:

```elixir
defmodule BezgelorCrypto.SRP6Test do
  use ExUnit.Case, async: true

  alias BezgelorCrypto.SRP6

  describe "constants" do
    test "generator g is 2" do
      assert SRP6.g() == 2
    end

    test "prime N is 1024-bit" do
      n = SRP6.n()
      # 1024 bits = 128 bytes, BigInteger may have leading zeros
      assert is_integer(n)
      assert n > 0
    end
  end

  describe "generate_verifier/3" do
    test "generates deterministic verifier from salt and credentials" do
      salt = Base.decode16!("0102030405060708090A0B0C0D0E0F10")
      email = "test@example.com"
      password = "password123"

      v1 = SRP6.generate_verifier(salt, email, password)
      v2 = SRP6.generate_verifier(salt, email, password)

      assert v1 == v2
      assert is_binary(v1)
      assert byte_size(v1) > 0
    end

    test "different salts produce different verifiers" do
      salt1 = Base.decode16!("0102030405060708090A0B0C0D0E0F10")
      salt2 = Base.decode16!("1112131415161718191A1B1C1D1E1F20")
      email = "test@example.com"
      password = "password123"

      v1 = SRP6.generate_verifier(salt1, email, password)
      v2 = SRP6.generate_verifier(salt2, email, password)

      assert v1 != v2
    end
  end

  describe "server authentication flow" do
    setup do
      salt = BezgelorCrypto.Random.bytes(16)
      email = "player@example.com"
      password = "secret123"
      verifier = SRP6.generate_verifier(salt, email, password)

      %{salt: salt, email: email, password: password, verifier: verifier}
    end

    test "generates server credentials", %{email: email, salt: salt, verifier: verifier} do
      {:ok, server} = SRP6.new_server(email, salt, verifier)
      {:ok, server_b} = SRP6.server_credentials(server)

      assert is_binary(server_b)
      assert byte_size(server_b) > 0
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run:
```bash
cd .
mix test apps/bezgelor_crypto/test/bezgelor_crypto/srp6_test.exs
```

Expected: FAIL - `BezgelorCrypto.SRP6` module not found.

**Step 3: Write the SRP6 implementation**

Create file `apps/bezgelor_crypto/lib/bezgelor_crypto/srp6.ex`:

```elixir
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
      {:ok, server_b} = BezgelorCrypto.SRP6.server_credentials(server)
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
      {:ok, %{server | m1: client_m1}}
    else
      {:error, :invalid_evidence}
    end
  end

  @doc """
  Calculate server evidence message M2 to send to client.

  M2 = H(A, M1, K)
  """
  @spec server_evidence(server()) :: {:ok, binary()}
  def server_evidence(%{public_a: a, m1: m1, session_key: k}) do
    m2 = hash_integers(true, [a, m1, :binary.decode_unsigned(k, :little)])
    m2_bytes = int_to_bytes(m2)

    # Reverse bytes as uint32 (WildStar-specific)
    reversed = reverse_bytes_as_uint32(m2_bytes)
    {:ok, reversed}
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
    length = if first_zero < length(t) - 4, do: length(t) - first_zero, else: 4

    # Split into even/odd bytes
    e = for i <- 0..(div(length, 2) - 1), do: Enum.at(t, i * 2)
    f = for i <- 0..(div(length, 2) - 1), do: Enum.at(t, i * 2 + 1)

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

  # Reverse bytes in 4-byte chunks (WildStar-specific)
  defp reverse_bytes_as_uint32(bytes) do
    bytes
    |> :binary.bin_to_list()
    |> Enum.chunk_every(4)
    |> Enum.reverse()
    |> List.flatten()
    |> :binary.list_to_bin()
  end
end
```

**Step 4: Run test to verify it passes**

Run:
```bash
cd .
mix test apps/bezgelor_crypto/test/bezgelor_crypto/srp6_test.exs
```

Expected: PASS - 5 tests, 0 failures.

**Step 5: Commit**

Run:
```bash
cd .
git add apps/bezgelor_crypto/lib/bezgelor_crypto/srp6.ex
git add apps/bezgelor_crypto/test/bezgelor_crypto/srp6_test.exs
git commit -m "feat(crypto): Add SRP6 authentication protocol implementation"
```

---

## Task 8: Implement PacketCrypt

**Files:**
- Create: `apps/bezgelor_crypto/lib/bezgelor_crypto/packet_crypt.ex`
- Test: `apps/bezgelor_crypto/test/bezgelor_crypto/packet_crypt_test.exs`

**Step 1: Write the test**

Create file `apps/bezgelor_crypto/test/bezgelor_crypto/packet_crypt_test.exs`:

```elixir
defmodule BezgelorCrypto.PacketCryptTest do
  use ExUnit.Case, async: true

  alias BezgelorCrypto.PacketCrypt

  describe "new/1" do
    test "creates a packet crypt with key" do
      crypt = PacketCrypt.new(12345)
      assert is_struct(crypt, PacketCrypt)
    end
  end

  describe "encrypt/decrypt round-trip" do
    test "decrypting encrypted data returns original" do
      crypt = PacketCrypt.new(0xDEADBEEF)
      original = "Hello, WildStar!"

      encrypted = PacketCrypt.encrypt(crypt, original)
      decrypted = PacketCrypt.decrypt(crypt, encrypted)

      assert decrypted == original
    end

    test "encrypted data differs from original" do
      crypt = PacketCrypt.new(0xDEADBEEF)
      original = "Secret message"

      encrypted = PacketCrypt.encrypt(crypt, original)
      assert encrypted != original
    end
  end

  describe "key_from_auth_build/0" do
    test "returns consistent key for build 16042" do
      key = PacketCrypt.key_from_auth_build()
      assert is_integer(key)
      assert key > 0
    end
  end

  describe "key_from_ticket/1" do
    test "generates key from 16-byte session key" do
      session_key = :crypto.strong_rand_bytes(16)
      key = PacketCrypt.key_from_ticket(session_key)

      assert is_integer(key)
      assert key > 0
    end

    test "raises for invalid session key length" do
      assert_raise ArgumentError, fn ->
        PacketCrypt.key_from_ticket(<<1, 2, 3>>)
      end
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run:
```bash
cd .
mix test apps/bezgelor_crypto/test/bezgelor_crypto/packet_crypt_test.exs
```

Expected: FAIL - `BezgelorCrypto.PacketCrypt` module not found.

**Step 3: Write the PacketCrypt implementation**

Create file `apps/bezgelor_crypto/lib/bezgelor_crypto/packet_crypt.ex`:

```elixir
defmodule BezgelorCrypto.PacketCrypt do
  @moduledoc """
  WildStar packet encryption/decryption.

  ## Overview

  This module implements WildStar's packet encryption scheme, which uses
  a 1024-bit key derived from either:

  - The client build number (for auth server)
  - A session key ticket (for world server)

  The encryption is a custom XOR-based cipher that maintains state
  between operations.

  ## Example

      # Create cipher for auth server
      key = BezgelorCrypto.PacketCrypt.key_from_auth_build()
      crypt = BezgelorCrypto.PacketCrypt.new(key)

      # Encrypt outgoing packet
      encrypted = BezgelorCrypto.PacketCrypt.encrypt(crypt, packet_data)

      # Decrypt incoming packet
      decrypted = BezgelorCrypto.PacketCrypt.decrypt(crypt, incoming_data)
  """

  @crypt_key_size 128  # 1024 bits
  @crypt_multiplier 0xAA7F8EA9
  @crypt_multiplier_2 0xAA7F8EAA
  @crypt_initial_value 0x718DA9074F2DEB91

  defstruct [:key, :key_value]

  @type t :: %__MODULE__{
          key: binary(),
          key_value: non_neg_integer()
        }

  @doc """
  Create a new packet cipher from a key integer.

  The key integer is used to derive a 1024-bit encryption key.
  """
  @spec new(non_neg_integer()) :: t()
  def new(key_integer) when is_integer(key_integer) do
    {key, key_value} = derive_key(key_integer)
    %__MODULE__{key: key, key_value: key_value}
  end

  @doc """
  Decrypt a packet buffer.

  Note: This creates a new state buffer for each operation. The cipher
  state is not modified between calls.
  """
  @spec decrypt(t(), binary()) :: binary()
  def decrypt(%__MODULE__{key: key, key_value: key_value}, buffer) when is_binary(buffer) do
    length = byte_size(buffer)
    # State initialized from key_value, reversed byte order for decrypt
    state = <<key_value::little-64>> |> reverse_bytes()

    v4 = band(@crypt_multiplier_2 * length, 0xFFFFFFFF)

    {output, _state, _v4, _v9} =
      buffer
      |> :binary.bin_to_list()
      |> Enum.with_index()
      |> Enum.reduce({[], state, v4, 0}, fn {byte, i}, {acc, state, v4, v9} ->
        state_index = rem(i, 8)

        {v4, v9} =
          if state_index == 0 do
            {v4 + 1, band(v4, 0xF) * 8}
          else
            {v4, v9}
          end

        state_byte = :binary.at(state, 7 - state_index)
        key_byte = :binary.at(key, v9 + state_index)

        output_byte = bxor(bxor(state_byte, byte), key_byte) |> band(0xFF)

        # Update state with input byte (decrypt)
        new_state = replace_byte(state, 7 - state_index, byte)

        {[output_byte | acc], new_state, v4, v9}
      end)

    output |> Enum.reverse() |> :binary.list_to_bin()
  end

  @doc """
  Encrypt a packet buffer.
  """
  @spec encrypt(t(), binary()) :: binary()
  def encrypt(%__MODULE__{key: key, key_value: key_value}, buffer) when is_binary(buffer) do
    length = byte_size(buffer)
    # State initialized from key_value, normal byte order for encrypt
    state = <<key_value::little-64>>

    v4 = band(@crypt_multiplier_2 * length, 0xFFFFFFFF)

    {output, _state, _v4, _v9} =
      buffer
      |> :binary.bin_to_list()
      |> Enum.with_index()
      |> Enum.reduce({[], state, v4, 0}, fn {byte, i}, {acc, state, v4, v9} ->
        state_index = rem(i, 8)

        {v4, v9} =
          if state_index == 0 do
            {v4 + 1, band(v4, 0xF) * 8}
          else
            {v4, v9}
          end

        state_byte = :binary.at(state, state_index)
        key_byte = :binary.at(key, v9 + state_index)

        output_byte = bxor(bxor(state_byte, byte), key_byte) |> band(0xFF)

        # Update state with output byte (encrypt)
        new_state = replace_byte(state, state_index, output_byte)

        {[output_byte | acc], new_state, v4, v9}
      end)

    output |> Enum.reverse() |> :binary.list_to_bin()
  end

  @doc """
  Generate encryption key from client build and auth message.

  This is used for the auth server connection before session is established.
  Hardcoded for build 16042.
  """
  @spec key_from_auth_build() :: non_neg_integer()
  def key_from_auth_build do
    key = @crypt_initial_value + 0x5B88D61139619662
    key = band(key * @crypt_multiplier, 0xFFFFFFFFFFFFFFFF)
    key = band((key + 16042) * @crypt_multiplier, 0xFFFFFFFFFFFFFFFF)
    band((key + 0x97998A0) * @crypt_multiplier, 0xFFFFFFFFFFFFFFFF)
  end

  @doc """
  Generate encryption key from a session key ticket.

  This is used for world server connections after authentication.
  The session key must be exactly 16 bytes.
  """
  @spec key_from_ticket(binary()) :: non_neg_integer()
  def key_from_ticket(session_key) when is_binary(session_key) do
    if byte_size(session_key) != 16 do
      raise ArgumentError, "session key must be exactly 16 bytes"
    end

    key =
      session_key
      |> :binary.bin_to_list()
      |> Enum.reduce(@crypt_initial_value, fn byte, key ->
        band((key + byte) * @crypt_multiplier, 0xFFFFFFFFFFFFFFFF)
      end)

    band((key + key_from_auth_build()) * @crypt_multiplier, 0xFFFFFFFFFFFFFFFF)
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  # Derive the 1024-bit key and final key value from the integer
  defp derive_key(key_integer) do
    key_val = @crypt_initial_value
    v2 = band((key_val + key_integer) * @crypt_multiplier, 0xFFFFFFFFFFFFFFFF)

    {key_bytes, final_key_val} =
      Enum.reduce(0..15, {[], key_val}, fn _i, {acc, kv} ->
        new_kv = band((kv + v2) * @crypt_multiplier, 0xFFFFFFFFFFFFFFFF)
        v2_next = band((key_integer + v2) * @crypt_multiplier, 0xFFFFFFFFFFFFFFFF)

        # Take the current v2 value as 8 bytes
        chunk = <<v2::little-64>>
        {[chunk | acc], new_kv}
      end)

    # Rebuild key in correct order
    key =
      key_bytes
      |> Enum.reverse()
      |> Enum.reduce(<<>>, fn chunk, acc -> acc <> chunk end)

    # Recalculate v2 sequence to match C# loop exactly
    {key, final_key_val} = derive_key_exact(key_integer)

    {key, final_key_val}
  end

  # Exact port of C# key derivation loop
  defp derive_key_exact(key_integer) do
    key_val = @crypt_initial_value
    v2 = band((key_val + key_integer) * @crypt_multiplier, 0xFFFFFFFFFFFFFFFF)

    {chunks, final_kv, _final_v2} =
      Enum.reduce(0..15, {[], key_val, v2}, fn _i, {acc, kv, v2} ->
        chunk = <<v2::little-64>>
        new_kv = band((kv + v2) * @crypt_multiplier, 0xFFFFFFFFFFFFFFFF)
        new_v2 = band((key_integer + v2) * @crypt_multiplier, 0xFFFFFFFFFFFFFFFF)
        {[chunk | acc], new_kv, new_v2}
      end)

    key = chunks |> Enum.reverse() |> IO.iodata_to_binary()
    {key, final_kv}
  end

  defp reverse_bytes(<<bytes::binary-size(8)>>) do
    bytes |> :binary.bin_to_list() |> Enum.reverse() |> :binary.list_to_bin()
  end

  defp replace_byte(binary, index, new_byte) do
    <<prefix::binary-size(index), _old::8, suffix::binary>> = binary
    <<prefix::binary, new_byte::8, suffix::binary>>
  end

  defp band(a, b), do: Bitwise.band(a, b)
  defp bxor(a, b), do: Bitwise.bxor(a, b)
end
```

**Step 4: Run test to verify it passes**

Run:
```bash
cd .
mix test apps/bezgelor_crypto/test/bezgelor_crypto/packet_crypt_test.exs
```

Expected: PASS - 5 tests, 0 failures.

**Step 5: Commit**

Run:
```bash
cd .
git add apps/bezgelor_crypto/lib/bezgelor_crypto/packet_crypt.ex
git add apps/bezgelor_crypto/test/bezgelor_crypto/packet_crypt_test.exs
git commit -m "feat(crypto): Add PacketCrypt for WildStar packet encryption"
```

---

## Task 9: Implement Password Provider

**Files:**
- Create: `apps/bezgelor_crypto/lib/bezgelor_crypto/password.ex`
- Test: `apps/bezgelor_crypto/test/bezgelor_crypto/password_test.exs`

**Step 1: Write the test**

Create file `apps/bezgelor_crypto/test/bezgelor_crypto/password_test.exs`:

```elixir
defmodule BezgelorCrypto.PasswordTest do
  use ExUnit.Case, async: true

  alias BezgelorCrypto.Password

  describe "generate_salt_and_verifier/2" do
    test "returns salt and verifier as hex strings" do
      {salt, verifier} = Password.generate_salt_and_verifier("test@example.com", "password123")

      assert is_binary(salt)
      assert is_binary(verifier)
      # Hex strings should be even length and contain only hex chars
      assert String.match?(salt, ~r/^[0-9A-F]+$/i)
      assert String.match?(verifier, ~r/^[0-9A-F]+$/i)
    end

    test "salt is 32 hex chars (16 bytes)" do
      {salt, _verifier} = Password.generate_salt_and_verifier("user@test.com", "secret")
      assert String.length(salt) == 32
    end

    test "generates different salt each time" do
      {salt1, _} = Password.generate_salt_and_verifier("user@test.com", "secret")
      {salt2, _} = Password.generate_salt_and_verifier("user@test.com", "secret")
      assert salt1 != salt2
    end

    test "email is case-insensitive" do
      salt = Base.decode16!("0102030405060708090A0B0C0D0E0F10")

      # Use same salt to compare verifiers
      v1 = BezgelorCrypto.SRP6.generate_verifier(salt, "TEST@EXAMPLE.COM", "password")
      v2 = BezgelorCrypto.SRP6.generate_verifier(salt, "test@example.com", "password")

      assert v1 == v2
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run:
```bash
cd .
mix test apps/bezgelor_crypto/test/bezgelor_crypto/password_test.exs
```

Expected: FAIL - `BezgelorCrypto.Password` module not found.

**Step 3: Write the Password implementation**

Create file `apps/bezgelor_crypto/lib/bezgelor_crypto/password.ex`:

```elixir
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
```

**Step 4: Run test to verify it passes**

Run:
```bash
cd .
mix test apps/bezgelor_crypto/test/bezgelor_crypto/password_test.exs
```

Expected: PASS - 4 tests, 0 failures.

**Step 5: Commit**

Run:
```bash
cd .
git add apps/bezgelor_crypto/lib/bezgelor_crypto/password.ex
git add apps/bezgelor_crypto/test/bezgelor_crypto/password_test.exs
git commit -m "feat(crypto): Add Password module for salt/verifier generation"
```

---

## Task 10: Create bezgelor_db App with Ecto

**Files:**
- Create: `apps/bezgelor_db/mix.exs`
- Create: `apps/bezgelor_db/lib/bezgelor_db.ex`
- Create: `apps/bezgelor_db/lib/bezgelor_db/repo.ex`

**Step 1: Generate the database app**

Run:
```bash
cd ./apps
mix new bezgelor_db --sup
```

**Step 2: Add Ecto dependencies**

Edit `apps/bezgelor_db/mix.exs` to add deps:

```elixir
defmodule BezgelorDb.MixProject do
  use Mix.Project

  def project do
    [
      app: :bezgelor_db,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {BezgelorDb.Application, []}
    ]
  end

  defp deps do
    [
      {:ecto_sql, "~> 3.11"},
      {:postgrex, "~> 0.18"}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
    ]
  end
end
```

**Step 3: Install dependencies**

Run:
```bash
cd .
mix deps.get
```

**Step 4: Create the Repo module**

Create file `apps/bezgelor_db/lib/bezgelor_db/repo.ex`:

```elixir
defmodule BezgelorDb.Repo do
  @moduledoc """
  Main database repository for Bezgelor.

  ## Overview

  This is the primary Ecto Repo for all database operations. It connects
  to PostgreSQL and handles:

  - Account data (users, permissions, roles)
  - Character data (characters, items, quests)
  - World data (guilds, chat channels)

  ## Configuration

  Configure in `config/config.exs`:

      config :bezgelor_db, BezgelorDb.Repo,
        database: "bezgelor_dev",
        username: "postgres",
        password: "postgres",
        hostname: "localhost",
        pool_size: 10
  """

  use Ecto.Repo,
    otp_app: :bezgelor_db,
    adapter: Ecto.Adapters.Postgres
end
```

**Step 5: Update Application to start Repo**

Edit `apps/bezgelor_db/lib/bezgelor_db/application.ex`:

```elixir
defmodule BezgelorDb.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      BezgelorDb.Repo
    ]

    opts = [strategy: :one_for_one, name: BezgelorDb.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

**Step 6: Add Repo configuration**

Edit `config/config.exs` to add:

```elixir
import Config

config :bezgelor_db,
  ecto_repos: [BezgelorDb.Repo]

config :bezgelor_db, BezgelorDb.Repo,
  database: "bezgelor_dev",
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  pool_size: 10

import_config "#{config_env()}.exs"
```

Create `config/dev.exs`:

```elixir
import Config

config :bezgelor_db, BezgelorDb.Repo,
  database: "bezgelor_dev",
  show_sensitive_data_on_connection_error: true,
  pool_size: 10
```

Create `config/test.exs`:

```elixir
import Config

config :bezgelor_db, BezgelorDb.Repo,
  database: "bezgelor_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

config :logger, level: :warning
```

Create `config/prod.exs`:

```elixir
import Config

# Production config loaded from environment variables at runtime
```

Create `config/runtime.exs`:

```elixir
import Config

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise "DATABASE_URL environment variable is missing"

  config :bezgelor_db, BezgelorDb.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")
end
```

**Step 7: Create the database**

Run:
```bash
cd .
mix ecto.create
```

Expected: Database `bezgelor_dev` created.

**Step 8: Commit**

Run:
```bash
cd .
git add apps/bezgelor_db
git add config/
git commit -m "feat(db): Add bezgelor_db app with Ecto and PostgreSQL"
```

---

## Task 11: Create Account Schema and Migration

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/schema/account.ex`
- Create: `apps/bezgelor_db/priv/repo/migrations/[timestamp]_create_accounts.exs`
- Test: `apps/bezgelor_db/test/bezgelor_db/schema/account_test.exs`

**Step 1: Generate migration**

Run:
```bash
cd .
mix ecto.gen.migration create_accounts --migrations-path apps/bezgelor_db/priv/repo/migrations
```

**Step 2: Write the migration**

Edit the generated migration file:

```elixir
defmodule BezgelorDb.Repo.Migrations.CreateAccounts do
  use Ecto.Migration

  def change do
    create table(:accounts, primary_key: false) do
      add :id, :serial, primary_key: true
      add :email, :string, null: false
      add :salt, :string, null: false      # Hex-encoded SRP6 salt
      add :verifier, :string, null: false  # Hex-encoded SRP6 verifier
      add :game_token, :string             # Current game session token
      add :session_key, :string            # Current session key (hex)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:accounts, [:email])
    create index(:accounts, [:game_token])
  end
end
```

**Step 3: Run migration**

Run:
```bash
cd .
mix ecto.migrate
```

Expected: Migration runs successfully.

**Step 4: Write the test for Account schema**

Create file `apps/bezgelor_db/test/bezgelor_db/schema/account_test.exs`:

```elixir
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
```

**Step 5: Run test to verify it fails**

Run:
```bash
cd .
mix test apps/bezgelor_db/test/bezgelor_db/schema/account_test.exs
```

Expected: FAIL - `BezgelorDb.Schema.Account` module not found.

**Step 6: Write the Account schema**

Create file `apps/bezgelor_db/lib/bezgelor_db/schema/account.ex`:

```elixir
defmodule BezgelorDb.Schema.Account do
  @moduledoc """
  Database schema for user accounts.

  ## Overview

  Accounts represent registered users. Each account can have multiple
  characters. Authentication uses SRP6 - the password is never stored,
  only a verifier derived from it.

  ## Fields

  - `email` - Unique email address (lowercased)
  - `salt` - SRP6 salt (hex string)
  - `verifier` - SRP6 password verifier (hex string)
  - `game_token` - Current game session token
  - `session_key` - Current session key for packet encryption

  ## Example

      # Creating a new account
      {salt, verifier} = BezgelorCrypto.Password.generate_salt_and_verifier(email, password)

      %Account{}
      |> Account.changeset(%{email: email, salt: salt, verifier: verifier})
      |> Repo.insert()
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          email: String.t() | nil,
          salt: String.t() | nil,
          verifier: String.t() | nil,
          game_token: String.t() | nil,
          session_key: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "accounts" do
    field :email, :string
    field :salt, :string
    field :verifier, :string
    field :game_token, :string
    field :session_key, :string

    timestamps(type: :utc_datetime)
  end

  @doc """
  Build a changeset for creating or updating an account.

  ## Validations

  - Email is required and must be valid format
  - Email is lowercased for consistency
  - Salt and verifier are required for new accounts
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(account, attrs) do
    account
    |> cast(attrs, [:email, :salt, :verifier, :game_token, :session_key])
    |> validate_required([:email, :salt, :verifier])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/, message: "has invalid format")
    |> update_change(:email, &String.downcase/1)
    |> unique_constraint(:email)
  end

  @doc """
  Changeset for updating session information only.
  """
  @spec session_changeset(t(), map()) :: Ecto.Changeset.t()
  def session_changeset(account, attrs) do
    account
    |> cast(attrs, [:game_token, :session_key])
  end
end
```

**Step 7: Run test to verify it passes**

Run:
```bash
cd .
mix test apps/bezgelor_db/test/bezgelor_db/schema/account_test.exs
```

Expected: PASS - 4 tests, 0 failures.

**Step 8: Commit**

Run:
```bash
cd .
git add apps/bezgelor_db/lib/bezgelor_db/schema/account.ex
git add apps/bezgelor_db/test/bezgelor_db/schema/account_test.exs
git add apps/bezgelor_db/priv/repo/migrations/
git commit -m "feat(db): Add Account schema with SRP6 fields"
```

---

## Task 12: Create Character Schema and Migration

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/schema/character.ex`
- Create: `apps/bezgelor_db/priv/repo/migrations/[timestamp]_create_characters.exs`
- Test: `apps/bezgelor_db/test/bezgelor_db/schema/character_test.exs`

**Step 1: Generate migration**

Run:
```bash
cd .
mix ecto.gen.migration create_characters --migrations-path apps/bezgelor_db/priv/repo/migrations
```

**Step 2: Write the migration**

Edit the generated migration file:

```elixir
defmodule BezgelorDb.Repo.Migrations.CreateCharacters do
  use Ecto.Migration

  def change do
    create table(:characters, primary_key: false) do
      add :id, :bigserial, primary_key: true
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :name, :string, size: 24, null: false
      add :sex, :smallint, null: false
      add :race, :smallint, null: false
      add :class, :smallint, null: false
      add :level, :smallint, null: false, default: 1
      add :faction_id, :smallint, null: false

      # Position
      add :location_x, :float, null: false, default: 0.0
      add :location_y, :float, null: false, default: 0.0
      add :location_z, :float, null: false, default: 0.0
      add :rotation_x, :float, null: false, default: 0.0
      add :rotation_y, :float, null: false, default: 0.0
      add :rotation_z, :float, null: false, default: 0.0
      add :world_id, :smallint, null: false
      add :world_zone_id, :smallint, null: false

      # State
      add :title, :smallint, default: 0
      add :active_path, :integer, default: 0
      add :active_costume_index, :smallint, default: -1
      add :active_spec, :smallint, default: 0
      add :innate_index, :smallint, default: 0
      add :total_xp, :integer, default: 0
      add :rest_bonus_xp, :integer, default: 0
      add :time_played_total, :integer, default: 0
      add :time_played_level, :integer, default: 0
      add :flags, :integer, default: 0

      # Timestamps
      add :last_online, :utc_datetime
      add :deleted_at, :utc_datetime
      add :original_name, :string, size: 24

      timestamps(type: :utc_datetime)
    end

    create unique_index(:characters, [:name], where: "deleted_at IS NULL")
    create index(:characters, [:account_id])
  end
end
```

**Step 3: Run migration**

Run:
```bash
cd .
mix ecto.migrate
```

Expected: Migration runs successfully.

**Step 4: Write the test for Character schema**

Create file `apps/bezgelor_db/test/bezgelor_db/schema/character_test.exs`:

```elixir
defmodule BezgelorDb.Schema.CharacterTest do
  use ExUnit.Case, async: true

  alias BezgelorDb.Schema.Character

  describe "changeset/2" do
    test "valid changeset with required fields" do
      attrs = %{
        account_id: 1,
        name: "TestCharacter",
        sex: 0,
        race: 1,
        class: 1,
        faction_id: 166,
        world_id: 870,
        world_zone_id: 6
      }

      changeset = Character.changeset(%Character{}, attrs)
      assert changeset.valid?
    end

    test "invalid with name too short" do
      attrs = %{
        account_id: 1,
        name: "AB",
        sex: 0,
        race: 1,
        class: 1,
        faction_id: 166,
        world_id: 870,
        world_zone_id: 6
      }

      changeset = Character.changeset(%Character{}, attrs)
      refute changeset.valid?
      assert "should be at least 3 character(s)" in errors_on(changeset).name
    end

    test "invalid with name too long" do
      attrs = %{
        account_id: 1,
        name: String.duplicate("a", 25),
        sex: 0,
        race: 1,
        class: 1,
        faction_id: 166,
        world_id: 870,
        world_zone_id: 6
      }

      changeset = Character.changeset(%Character{}, attrs)
      refute changeset.valid?
      assert "should be at most 24 character(s)" in errors_on(changeset).name
    end
  end

  describe "position_changeset/2" do
    test "updates position fields" do
      character = %Character{
        location_x: 0.0,
        location_y: 0.0,
        location_z: 0.0
      }

      attrs = %{location_x: 100.5, location_y: 50.0, location_z: 200.75}
      changeset = Character.position_changeset(character, attrs)

      assert changeset.valid?
      assert changeset.changes.location_x == 100.5
      assert changeset.changes.location_y == 50.0
      assert changeset.changes.location_z == 200.75
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
```

**Step 5: Run test to verify it fails**

Run:
```bash
cd .
mix test apps/bezgelor_db/test/bezgelor_db/schema/character_test.exs
```

Expected: FAIL - `BezgelorDb.Schema.Character` module not found.

**Step 6: Write the Character schema**

Create file `apps/bezgelor_db/lib/bezgelor_db/schema/character.ex`:

```elixir
defmodule BezgelorDb.Schema.Character do
  @moduledoc """
  Database schema for player characters.

  ## Overview

  Characters are the playable entities in the game world. Each account
  can have multiple characters. Characters store persistent state like
  level, position, and various progression data.

  ## Fields

  ### Identity
  - `name` - Unique character name (3-24 characters)
  - `sex` - Character sex (0 = male, 1 = female)
  - `race` - Race ID (Human, Aurin, etc.)
  - `class` - Class ID (Warrior, Esper, etc.)
  - `faction_id` - Faction (Exile or Dominion)

  ### Progression
  - `level` - Current level (1-50)
  - `total_xp` - Total experience points earned
  - `rest_bonus_xp` - Rested XP bonus

  ### Position
  - `location_x/y/z` - World coordinates
  - `rotation_x/y/z` - Character facing
  - `world_id` - Current world/continent
  - `world_zone_id` - Current zone within world

  ## Associations

  - `belongs_to :account` - The owning account
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BezgelorDb.Schema.Account

  @type t :: %__MODULE__{
          id: integer() | nil,
          account_id: integer() | nil,
          account: Account.t() | Ecto.Association.NotLoaded.t() | nil,
          name: String.t() | nil,
          sex: integer() | nil,
          race: integer() | nil,
          class: integer() | nil,
          level: integer(),
          faction_id: integer() | nil,
          location_x: float(),
          location_y: float(),
          location_z: float(),
          rotation_x: float(),
          rotation_y: float(),
          rotation_z: float(),
          world_id: integer() | nil,
          world_zone_id: integer() | nil,
          title: integer(),
          active_path: integer(),
          active_costume_index: integer(),
          active_spec: integer(),
          innate_index: integer(),
          total_xp: integer(),
          rest_bonus_xp: integer(),
          time_played_total: integer(),
          time_played_level: integer(),
          flags: integer(),
          last_online: DateTime.t() | nil,
          deleted_at: DateTime.t() | nil,
          original_name: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "characters" do
    belongs_to :account, Account

    field :name, :string
    field :sex, :integer
    field :race, :integer
    field :class, :integer
    field :level, :integer, default: 1
    field :faction_id, :integer

    # Position
    field :location_x, :float, default: 0.0
    field :location_y, :float, default: 0.0
    field :location_z, :float, default: 0.0
    field :rotation_x, :float, default: 0.0
    field :rotation_y, :float, default: 0.0
    field :rotation_z, :float, default: 0.0
    field :world_id, :integer
    field :world_zone_id, :integer

    # State
    field :title, :integer, default: 0
    field :active_path, :integer, default: 0
    field :active_costume_index, :integer, default: -1
    field :active_spec, :integer, default: 0
    field :innate_index, :integer, default: 0
    field :total_xp, :integer, default: 0
    field :rest_bonus_xp, :integer, default: 0
    field :time_played_total, :integer, default: 0
    field :time_played_level, :integer, default: 0
    field :flags, :integer, default: 0

    # Timestamps
    field :last_online, :utc_datetime
    field :deleted_at, :utc_datetime
    field :original_name, :string

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(account_id name sex race class faction_id world_id world_zone_id)a
  @optional_fields ~w(level location_x location_y location_z rotation_x rotation_y rotation_z
                      title active_path active_costume_index active_spec innate_index
                      total_xp rest_bonus_xp time_played_total time_played_level flags
                      last_online deleted_at original_name)a

  @doc """
  Build a changeset for creating or updating a character.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(character, attrs) do
    character
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:name, min: 3, max: 24)
    |> foreign_key_constraint(:account_id)
    |> unique_constraint(:name)
  end

  @doc """
  Changeset for updating character position.
  """
  @spec position_changeset(t(), map()) :: Ecto.Changeset.t()
  def position_changeset(character, attrs) do
    character
    |> cast(attrs, [:location_x, :location_y, :location_z,
                    :rotation_x, :rotation_y, :rotation_z,
                    :world_id, :world_zone_id])
  end

  @doc """
  Changeset for soft-deleting a character.
  """
  @spec delete_changeset(t()) :: Ecto.Changeset.t()
  def delete_changeset(character) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    character
    |> change(deleted_at: now, original_name: character.name)
  end
end
```

**Step 7: Run test to verify it passes**

Run:
```bash
cd .
mix test apps/bezgelor_db/test/bezgelor_db/schema/character_test.exs
```

Expected: PASS - 4 tests, 0 failures.

**Step 8: Commit**

Run:
```bash
cd .
git add apps/bezgelor_db/lib/bezgelor_db/schema/character.ex
git add apps/bezgelor_db/test/bezgelor_db/schema/character_test.exs
git add apps/bezgelor_db/priv/repo/migrations/
git commit -m "feat(db): Add Character schema with position and progression fields"
```

---

## Task 13: Run All Tests and Final Commit

**Step 1: Run all tests**

Run:
```bash
cd .
mix test
```

Expected: All tests pass.

**Step 2: Check test coverage**

Run:
```bash
cd .
mix test --cover
```

Review coverage report.

**Step 3: Format code**

Run:
```bash
cd .
mix format
```

**Step 4: Final commit**

Run:
```bash
cd .
git add -A
git status
# If any changes from formatting:
git commit -m "chore: Format code and complete Phase 1 foundation"
```

---

## Summary

Phase 1 establishes:

1. **Umbrella structure** — Clean separation between apps
2. **bezgelor_core** — Types (Vector3) and Config utilities
3. **bezgelor_crypto** — Full cryptography suite:
   - Random number generation
   - SRP6 authentication protocol
   - Packet encryption/decryption
   - Password handling
4. **bezgelor_db** — Database layer:
   - Ecto Repo with PostgreSQL
   - Account schema (SRP6 auth fields)
   - Character schema (full WildStar character data)

Next phases will build on this foundation:
- Phase 2: Protocol layer (packet parsing)
- Phase 3: Authentication server
- Phase 4: Character management
- Phase 5: World entry

---

## Implementation Status

| Task | Description | Status |
|------|-------------|--------|
| 1 | Create Umbrella Project Structure | ✅ Done |
| 2 | Create bezgelor_core App | ✅ Done |
| 3 | Add Core Types Module (Vector3) | ✅ Done |
| 4 | Add Core Config Module | ✅ Done |
| 5 | Create bezgelor_crypto App | ✅ Done |
| 6 | Implement RandomProvider | ✅ Done |
| 7 | Implement SRP6 Provider | ✅ Done |
| 8 | Implement PacketCrypt | ✅ Done |
| 9 | Implement Password Provider | ✅ Done |
| 10 | Create bezgelor_db App with Ecto | ✅ Done |
| 11 | Create Account Schema and Migration | ✅ Done |
| 12 | Create Character Schema and Migration | ✅ Done |
| 13 | Run All Tests and Final Commit | ✅ Done |

## Success Criteria

| # | Criterion | Status |
|---|-----------|--------|
| 1 | Umbrella project structure exists with apps/ directory | ✅ Done |
| 2 | bezgelor_core app with Vector3 type and Config module | ✅ Done |
| 3 | bezgelor_crypto app with Random, SRP6, PacketCrypt, Password modules | ✅ Done |
| 4 | bezgelor_db app with Ecto Repo and PostgreSQL connection | ✅ Done |
| 5 | Account schema with SRP6 authentication fields | ✅ Done |
| 6 | Character schema with position and progression fields | ✅ Done |
| 7 | All tests pass | ✅ Done |

## Implementation Notes

**Files Implemented:**

*bezgelor_core:*
- `apps/bezgelor_core/lib/bezgelor_core/types.ex` - Vector3 type with distance calculation
- `apps/bezgelor_core/lib/bezgelor_core/config.ex` - Configuration access utilities
- `apps/bezgelor_core/lib/bezgelor_core/application.ex` - Application supervision tree

*bezgelor_crypto:*
- `apps/bezgelor_crypto/lib/bezgelor_crypto/random.ex` - CSPRNG wrapper
- `apps/bezgelor_crypto/lib/bezgelor_crypto/srp6.ex` - SRP6 authentication protocol
- `apps/bezgelor_crypto/lib/bezgelor_crypto/packet_crypt.ex` - WildStar packet encryption
- `apps/bezgelor_crypto/lib/bezgelor_crypto/password.ex` - Salt/verifier generation

*bezgelor_db:*
- `apps/bezgelor_db/lib/bezgelor_db/repo.ex` - Ecto Repo with PostgreSQL adapter
- `apps/bezgelor_db/lib/bezgelor_db/application.ex` - Application with Repo supervision
- `apps/bezgelor_db/lib/bezgelor_db/schema/account.ex` - Account schema with SRP6 fields
- `apps/bezgelor_db/lib/bezgelor_db/schema/character.ex` - Character schema with full WildStar data

*Tests:*
- `apps/bezgelor_core/test/bezgelor_core/types_test.exs`
- `apps/bezgelor_core/test/bezgelor_core/config_test.exs`
- `apps/bezgelor_crypto/test/bezgelor_crypto/random_test.exs`
- `apps/bezgelor_crypto/test/bezgelor_crypto/srp6_test.exs`
- `apps/bezgelor_crypto/test/bezgelor_crypto/packet_crypt_test.exs`
- `apps/bezgelor_crypto/test/bezgelor_crypto/password_test.exs`
- `apps/bezgelor_db/test/bezgelor_db/schema/account_test.exs`
- `apps/bezgelor_db/test/bezgelor_db/schema/character_test.exs`
