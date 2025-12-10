# Phase 4: Realm Server - Implementation Plan

**Goal:** Implement the Auth Server (port 23115) that validates game tokens and provides realm information.

**Outcome:** After authenticating with STS (port 6600), clients connect to port 23115, validate their game token, and receive realm server info with a session key.

---

## Overview

After Phase 3's STS Server issues a game token, clients connect to the Auth Server (port 23115) which:
1. Validates the game token matches the account
2. Checks account status (bans/suspensions)
3. Generates a session key for World Server auth
4. Sends realm info (IP, port, name)

This is simpler than STS since there's no SRP6 - just token validation and realm selection.

### Authentication Flow

```
Client authenticated with STS (port 6600)
        │
        │ Has: GameToken (16 bytes)
        │
        ▼
Client connects to Auth Server (port 23115)
        │
        ▼
┌───────────────────────────────────────┐
│ Server sends: ServerHello (unencrypted)│
│   - AuthVersion: 16042                │
│   - ConnectionType: 3                 │
│   - AuthMessage: 0x97998A0            │
└───────────────────────────────────────┘
        │
        ▼
┌───────────────────────────────────────┐
│ Client sends: ClientHelloAuth         │
│   - Build version (16042)             │
│   - Email address                     │
│   - GameToken (from STS)              │
│   - Language, GameMode                │
└───────────────────────────────────────┘
        │
        ▼
┌───────────────────────────────────────┐
│ Server performs:                      │
│   1. Validate build version           │
│   2. Look up account by email + token │
│   3. Check account status             │
│   4. Generate session key             │
│   5. Select realm                     │
└───────────────────────────────────────┘
        │
        ▼
┌───────────────────────────────────────┐
│ Server sends (encrypted):             │
│   - ServerAuthAccepted                │
│   - ServerRealmMessages (optional)    │
│   - ServerRealmInfo (IP, port, key)   │
│ OR                                    │
│   - ServerAuthDenied (with reason)    │
└───────────────────────────────────────┘
        │
        ▼
Client disconnects, connects to World Server
```

### Key Packets

| Opcode | Name | Direction | Description |
|--------|------|-----------|-------------|
| 0x0003 | ServerHello | S→C | Initial handshake (unencrypted) |
| 0x0592 | ClientHelloAuth | C→S | Token validation request |
| 0x0591 | ServerAuthAccepted | S→C | Token accepted (encrypted) |
| 0x063D | ServerAuthDenied | S→C | Token rejected (encrypted) |
| 0x0593 | ServerRealmMessages | S→C | Server broadcasts (encrypted) |
| 0x03DB | ServerRealmInfo | S→C | Realm details + session key (encrypted) |

---

## Tasks

### Batch 1: Packet Definitions (Tasks 1-4)

| Task | Description |
|------|-------------|
| 1 | Define ClientHelloAuth packet (port 23115 variant) |
| 2 | Define ServerAuthAccepted packet (realm variant) |
| 3 | Define ServerRealmMessages packet |
| 4 | Define ServerRealmInfo packet |

### Batch 2: Realm Data (Tasks 5-7)

| Task | Description |
|------|-------------|
| 5 | Create Realm schema and migration |
| 6 | Create Realms context module |
| 7 | Add realm seeding/configuration |

### Batch 3: Token Handler (Tasks 8-10)

| Task | Description |
|------|-------------|
| 8 | Implement ClientHelloAuth handler (realm) |
| 9 | Add game token validation |
| 10 | Generate and store session keys |

### Batch 4: Realm Server (Tasks 11-13)

| Task | Description |
|------|-------------|
| 11 | Create bezgelor_realm application |
| 12 | Configure port 23115 listener |
| 13 | Integration test with mock client |

---

## Task 1: Define ClientHelloAuth Packet (Realm Variant)

