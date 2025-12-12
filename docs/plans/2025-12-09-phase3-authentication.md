# Phase 3: Authentication - Implementation Plan

**Status:** ✅ Complete

**Goal:** Implement the full SRP6 authentication handshake so clients can log in.

**Outcome:** A client can connect to port 6600, authenticate with email/password via SRP6, receive a game token, and be ready for realm selection.

---

## Overview

NexusForever has two auth-related servers:
1. **STS Server (port 6600)** - SRP6 password verification, issues game tokens
2. **Auth Server (port 23115)** - Validates game tokens, provides realm info

For Phase 3, we'll implement the **STS Server flow** on port 6600, which handles:
- SRP6 handshake (ServerHello → ClientHelloAuth → key exchange)
- Game token generation
- Account lookup and creation

The Auth Server (port 23115) and realm selection will be Phase 4.

### Authentication Packet Sequence

```
Client connects to port 6600
        │
        ▼
┌───────────────────────────────────────┐
│ Server sends: ServerHello             │
│   - AuthVersion: 16042                │
│   - ConnectionType: 3 (auth)          │
│   - AuthMessage: 0x97998A0            │
└───────────────────────────────────────┘
        │
        ▼
┌───────────────────────────────────────┐
│ Client sends: ClientHelloAuth         │
│   - Build version                     │
│   - Email address                     │
│   - SRP6 public key (A)               │
│   - Client evidence (M1)              │
└───────────────────────────────────────┘
        │
        ▼
┌───────────────────────────────────────┐
│ Server performs:                      │
│   1. Look up account by email         │
│   2. Load salt (S) and verifier (V)   │
│   3. Verify M1 with SRP6              │
│   4. Generate session key             │
│   5. Generate game token              │
└───────────────────────────────────────┘
        │
        ▼
┌───────────────────────────────────────┐
│ Server sends: ServerAuthEncrypted     │
│   containing ServerAuthAccepted       │
│   OR ServerAuthDenied                 │
└───────────────────────────────────────┘
```

### Key Elixir Concepts Introduced

1. **GenStateMachine** - State machine for auth flow
2. **Ecto Queries** - Account lookup and updates
3. **Binary Protocol** - Complex packet structures
4. **Integration Testing** - Full client simulation

---

## Tasks

### Batch 1: Packet Definitions (Tasks 1-3)

| Task | Description | Status |
|------|-------------|--------|
| 1 | Define ClientHelloAuth packet struct | ✅ Done |
| 2 | Define ServerAuthAccepted/Denied packets | ✅ Done |
| 3 | Define ServerRealmInfo packet | ✅ Done |

### Batch 2: Auth Handler (Tasks 4-6)

| Task | Description | Status |
|------|-------------|--------|
| 4 | Implement ClientHelloAuth handler | ✅ Done |
| 5 | Add account lookup via bezgelor_db | ✅ Done |
| 6 | Integrate SRP6 verification | ✅ Done |

### Batch 3: Session Management (Tasks 7-9)

| Task | Description | Status |
|------|-------------|--------|
| 7 | Generate and store game tokens | ✅ Done |
| 8 | Generate and store session keys | ✅ Done |
| 9 | Handle account suspension checks | ✅ Done |

### Batch 4: Server Setup (Tasks 10-12)

| Task | Description | Status |
|------|-------------|--------|
| 10 | Create AuthServer application | ✅ Done |
| 11 | Configure port 6600 listener | ✅ Done |
| 12 | Integration test with mock client | ✅ Done |

---

## Task 1: Define ClientHelloAuth Packet

**Files:**
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/client_hello_auth.ex`
- Test: `apps/bezgelor_protocol/test/bezgelor_protocol/packets/client_hello_auth_test.exs`

**ClientHelloAuth Structure (opcode 0x0004):**

```elixir
defmodule BezgelorProtocol.Packets.ClientHelloAuth do
  @moduledoc """
  Client authentication request packet.

  Sent by client after receiving ServerHello.
  Contains SRP6 credentials for authentication.
  """

  @behaviour BezgelorProtocol.Packet.Readable

  defstruct [
    :build,           # uint32 - Must be 16042
    :email,           # wide_string - Account email
    :client_key_a,    # 128 bytes - SRP6 public key
    :client_proof_m1  # 32 bytes - SHA256 evidence
  ]

  @impl true
  def opcode, do: :client_hello_auth

  @impl true
  def read(reader) do
    # Parse packet using PacketReader
  end
end
```

**Test:**
```elixir
test "parses ClientHelloAuth packet" do
  # Build test packet binary
  payload = build_client_hello_auth("test@example.com", fake_key_a(), fake_m1())

  reader = PacketReader.new(payload)
  {:ok, packet, _reader} = ClientHelloAuth.read(reader)

  assert packet.build == 16042
  assert packet.email == "test@example.com"
  assert byte_size(packet.client_key_a) == 128
  assert byte_size(packet.client_proof_m1) == 32
end
```

---

## Task 2: Define Server Auth Response Packets

**Files:**
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/server_auth_accepted.ex`
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/server_auth_denied.ex`

**ServerAuthAccepted (opcode 0x0005):**
```elixir
defmodule BezgelorProtocol.Packets.ServerAuthAccepted do
  @behaviour BezgelorProtocol.Packet.Writable

  defstruct [
    :server_proof_m2,  # 32 bytes - Server evidence
    :game_token        # 16 bytes - GUID for Auth Server
  ]

  @impl true
  def opcode, do: :server_auth_accepted

  @impl true
  def write(packet, writer) do
    writer
    |> PacketWriter.write_bytes(packet.server_proof_m2)
    |> PacketWriter.write_bytes(packet.game_token)
  end
end
```

**ServerAuthDenied (opcode 0x0006):**
```elixir
defmodule BezgelorProtocol.Packets.ServerAuthDenied do
  @behaviour BezgelorProtocol.Packet.Writable

  defstruct [
    :result,          # uint32 - NpLoginResult enum
    :error_value,     # uint32 - Additional error code
    :suspended_days   # float32 - Days remaining if suspended
  ]

  @login_results %{
    unknown: 0,
    success: 1,
    database_error: 2,
    invalid_token: 16,
    version_mismatch: 19,
    account_banned: 20,
    account_suspended: 21
  }

  @impl true
  def opcode, do: :server_auth_denied
end
```

---

## Task 3: Define ServerRealmInfo Packet

**Files:**
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/server_realm_info.ex`

**ServerRealmInfo (opcode 0x0117):**
```elixir
defmodule BezgelorProtocol.Packets.ServerRealmInfo do
  @behaviour BezgelorProtocol.Packet.Writable

  defstruct [
    :account_id,      # uint32
    :realm_id,        # uint32
    :realm_name,      # wide_string
    :realm_address,   # string (IP:port)
    :session_key      # 16 bytes
  ]

  @impl true
  def opcode, do: :server_realm_info
end
```

---

## Task 4: Implement ClientHelloAuth Handler

**Files:**
- Modify: `apps/bezgelor_protocol/lib/bezgelor_protocol/handler/auth_handler.ex`