**Files:**
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/realm/client_hello_auth.ex`
- Test: `apps/bezgelor_protocol/test/bezgelor_protocol/packets/realm/client_hello_auth_test.exs`

The realm ClientHelloAuth differs from the STS variant - includes game token instead of SRP6 keys.

**Packet Structure (opcode 0x0592):**

```elixir
defmodule BezgelorProtocol.Packets.Realm.ClientHelloAuth do
  @moduledoc """
  Client authentication request for realm server.

  Sent after receiving ServerHello on port 23115.
  Contains game token from STS server for validation.
  """

  @behaviour BezgelorProtocol.Packet.Readable

  defstruct [
    :build,              # uint32 - Must be 16042
    :crypt_key_integer,  # uint64 - Always 0x1588
    :email,              # wide_string - Account email
    :uuid_1,             # 16 bytes - Client UUID
    :game_token,         # 16 bytes - Token from STS
    :inet_address,       # uint32 - Client IP
    :language,           # uint32 - Language enum
    :game_mode,          # uint32 - Game mode
    :unused,             # uint32
    :hardware_info,      # Hardware info structure
    :realm_datacenter_id # uint32 - Preferred datacenter
  ]

  @impl true
  def opcode, do: :client_hello_auth_realm

  @impl true
  def read(reader) do
    with {:ok, build, reader} <- PacketReader.read_uint32(reader),
         {:ok, crypt_key, reader} <- PacketReader.read_uint64(reader),
         {:ok, email, reader} <- PacketReader.read_wide_string(reader),
         {:ok, uuid_1, reader} <- PacketReader.read_bytes(reader, 16),
         {:ok, game_token, reader} <- PacketReader.read_bytes(reader, 16),
         {:ok, inet_address, reader} <- PacketReader.read_uint32(reader),
         {:ok, language, reader} <- PacketReader.read_uint32(reader),
         {:ok, game_mode, reader} <- PacketReader.read_uint32(reader),
         {:ok, unused, reader} <- PacketReader.read_uint32(reader),
         {:ok, hardware_info, reader} <- read_hardware_info(reader),
         {:ok, datacenter_id, reader} <- PacketReader.read_uint32(reader) do
      packet = %__MODULE__{
        build: build,
        crypt_key_integer: crypt_key,
        email: email,
        uuid_1: uuid_1,
        game_token: game_token,
        inet_address: inet_address,
        language: language,
        game_mode: game_mode,
        unused: unused,
        hardware_info: hardware_info,
        realm_datacenter_id: datacenter_id
      }
      {:ok, packet, reader}
    end
  end
end
```

---

## Task 2: Define ServerAuthAccepted (Realm Variant)

**Files:**
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/realm/server_auth_accepted.ex`

**Packet Structure (opcode 0x0591):**

```elixir
defmodule BezgelorProtocol.Packets.Realm.ServerAuthAccepted do
  @moduledoc """
  Server acceptance of game token.

  Sent after validating client's game token.
  Followed by ServerRealmMessages and ServerRealmInfo.
  """

  @behaviour BezgelorProtocol.Packet.Writable

  defstruct [
    disconnected_for_lag: 0  # uint32 - Lag disconnect flag
  ]

  @impl true
  def opcode, do: :server_auth_accepted_realm

  @impl true
  def write(packet, writer) do
    PacketWriter.write_uint32(writer, packet.disconnected_for_lag)
  end
end
```

---

## Task 3: Define ServerRealmMessages Packet

**Files:**
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/realm/server_realm_messages.ex`

**Packet Structure (opcode 0x0593):**

```elixir
defmodule BezgelorProtocol.Packets.Realm.ServerRealmMessages do
  @moduledoc """
  Server broadcast messages shown to player.

  Can contain multiple indexed messages.
  """

  @behaviour BezgelorProtocol.Packet.Writable

  defstruct messages: []

  defmodule Message do
    defstruct [:index, :message]
  end

  @impl true
  def opcode, do: :server_realm_messages

  @impl true
  def write(packet, writer) do
    writer = PacketWriter.write_uint32(writer, length(packet.messages))

    Enum.reduce(packet.messages, writer, fn msg, w ->
      w
      |> PacketWriter.write_uint32(msg.index)
      |> PacketWriter.write_wide_string(msg.message)
    end)
  end