**Handler Logic:**
```elixir
defmodule BezgelorProtocol.Handler.AuthHandler do
  @behaviour BezgelorProtocol.Handler

  alias BezgelorProtocol.Packets.{ClientHelloAuth, ServerAuthAccepted, ServerAuthDenied}
  alias BezgelorProtocol.PacketReader
  alias BezgelorCrypto.SRP6
  alias BezgelorDb.Schema.Account

  require Logger

  @impl true
  def handle(payload, state) do
    with {:ok, packet, _} <- parse_packet(payload),
         :ok <- validate_build(packet.build),
         {:ok, account} <- lookup_account(packet.email),
         {:ok, proof_m2} <- verify_srp6(account, packet) do

      # Generate game token
      game_token = generate_game_token()
      update_account_token(account, game_token)

      # Build response
      response = %ServerAuthAccepted{
        server_proof_m2: proof_m2,
        game_token: game_token
      }

      {:reply, :server_auth_accepted, encode_packet(response), state}
    else
      {:error, reason} ->
        response = build_denial(reason)
        {:reply, :server_auth_denied, encode_packet(response), state}
    end
  end

  defp validate_build(16042), do: :ok
  defp validate_build(_), do: {:error, :version_mismatch}

  defp lookup_account(email) do
    case BezgelorDb.Repo.get_by(Account, email: String.downcase(email)) do
      nil -> {:error, :account_not_found}
      account -> {:ok, account}
    end
  end

  defp verify_srp6(account, packet) do
    # Use existing SRP6 module from bezgelor_crypto
    salt = Base.decode16!(account.salt)
    verifier = Base.decode16!(account.verifier)

    case SRP6.verify_client(salt, verifier, packet.client_key_a, packet.client_proof_m1) do
      {:ok, proof_m2} -> {:ok, proof_m2}
      :error -> {:error, :invalid_credentials}
    end
  end
end
```

---

## Task 5: Add Account Lookup via bezgelor_db

**Files:**
- Modify: `apps/bezgelor_db/lib/bezgelor_db/accounts.ex` (create context module)

**Context Module:**
```elixir
defmodule BezgelorDb.Accounts do
  @moduledoc """
  Account management context.
  """

  alias BezgelorDb.Repo
  alias BezgelorDb.Schema.Account

  @doc "Get account by email address."
  def get_by_email(email) when is_binary(email) do
    Repo.get_by(Account, email: String.downcase(email))
  end

  @doc "Get account by email and game token."
  def get_by_token(email, game_token) do
    Repo.get_by(Account,
      email: String.downcase(email),
      game_token: game_token
    )
  end

  @doc "Update account's game token."
  def update_game_token(account, token) do
    account
    |> Account.changeset(%{game_token: token})
    |> Repo.update()
  end

  @doc "Update account's session key."
  def update_session_key(account, key) do
    account
    |> Account.changeset(%{session_key: key})
    |> Repo.update()
  end

  @doc "Create a new account with SRP6 credentials."
  def create_account(email, password) do
    {salt, verifier} = BezgelorCrypto.Password.generate_salt_and_verifier(email, password)

    %Account{}
    |> Account.changeset(%{
      email: String.downcase(email),
      salt: salt,
      verifier: verifier
    })
    |> Repo.insert()
  end
end
```

---

## Task 6: Integrate SRP6 Verification

**Files:**
- Modify: `apps/bezgelor_crypto/lib/bezgelor_crypto/srp6.ex`

**Add Server-Side Verification:**

The existing SRP6 module has `generate_verifier/3`. We need to add:

```elixir
@doc """
Verify client's SRP6 proof and return server proof.

## Parameters
- salt: The account's salt (binary)
- verifier: The stored verifier (binary)
- client_public: Client's public key A (128 bytes)
- client_proof: Client's evidence M1 (32 bytes)

## Returns
- {:ok, server_proof} on success
- :error on verification failure
"""
@spec verify_client(binary(), binary(), binary(), binary()) ::
  {:ok, binary()} | :error
def verify_client(salt, verifier, client_public, client_proof) do
  # Generate server private key
  server_private = Random.bytes(128)

  # Calculate server public key B
  server_public = calculate_server_public(verifier, server_private)

  # Calculate shared secret
  secret = calculate_shared_secret(client_public, verifier, server_private)

  # Derive session key
  session_key = derive_session_key(secret)

  # Calculate expected client proof
  expected_m1 = calculate_client_proof(salt, client_public, server_public, session_key)

  # Verify
  if secure_compare(client_proof, expected_m1) do
    server_proof = calculate_server_proof(client_public, client_proof, session_key)
    {:ok, server_proof}
  else
    :error
  end
end
```

---

## Task 7: Generate and Store Game Tokens

**Files:**
- Modify: `apps/bezgelor_crypto/lib/bezgelor_crypto/random.ex`

**Add UUID Generation:**
```elixir
@doc "Generate a random UUID (16 bytes)."
@spec uuid() :: binary()
def uuid do
  bytes(16)
end

@doc "Generate a UUID as a hex string."
@spec uuid_hex() :: String.t()
def uuid_hex do
  uuid() |> Base.encode16()
end
```

---

## Task 8: Generate and Store Session Keys

Session keys are 16 random bytes used by the Auth Server (Phase 4) to validate clients connecting to realm servers.

```elixir
# In AuthHandler after successful auth:
session_key = BezgelorCrypto.Random.bytes(16) |> Base.encode16()
BezgelorDb.Accounts.update_session_key(account, session_key)
```

---

## Task 9: Handle Account Suspension Checks

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/schema/account_suspension.ex`
- Modify: `apps/bezgelor_db/lib/bezgelor_db/accounts.ex`

**Suspension Schema:**
```elixir
defmodule BezgelorDb.Schema.AccountSuspension do
  use Ecto.Schema
  import Ecto.Changeset

  schema "account_suspensions" do
    belongs_to :account, BezgelorDb.Schema.Account
    field :reason, :string
    field :start_time, :utc_datetime
    field :end_time, :utc_datetime  # nil = permanent ban

    timestamps()
  end
end
```

**Check Logic:**
```elixir
def check_suspension(account) do
  suspensions = Repo.preload(account, :suspensions).suspensions

  cond do
    # Permanent ban
    Enum.any?(suspensions, &is_nil(&1.end_time)) ->
      {:error, :account_banned}

    # Active suspension
    active = Enum.find(suspensions, &(DateTime.compare(&1.end_time, DateTime.utc_now()) == :gt)) ->
      days = DateTime.diff(active.end_time, DateTime.utc_now(), :day)
      {:error, {:account_suspended, days}}

    # No active suspensions
    true ->
      :ok
  end