end
```

---

## Task 4: Define ServerRealmInfo Packet

**Files:**
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/realm/server_realm_info.ex`

**Packet Structure (opcode 0x03DB):**

```elixir
defmodule BezgelorProtocol.Packets.Realm.ServerRealmInfo do
  @moduledoc """
  Realm server details for client connection.

  Contains World Server address and session credentials.
  """

  @behaviour BezgelorProtocol.Packet.Writable

  @realm_type_pve 0
  @realm_type_pvp 1

  defstruct [
    :address,      # uint32 - World server IP (network byte order)
    :port,         # uint16 - World server port
    :session_key,  # 16 bytes - Session key for world auth
    :account_id,   # uint32
    :realm_name,   # wide_string
    :flags,        # uint32 - RealmFlag bitfield
    :type,         # 2 bits - PVE(0) or PVP(1)
    :note_text_id  # 21 bits - Server message ID
  ]

  @impl true
  def opcode, do: :server_realm_info

  @impl true
  def write(packet, writer) do
    # Pack type (2 bits) and note_text_id (21 bits)
    type_and_note = (packet.type &&& 0x3) ||| ((packet.note_text_id &&& 0x1FFFFF) <<< 2)

    writer
    |> PacketWriter.write_uint32(packet.address)
    |> PacketWriter.write_uint16(packet.port)
    |> PacketWriter.write_bytes(packet.session_key)
    |> PacketWriter.write_uint32(packet.account_id)
    |> PacketWriter.write_wide_string(packet.realm_name)
    |> PacketWriter.write_uint32(packet.flags)
    |> PacketWriter.write_uint32(type_and_note)
  end

  def realm_type(:pve), do: @realm_type_pve
  def realm_type(:pvp), do: @realm_type_pvp
end
```

---

## Task 5: Create Realm Schema

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/schema/realm.ex`
- Create: `apps/bezgelor_db/priv/repo/migrations/TIMESTAMP_create_realms.exs`

**Schema:**

```elixir
defmodule BezgelorDb.Schema.Realm do
  use Ecto.Schema
  import Ecto.Changeset

  schema "realms" do
    field :name, :string
    field :address, :string       # IP address
    field :port, :integer         # World server port
    field :type, Ecto.Enum, values: [:pve, :pvp]
    field :flags, :integer, default: 0
    field :online, :boolean, default: false
    field :note_text_id, :integer, default: 0

    timestamps(type: :utc_datetime)
  end

  def changeset(realm, attrs) do
    realm
    |> cast(attrs, [:name, :address, :port, :type, :flags, :online, :note_text_id])
    |> validate_required([:name, :address, :port, :type])
    |> validate_number(:port, greater_than: 0, less_than: 65536)
    |> unique_constraint(:name)
  end
end
```

**Migration:**

```elixir
defmodule BezgelorDb.Repo.Migrations.CreateRealms do
  use Ecto.Migration

  def change do
    create table(:realms) do
      add :name, :string, null: false
      add :address, :string, null: false
      add :port, :integer, null: false
      add :type, :string, null: false, default: "pve"
      add :flags, :integer, default: 0
      add :online, :boolean, default: false
      add :note_text_id, :integer, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:realms, [:name])
  end
end
```

---

## Task 6: Create Realms Context Module

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/realms.ex`

```elixir
defmodule BezgelorDb.Realms do
  @moduledoc """
  Realm management context.
  """

  import Ecto.Query
  alias BezgelorDb.Repo
  alias BezgelorDb.Schema.Realm

  @doc "Get all realms."
  def list_realms do
    Repo.all(Realm)
  end

  @doc "Get only online realms."
  def list_online_realms do
    Realm
    |> where([r], r.online == true)
    |> Repo.all()
  end

  @doc "Get first online realm (for simple realm selection)."
  def get_first_online_realm do
    Realm
    |> where([r], r.online == true)
    |> first()
    |> Repo.one()
  end

  @doc "Get realm by ID."
  def get_realm(id), do: Repo.get(Realm, id)

  @doc "Get realm by name."
  def get_realm_by_name(name), do: Repo.get_by(Realm, name: name)

  @doc "Create a new realm."
  def create_realm(attrs) do
    %Realm{}
    |> Realm.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Update realm."
  def update_realm(%Realm{} = realm, attrs) do
    realm
    |> Realm.changeset(attrs)
    |> Repo.update()
  end

  @doc "Set realm online status."
  def set_online(%Realm{} = realm, online) do
    update_realm(realm, %{online: online})
  end

  @doc "Convert IP string to uint32 (network byte order)."
  def ip_to_uint32(ip_string) do
    ip_string
    |> String.split(".")
    |> Enum.map(&String.to_integer/1)
    |> :binary.list_to_bin()
    |> then(fn <<a, b, c, d>> ->
      <<n::big-unsigned-32>> = <<a, b, c, d>>
      n
    end)
  end
end
```

---

## Task 7: Add Realm Seeding

**Files:**
- Create: `apps/bezgelor_db/priv/repo/seeds/realms.exs`

```elixir
alias BezgelorDb.Realms

# Create default development realm
case Realms.get_realm_by_name("Bezgelor") do
  nil ->
    {:ok, _} = Realms.create_realm(%{
      name: "Bezgelor",
      address: "127.0.0.1",
      port: 24000,
      type: :pve,
      online: true
    })
    IO.puts("Created default realm: Bezgelor")

  _realm ->
    IO.puts("Default realm already exists")
end
```

---

## Task 8: Implement ClientHelloAuth Handler (Realm)