end
```

---

## Task 10: Create AuthServer Application

**Files:**
- Create: `apps/bezgelor_auth/` (new umbrella app)

**Structure:**
```
apps/bezgelor_auth/
├── lib/
│   ├── bezgelor_auth.ex
│   └── bezgelor_auth/
│       ├── application.ex
│       └── supervisor.ex
├── mix.exs
└── test/
```

**Application:**
```elixir
defmodule BezgelorAuth.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {BezgelorProtocol.TcpListener, [
        port: Application.get_env(:bezgelor_auth, :port, 6600),
        handler: BezgelorProtocol.Connection,
        handler_opts: [connection_type: :auth],
        name: :auth_listener
      ]}
    ]

    opts = [strategy: :one_for_one, name: BezgelorAuth.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

---

## Task 11: Configure Port 6600 Listener

**Files:**
- Create: `config/auth.exs`

**Configuration:**
```elixir
import Config

config :bezgelor_auth,
  port: String.to_integer(System.get_env("AUTH_PORT", "6600"))
```

---

## Task 12: Integration Test with Mock Client

**Files:**
- Create: `apps/bezgelor_auth/test/integration/auth_flow_test.exs`

**Test:**
```elixir
defmodule BezgelorAuth.AuthFlowTest do
  use ExUnit.Case

  alias BezgelorProtocol.{Framing, PacketWriter, PacketReader, Opcode}
  alias BezgelorDb.Accounts

  @moduletag :integration

  setup do
    # Create test account
    {:ok, account} = Accounts.create_account("test@example.com", "password123")

    on_exit(fn ->
      BezgelorDb.Repo.delete(account)
    end)

    %{account: account}
  end

  test "successful authentication flow", %{account: account} do
    # Connect to auth server
    {:ok, socket} = :gen_tcp.connect(~c"localhost", 6600, [:binary, active: false])

    # Receive ServerHello
    {:ok, hello_data} = :gen_tcp.recv(socket, 0, 5000)
    {:ok, [{hello_opcode, _}], _} = Framing.parse_packets(hello_data)
    assert hello_opcode == Opcode.to_integer(:server_hello)

    # Build and send ClientHelloAuth
    {client_key_a, client_proof_m1} = build_srp6_credentials(account)
    auth_packet = build_client_hello_auth("test@example.com", client_key_a, client_proof_m1)
    :ok = :gen_tcp.send(socket, Framing.frame_packet(Opcode.to_integer(:client_hello_auth), auth_packet))

    # Receive response
    {:ok, response_data} = :gen_tcp.recv(socket, 0, 5000)
    {:ok, [{response_opcode, payload}], _} = Framing.parse_packets(response_data)

    # Should be accepted
    assert response_opcode == Opcode.to_integer(:server_auth_accepted)

    :gen_tcp.close(socket)
  end
end
```

---

## Success Criteria

| # | Criterion | Status |
|---|-----------|--------|
| 1 | ClientHelloAuth packet can be parsed | ✅ Done |
| 2 | ServerAuthAccepted/Denied packets can be sent | ✅ Done |
| 3 | Account lookup works via Ecto | ✅ Done |
| 4 | SRP6 verification validates credentials | ✅ Done |
| 5 | Game tokens are generated and stored | ✅ Done |
| 6 | Session keys are generated and stored | ✅ Done |
| 7 | Account suspensions are checked | ✅ Done |
| 8 | Auth server listens on port 6600 | ✅ Done |
| 9 | Integration test passes end-to-end | ✅ Done |
| 10 | All tests pass | ✅ Done |

---

## Dependencies

**From Previous Phases:**
- `bezgelor_crypto.SRP6` - SRP6 algorithm
- `bezgelor_crypto.Password` - Salt/verifier generation
- `bezgelor_crypto.Random` - Secure random generation
- `bezgelor_db.Account` - Account schema
- `bezgelor_protocol.Connection` - TCP connection handling
- `bezgelor_protocol.PacketReader/Writer` - Binary parsing

**New Dependencies:**
- None (all deps already in umbrella)

---

## Next Phase Preview

**Phase 4: Realm Server** will:
- Listen on port 23115
- Validate game tokens from STS
- Provide realm server list
- Generate session keys for world server
- Handle realm selection

---

## Implementation Notes

**Files Implemented:**
- `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/client_hello_auth.ex` - STS auth request packet
- `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/server_auth_accepted.ex` - STS auth success response
- `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/server_auth_denied.ex` - STS auth failure response
- `apps/bezgelor_protocol/lib/bezgelor_protocol/handler/auth_handler.ex` - STS authentication handler
- `apps/bezgelor_db/lib/bezgelor_db/accounts.ex` - Accounts context module
- `apps/bezgelor_db/lib/bezgelor_db/schema/account.ex` - Account schema
- `apps/bezgelor_db/lib/bezgelor_db/schema/account_suspension.ex` - Suspension tracking schema
- `apps/bezgelor_crypto/lib/bezgelor_crypto/srp6.ex` - SRP6 authentication algorithm
- `apps/bezgelor_crypto/lib/bezgelor_crypto/random.ex` - Secure random generation
- `apps/bezgelor_auth/lib/bezgelor_auth/application.ex` - Auth server application
- `apps/bezgelor_auth/test/integration/auth_flow_test.exs` - Integration tests

**Design Notes:**
- STS packets located in `packets/` root folder (not `packets/sts/` as originally designed)
- Port 6600 configuration in `config/config.exs`
- ServerRealmInfo packet (Task 3) implemented separately in Phase 4 realm packets