**Files:**
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/handler/realm_auth_handler.ex`
- Test: `apps/bezgelor_protocol/test/bezgelor_protocol/handler/realm_auth_handler_test.exs`

```elixir
defmodule BezgelorProtocol.Handler.RealmAuthHandler do
  @moduledoc """
  Handler for realm authentication (port 23115).

  Validates game tokens issued by STS server.
  """

  @behaviour BezgelorProtocol.Handler

  alias BezgelorProtocol.Packets.Realm.{
    ClientHelloAuth,
    ServerAuthAccepted,
    ServerAuthDenied,
    ServerRealmMessages,
    ServerRealmInfo
  }
  alias BezgelorProtocol.{PacketReader, PacketWriter}
  alias BezgelorCrypto.Random
  alias BezgelorDb.{Accounts, Realms}

  require Logger

  @expected_build 16042

  @impl true
  def handle(payload, state) do
    reader = PacketReader.new(payload)

    case ClientHelloAuth.read(reader) do
      {:ok, packet, _reader} ->
        state = put_in(state.session_data[:email], packet.email)
        process_auth(packet, state)

      {:error, reason} ->
        Logger.warning("Failed to parse ClientHelloAuth: #{inspect(reason)}")
        response = build_denial(:unknown)
        {:reply, :server_auth_denied_realm, encode_packet(response), state}
    end
  end

  defp process_auth(packet, state) do
    case validate_build(packet.build) do
      :ok ->
        authenticate(packet, state)

      {:error, reason} ->
        Logger.warning("Build version mismatch: expected #{@expected_build}, got #{packet.build}")
        response = build_denial(reason)
        {:reply, :server_auth_denied_realm, encode_packet(response), state}
    end
  end

  defp authenticate(packet, state) do
    game_token = Base.encode16(packet.game_token)

    with {:ok, account} <- lookup_account(packet.email, game_token),
         :ok <- check_suspension(account),
         {:ok, realm} <- get_realm(),
         {:ok, session_key} <- generate_session_key(account) do

      # Build responses
      accepted = %ServerAuthAccepted{}
      messages = %ServerRealmMessages{messages: []}
      realm_info = build_realm_info(account, realm, session_key)

      state = put_in(state.session_data[:account_id], account.id)

      # Send multiple responses
      responses = [
        {:server_auth_accepted_realm, encode_packet(accepted)},
        {:server_realm_messages, encode_packet(messages)},
        {:server_realm_info, encode_packet(realm_info)}
      ]

      {:reply_multi, responses, state}
    else
      {:error, reason} ->
        Logger.warning("Authentication failed: #{inspect(reason)}")
        {result, days} = denial_from_reason(reason)
        response = build_denial(result, days)
        {:reply, :server_auth_denied_realm, encode_packet(response), state}
    end
  end

  defp validate_build(@expected_build), do: :ok
  defp validate_build(_), do: {:error, :version_mismatch}

  defp lookup_account(email, game_token) do
    case Accounts.get_by_token(email, game_token) do
      nil -> {:error, :invalid_token}
      account -> {:ok, account}
    end
  end

  defp check_suspension(account) do
    Accounts.check_suspension(account)
  end

  defp get_realm do
    case Realms.get_first_online_realm() do
      nil -> {:error, :no_realms_available}
      realm -> {:ok, realm}
    end
  end

  defp generate_session_key(account) do
    session_key = Random.bytes(16)
    hex_key = Base.encode16(session_key)

    case Accounts.update_session_key(account, hex_key) do
      {:ok, _} -> {:ok, session_key}
      {:error, _} -> {:error, :database_error}
    end
  end

  defp build_realm_info(account, realm, session_key) do
    %ServerRealmInfo{
      address: Realms.ip_to_uint32(realm.address),
      port: realm.port,
      session_key: session_key,
      account_id: account.id,
      realm_name: realm.name,
      flags: realm.flags,
      type: ServerRealmInfo.realm_type(realm.type),
      note_text_id: realm.note_text_id
    }
  end

  defp build_denial(result, days \\ 0.0) do
    %ServerAuthDenied{
      result: result_code(result),
      error_value: 0,
      suspended_days: days
    }
  end

  defp denial_from_reason(:invalid_token), do: {:invalid_token, 0.0}
  defp denial_from_reason(:version_mismatch), do: {:version_mismatch, 0.0}
  defp denial_from_reason(:account_banned), do: {:account_banned, 0.0}
  defp denial_from_reason({:account_suspended, days}), do: {:account_suspended, days / 1.0}
  defp denial_from_reason(:no_realms_available), do: {:no_realms_available, 0.0}
  defp denial_from_reason(_), do: {:unknown, 0.0}

  defp result_code(:unknown), do: 0
  defp result_code(:success), do: 1
  defp result_code(:database_error), do: 2
  defp result_code(:invalid_token), do: 16
  defp result_code(:no_realms_available), do: 18
  defp result_code(:version_mismatch), do: 19
  defp result_code(:account_banned), do: 20
  defp result_code(:account_suspended), do: 21

  defp encode_packet(packet) do
    writer = PacketWriter.new()
    packet.__struct__.write(packet, writer)
    |> PacketWriter.to_binary()
  end
end
```

---

## Task 9: Add Game Token Validation

Game token validation is handled in Task 8 via `Accounts.get_by_token/2`. The token lookup requires both email AND token to match, preventing token theft.

**Additional work:**
- Ensure `get_by_token` in Accounts context properly validates

```elixir
# In BezgelorDb.Accounts
def get_by_token(email, game_token) when is_binary(email) and is_binary(game_token) do
  Repo.get_by(Account,
    email: String.downcase(email),
    game_token: game_token
  )
end
```

---

## Task 10: Generate and Store Session Keys

Session key generation is handled in Task 8. The key flow:

1. Generate 16 random bytes
2. Store hex-encoded in account.session_key
3. Send raw bytes to client in ServerRealmInfo
4. Client uses same key to authenticate with World Server

---

## Task 11: Create bezgelor_realm Application

**Files:**
- Create: `apps/bezgelor_realm/` (new umbrella app)

**Structure:**
```
apps/bezgelor_realm/
├── lib/
│   ├── bezgelor_realm.ex
│   └── bezgelor_realm/
│       └── application.ex
├── test/
│   ├── bezgelor_realm_test.exs
│   ├── integration/
│   │   └── realm_flow_test.exs
│   └── test_helper.exs
└── mix.exs
```

**mix.exs:**
```elixir
defmodule BezgelorRealm.MixProject do
  use Mix.Project

  def project do
    [
      app: :bezgelor_realm,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {BezgelorRealm.Application, []}
    ]
  end

  defp deps do
    [
      {:bezgelor_protocol, in_umbrella: true},
      {:bezgelor_db, in_umbrella: true}
    ]
  end
end
```

**application.ex:**
```elixir
defmodule BezgelorRealm.Application do
  @moduledoc """
  OTP Application for the Realm/Auth Server.

  Handles game token validation and realm selection on port 23115.
  """

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    children =
      if Application.get_env(:bezgelor_realm, :start_server, true) do
        port = Application.get_env(:bezgelor_realm, :port, 23115)
        Logger.info("Starting Realm Server on port #{port}")

        [
          BezgelorProtocol.PacketRegistry,
          {BezgelorProtocol.TcpListener,
           port: port,
           handler: BezgelorProtocol.Connection,
           handler_opts: [connection_type: :realm],
           name: :realm_listener}
        ]
      else
        Logger.info("Realm Server disabled (start_server: false)")
        []
      end

    opts = [strategy: :one_for_one, name: BezgelorRealm.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

---

## Task 12: Configure Port 23115 Listener

**Files:**
- Modify: `config/config.exs`

```elixir
config :bezgelor_realm,
  port: String.to_integer(System.get_env("REALM_PORT", "23115"))
```

---

## Task 13: Integration Test with Mock Client

**Files:**
- Create: `apps/bezgelor_realm/test/integration/realm_flow_test.exs`

```elixir
defmodule BezgelorRealm.Integration.RealmFlowTest do
  @moduledoc """
  Integration test for the realm authentication flow.

  Tests the complete client-server realm handshake:
  1. Connect to realm server
  2. Receive ServerHello
  3. Send ClientHelloAuth with game token
  4. Receive ServerAuthAccepted + ServerRealmInfo
  """

  use ExUnit.Case, async: false

  alias BezgelorDb.{Accounts, Realms, Repo}
  alias BezgelorProtocol.{Framing, Opcode, TcpListener}

  @moduletag :integration

  @test_port 46601

  setup_all do
    case BezgelorProtocol.PacketRegistry.start_link([]) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    case TcpListener.start_link(
           port: @test_port,
           handler: BezgelorProtocol.Connection,
           handler_opts: [connection_type: :realm],
           name: :test_realm_listener
         ) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    :timer.sleep(100)

    on_exit(fn ->
      TcpListener.stop(:test_realm_listener)
    end)

    :ok
  end

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    # Create test realm
    {:ok, realm} = Realms.create_realm(%{
      name: "TestRealm",
      address: "127.0.0.1",
      port: 24000,
      type: :pve,
      online: true
    })

    %{realm: realm}
  end

  describe "realm authentication flow" do
    test "successful connection receives ServerHello" do
      {:ok, socket} = :gen_tcp.connect(~c"localhost", @test_port, [:binary, active: false])

      {:ok, data} = :gen_tcp.recv(socket, 0, 5000)
      assert byte_size(data) > 6

      <<_size::little-32, opcode::little-16, _payload::binary>> = data
      assert {:ok, :server_hello} = Opcode.from_integer(opcode)

      :gen_tcp.close(socket)
    end

    test "auth with valid game token succeeds", %{realm: realm} do
      # Create account with game token
      email = "realm_test#{System.unique_integer([:positive])}@test.com"
      {:ok, account} = Accounts.create_account(email, "password123")
      game_token = BezgelorCrypto.Random.bytes(16) |> Base.encode16()
      {:ok, account} = Accounts.update_game_token(account, game_token)

      {:ok, socket} = :gen_tcp.connect(~c"localhost", @test_port, [:binary, active: false])

      # Receive ServerHello
      {:ok, _hello} = :gen_tcp.recv(socket, 0, 5000)

      # Send ClientHelloAuth with token
      auth_packet = build_client_hello_auth(16042, email, Base.decode16!(game_token))
      framed = Framing.frame_packet(Opcode.to_integer(:client_hello_auth_realm), auth_packet)
      :ok = :gen_tcp.send(socket, framed)

      # Should receive ServerAuthAccepted
      {:ok, response_data} = :gen_tcp.recv(socket, 0, 5000)
      <<_size::little-32, opcode::little-16, _payload::binary>> = response_data
      assert {:ok, :server_auth_accepted_realm} = Opcode.from_integer(opcode)

      :gen_tcp.close(socket)
    end

    test "auth with invalid token returns denial" do
      {:ok, socket} = :gen_tcp.connect(~c"localhost", @test_port, [:binary, active: false])

      {:ok, _hello} = :gen_tcp.recv(socket, 0, 5000)

      # Send with invalid token
      auth_packet = build_client_hello_auth(16042, "invalid@test.com", :crypto.strong_rand_bytes(16))
      framed = Framing.frame_packet(Opcode.to_integer(:client_hello_auth_realm), auth_packet)
      :ok = :gen_tcp.send(socket, framed)

      {:ok, response_data} = :gen_tcp.recv(socket, 0, 5000)
      <<_size::little-32, opcode::little-16, payload::binary>> = response_data

      assert {:ok, :server_auth_denied_realm} = Opcode.from_integer(opcode)

      <<result_code::little-32, _rest::binary>> = payload
      assert result_code == 16  # invalid_token

      :gen_tcp.close(socket)
    end
  end

  defp build_client_hello_auth(build, email, game_token) do
    utf16_email = :unicode.characters_to_binary(email, :utf8, {:utf16, :little})
    email_length = String.length(email)
    uuid_1 = :crypto.strong_rand_bytes(16)

    <<
      build::little-32,
      0x1588::little-64,
      email_length::little-32,
      utf16_email::binary,
      uuid_1::binary-size(16),
      game_token::binary-size(16),
      0::little-32,  # inet_address
      0::little-32,  # language
      0::little-32,  # game_mode
      0::little-32   # unused
      # Hardware info would follow but simplified for test
    >>
  end
end
```

---

## Success Criteria

Phase 4 is complete when:

1. ✅ ClientHelloAuth (realm) packet can be parsed
2. ✅ ServerAuthAccepted/Denied (realm) packets can be sent
3. ✅ ServerRealmMessages packet can be sent
4. ✅ ServerRealmInfo packet can be sent
5. ✅ Realm schema and migrations exist
6. ✅ Realms context provides CRUD operations
7. ✅ Game token validation works
8. ✅ Session keys are generated and stored
9. ✅ Realm server listens on port 23115
10. ✅ Integration test passes end-to-end
11. ✅ All tests pass

---

## Dependencies

**From Previous Phases:**
- `bezgelor_crypto.Random` - Session key generation
- `bezgelor_db.Accounts` - Token lookup, session storage
- `bezgelor_protocol.Connection` - TCP connection handling
- `bezgelor_protocol.PacketReader/Writer` - Binary parsing

**New Dependencies:**
- None (all deps already in umbrella)

---

## Next Phase Preview

**Phase 5: Character Management** will:
- Add character creation flow
- Implement character selection screen
- Handle character deletion
- Add Phoenix API for launcher

**Phase 6: World Entry** will:
- Listen on port 24000 (World Server)
- Validate session keys from Realm Server
- Handle world entry packets
- Spawn player in zone
