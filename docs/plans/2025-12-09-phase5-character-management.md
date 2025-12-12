# Phase 5: Character Management - Implementation Plan

**Status:** ✅ Complete

**Goal:** Implement character creation, selection, and deletion so players can manage their characters.

**Outcome:** After realm authentication, clients can see their character list, create new characters, select a character, and delete characters.

---

## Overview

After authenticating with the Realm Server (Phase 4), clients need to:
1. Receive their character list
2. Create new characters (race, class, appearance)
3. Select a character to enter the world
4. Delete unwanted characters

This phase focuses on the database and protocol layers. World entry (actually spawning in-game) is Phase 6.

### Character Flow

```
Client authenticated with Realm Server
        │
        │ Receives: ServerRealmInfo (world server address)
        │
        ▼
Client connects to World Server (port 24000)
        │
        ▼
┌───────────────────────────────────────┐
│ Client sends: ClientHelloRealm        │
│   - Account ID                        │
│   - Session key (from realm)          │
│   - Email                             │
└───────────────────────────────────────┘
        │
        ▼
┌───────────────────────────────────────┐
│ Server validates session key          │
│ Server sends: ServerCharacterList     │
│   - List of characters for account    │
└───────────────────────────────────────┘
        │
        ├─────────────────────────────────────┐
        │                                     │
        ▼                                     ▼
┌─────────────────────┐           ┌─────────────────────┐
│ Create Character    │           │ Select Character    │
│ ClientCharCreate    │           │ ClientCharSelect    │
│ ServerCharCreate    │           │ ServerCharSelect    │
└─────────────────────┘           └─────────────────────┘
```

### Key Packets

| Opcode | Name | Direction | Description |
|--------|------|-----------|-------------|
| 0x0008 | ClientHelloRealm | C→S | World server auth with session key |
| 0x0117 | ServerCharacterList | S→C | List of account's characters |
| 0x0118 | ClientCharacterSelect | C→S | Select character to play |
| 0x011A | ClientCharacterCreate | C→S | Create new character |
| 0x011B | ServerCharacterCreate | S→C | Character creation result |
| 0x011C | ClientCharacterDelete | C→S | Delete character request |

---

## Tasks

### Batch 1: Character Schema Enhancement (Tasks 1-3)

| Task | Description | Status |
|------|-------------|--------|
| 1 | Enhance Character schema with full attributes | ✅ Done |
| 2 | Add character appearance schema | ✅ Done |
| 3 | Create Characters context module | ✅ Done |

### Batch 2: World Server Packets (Tasks 4-7)

| Task | Description | Status |
|------|-------------|--------|
| 4 | Define ClientHelloRealm packet | ✅ Done |
| 5 | Define ServerCharacterList packet | ✅ Done |
| 6 | Define ClientCharacterSelect packet | ✅ Done |
| 7 | Define character create/delete packets | ✅ Done |

### Batch 3: World Auth Handler (Tasks 8-10)

| Task | Description | Status |
|------|-------------|--------|
| 8 | Implement ClientHelloRealm handler | ✅ Done |
| 9 | Implement character list handler | ✅ Done |
| 10 | Implement character CRUD handlers | ✅ Done |

### Batch 4: World Server Application (Tasks 11-13)

| Task | Description | Status |
|------|-------------|--------|
| 11 | Create bezgelor_world application | ✅ Done |
| 12 | Configure port 24000 listener | ✅ Done |
| 13 | Integration tests for character flow | ✅ Done |

---

## Task 1: Enhance Character Schema

**Files:**
- Modify: `apps/bezgelor_db/lib/bezgelor_db/schema/character.ex`
- Create migration for new fields

The existing Character schema is minimal. We need to add:

```elixir
defmodule BezgelorDb.Schema.Character do
  use Ecto.Schema
  import Ecto.Changeset

  schema "characters" do
    belongs_to :account, BezgelorDb.Schema.Account

    # Identity
    field :name, :string
    field :sex, Ecto.Enum, values: [:male, :female]
    field :race, Ecto.Enum, values: [:human, :granok, :aurin, :mordesh, :mechari, :draken, :chua, :cassian]
    field :class, Ecto.Enum, values: [:warrior, :engineer, :esper, :medic, :stalker, :spellslinger]
    field :path, Ecto.Enum, values: [:soldier, :settler, :scientist, :explorer]
    field :faction, Ecto.Enum, values: [:exile, :dominion]

    # Progression
    field :level, :integer, default: 1
    field :experience, :integer, default: 0
    field :title_id, :integer, default: 0

    # Location
    field :world_id, :integer, default: 0
    field :zone_id, :integer, default: 0
    field :position_x, :float, default: 0.0
    field :position_y, :float, default: 0.0
    field :position_z, :float, default: 0.0
    field :rotation_x, :float, default: 0.0
    field :rotation_y, :float, default: 0.0
    field :rotation_z, :float, default: 0.0

    # Status
    field :online, :boolean, default: false
    field :deleted_at, :utc_datetime
    field :last_login_at, :utc_datetime

    # Appearance is a separate table
    has_one :appearance, BezgelorDb.Schema.CharacterAppearance

    timestamps(type: :utc_datetime)
  end
end
```

---

## Task 2: Character Appearance Schema

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/schema/character_appearance.ex`
- Create migration

WildStar has extensive character customization:

```elixir
defmodule BezgelorDb.Schema.CharacterAppearance do
  use Ecto.Schema
  import Ecto.Changeset

  schema "character_appearances" do
    belongs_to :character, BezgelorDb.Schema.Character

    # Body
    field :body_type, :integer, default: 0
    field :body_height, :integer, default: 0
    field :body_weight, :integer, default: 0

    # Face
    field :face_type, :integer, default: 0
    field :eye_type, :integer, default: 0
    field :eye_color, :integer, default: 0
    field :nose_type, :integer, default: 0
    field :mouth_type, :integer, default: 0
    field :ear_type, :integer, default: 0

    # Hair
    field :hair_style, :integer, default: 0
    field :hair_color, :integer, default: 0
    field :facial_hair, :integer, default: 0

    # Skin
    field :skin_color, :integer, default: 0

    # Race-specific features
    field :feature_1, :integer, default: 0
    field :feature_2, :integer, default: 0
    field :feature_3, :integer, default: 0
    field :feature_4, :integer, default: 0

    # Bone customization (sliders)
    field :bones, {:array, :float}, default: []

    timestamps(type: :utc_datetime)
  end
end
```

---

## Task 3: Characters Context Module

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/characters.ex`

```elixir
defmodule BezgelorDb.Characters do
  @moduledoc """
  Character management context.
  """

  import Ecto.Query
  alias BezgelorDb.Repo
  alias BezgelorDb.Schema.{Character, CharacterAppearance}

  @doc "List all characters for an account."
  def list_characters(account_id) do
    Character
    |> where([c], c.account_id == ^account_id)
    |> where([c], is_nil(c.deleted_at))
    |> preload(:appearance)
    |> order_by([c], desc: c.last_login_at)
    |> Repo.all()
  end

  @doc "Get a character by ID, ensuring it belongs to the account."
  def get_character(account_id, character_id) do
    Character
    |> where([c], c.id == ^character_id and c.account_id == ^account_id)
    |> where([c], is_nil(c.deleted_at))
    |> preload(:appearance)
    |> Repo.one()
  end

  @doc "Create a new character."
  def create_character(account_id, attrs, appearance_attrs) do
    Repo.transaction(fn ->
      with {:ok, character} <- insert_character(account_id, attrs),
           {:ok, _appearance} <- insert_appearance(character.id, appearance_attrs) do
        Repo.preload(character, :appearance)
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  @doc "Soft delete a character (can be restored)."
  def delete_character(account_id, character_id) do
    case get_character(account_id, character_id) do
      nil -> {:error, :not_found}
      character ->
        character
        |> Character.delete_changeset()
        |> Repo.update()
    end
  end

  @doc "Count characters for an account."
  def count_characters(account_id) do
    Character
    |> where([c], c.account_id == ^account_id)
    |> where([c], is_nil(c.deleted_at))
    |> Repo.aggregate(:count)
  end

  @doc "Check if character name is available."
  def name_available?(name) do
    Character
    |> where([c], fragment("lower(?)", c.name) == ^String.downcase(name))
    |> where([c], is_nil(c.deleted_at))
    |> Repo.exists?()
    |> Kernel.not()
  end
end
```

---

## Task 4: Define ClientHelloRealm Packet

**Files:**
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/client_hello_realm.ex`

```elixir
defmodule BezgelorProtocol.Packets.World.ClientHelloRealm do
  @moduledoc """
  Client authentication for world server.

  Sent when connecting to the world server after realm selection.
  Contains session key from realm server for validation.
  """

  @behaviour BezgelorProtocol.Packet.Readable

  defstruct [
    :account_id,    # uint32
    :session_key,   # 16 bytes
    :email          # wide_string
  ]

  @impl true
  def opcode, do: :client_hello_realm

  @impl true
  def read(reader) do
    with {:ok, account_id, reader} <- PacketReader.read_uint32(reader),
         {:ok, session_key, reader} <- PacketReader.read_bytes(reader, 16),
         {:ok, email, reader} <- PacketReader.read_wide_string(reader) do
      {:ok, %__MODULE__{
        account_id: account_id,
        session_key: session_key,
        email: email
      }, reader}
    end
  end
end
```

---

## Task 5: Define ServerCharacterList Packet

**Files:**
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_character_list.ex`

```elixir
defmodule BezgelorProtocol.Packets.World.ServerCharacterList do
  @moduledoc """
  List of characters for the account.

  Sent after successful world server authentication.
  """

  @behaviour BezgelorProtocol.Packet.Writable

  defstruct characters: [], max_characters: 12

  defmodule CharacterEntry do
    defstruct [
      :id,
      :name,
      :sex,
      :race,
      :class,
      :path,
      :faction,
      :level,
      :world_id,
      :zone_id,
      :last_login,
      :appearance
    ]
  end

  @impl true
  def opcode, do: :server_character_list

  @impl true
  def write(packet, writer) do
    # Write max character slots
    writer = PacketWriter.write_uint32(writer, packet.max_characters)

    # Write character count
    writer = PacketWriter.write_uint32(writer, length(packet.characters))

    # Write each character
    Enum.reduce(packet.characters, writer, fn char, w ->
      write_character(w, char)
    end)
  end

  defp write_character(writer, char) do
    writer
    |> PacketWriter.write_uint64(char.id)
    |> PacketWriter.write_wide_string(char.name)
    |> PacketWriter.write_uint32(sex_to_int(char.sex))
    |> PacketWriter.write_uint32(race_to_int(char.race))
    |> PacketWriter.write_uint32(class_to_int(char.class))
    |> PacketWriter.write_uint32(path_to_int(char.path))
    |> PacketWriter.write_uint32(faction_to_int(char.faction))
    |> PacketWriter.write_uint32(char.level)
    |> PacketWriter.write_uint32(char.world_id)
    |> PacketWriter.write_uint32(char.zone_id)
    |> PacketWriter.write_uint64(char.last_login || 0)
    |> write_appearance(char.appearance)
  end
end
```

---

## Task 6: Define ClientCharacterSelect Packet

**Files:**
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/client_character_select.ex`

```elixir
defmodule BezgelorProtocol.Packets.World.ClientCharacterSelect do
  @moduledoc """
  Character selection request.

  Client selects which character to play.
  """

  @behaviour BezgelorProtocol.Packet.Readable

  defstruct [:character_id]

  @impl true
  def opcode, do: :client_character_select

  @impl true
  def read(reader) do
    with {:ok, character_id, reader} <- PacketReader.read_uint64(reader) do
      {:ok, %__MODULE__{character_id: character_id}, reader}
    end
  end
end
```

---

## Task 7: Define Character Create/Delete Packets

**Files:**
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/client_character_create.ex`
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_character_create.ex`
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/client_character_delete.ex`

```elixir
defmodule BezgelorProtocol.Packets.World.ClientCharacterCreate do
  defstruct [
    :name,
    :sex,
    :race,
    :class,
    :path,
    :appearance
  ]

  @impl true
  def read(reader) do
    # Parse all character creation fields
  end
end

defmodule BezgelorProtocol.Packets.World.ServerCharacterCreate do
  defstruct [
    :result,        # :success, :name_taken, :invalid_name, :max_characters, etc.
    :character_id   # Only set on success
  ]

  @impl true
  def write(packet, writer) do
    # Serialize result and character ID
  end
end

defmodule BezgelorProtocol.Packets.World.ClientCharacterDelete do
  defstruct [:character_id]
end
```

---

## Task 8: Implement ClientHelloRealm Handler

**Files:**
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/handler/world_auth_handler.ex`

```elixir
defmodule BezgelorProtocol.Handler.WorldAuthHandler do
  @moduledoc """
  Handler for world server authentication.

  Validates session key from realm server and sends character list.
  """

  @behaviour BezgelorProtocol.Handler

  def handle(payload, state) do
    with {:ok, packet, _} <- parse_packet(payload),
         {:ok, account} <- validate_session(packet),
         characters <- load_characters(account.id) do

      # Store account in session
      state = put_in(state.session_data[:account_id], account.id)

      # Build character list response
      response = build_character_list(characters)

      {:reply, :server_character_list, encode_packet(response), state}
    else
      {:error, reason} ->
        # Send denial and disconnect
        {:error, reason}
    end
  end

  defp validate_session(packet) do
    session_key_hex = Base.encode16(packet.session_key)

    case Accounts.get_by_session_key(packet.email, session_key_hex) do
      nil -> {:error, :invalid_session}
      account -> {:ok, account}
    end
  end
end
```

---

## Task 9: Implement Character List Handler

Building character list from database is handled in Task 8's handler.

---

## Task 10: Implement Character CRUD Handlers

**Files:**
- Create handlers for create, select, and delete

```elixir
defmodule BezgelorProtocol.Handler.CharacterCreateHandler do
  def handle(payload, state) do
    with {:ok, packet, _} <- parse_packet(payload),
         :ok <- validate_name(packet.name),
         :ok <- validate_faction_race(packet),
         {:ok, character} <- create_character(state, packet) do

      response = %ServerCharacterCreate{
        result: :success,
        character_id: character.id
      }

      {:reply, :server_character_create, encode_packet(response), state}
    else
      {:error, reason} ->
        response = %ServerCharacterCreate{result: reason, character_id: 0}
        {:reply, :server_character_create, encode_packet(response), state}
    end
  end
end
```

---

## Task 11: Create bezgelor_world Application

**Files:**
- Create: `apps/bezgelor_world/` (new umbrella app)

```elixir
defmodule BezgelorWorld.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children =
      if Application.get_env(:bezgelor_world, :start_server, true) do
        port = Application.get_env(:bezgelor_world, :port, 24000)

        [
          BezgelorProtocol.PacketRegistry,
          {BezgelorProtocol.TcpListener,
           port: port,
           handler: BezgelorProtocol.Connection,
           handler_opts: [connection_type: :world],
           name: :world_listener}
        ]
      else
        []
      end

    Supervisor.start_link(children, strategy: :one_for_one, name: BezgelorWorld.Supervisor)
  end
end
```

---

## Task 12: Configure Port 24000 Listener

**Files:**
- Modify: `config/config.exs`
- Modify: `config/test.exs`

```elixir
# config.exs
config :bezgelor_world,
  port: String.to_integer(System.get_env("WORLD_PORT", "24000"))

# test.exs
config :bezgelor_world, start_server: false
```

---

## Task 13: Integration Tests

**Files:**
- Create: `apps/bezgelor_world/test/integration/character_flow_test.exs`

```elixir
defmodule BezgelorWorld.Integration.CharacterFlowTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  describe "world authentication flow" do
    test "valid session key receives character list" do
      # Create account, set session key
      # Connect to world server
      # Send ClientHelloRealm
      # Receive ServerCharacterList
    end

    test "can create a character" do
      # Authenticate
      # Send ClientCharacterCreate
      # Receive ServerCharacterCreate with success
      # Verify character appears in list
    end

    test "can delete a character" do
      # Create character
      # Send ClientCharacterDelete
      # Verify character no longer in list
    end
  end
end
```

---

## Success Criteria

| # | Criterion | Status |
|---|-----------|--------|
| 1 | Character schema has all WildStar attributes | ✅ Done |
| 2 | Character appearance schema exists | ✅ Done |
| 3 | Characters context provides CRUD operations | ✅ Done |
| 4 | ClientHelloRealm validates session keys | ✅ Done |
| 5 | ServerCharacterList returns account's characters | ✅ Done |
| 6 | Character creation works with validation | ✅ Done |
| 7 | Character deletion (soft delete) works | ✅ Done |
| 8 | World server listens on port 24000 | ✅ Done |
| 9 | Integration tests pass | ✅ Done |
| 10 | All tests pass | ✅ Done |

---

## Dependencies

**From Previous Phases:**
- `bezgelor_db.Accounts` - Session key validation
- `bezgelor_protocol.Connection` - TCP handling
- `bezgelor_protocol.PacketReader/Writer` - Binary parsing

**New Dependencies:**
- None

---

## Data Constraints

**WildStar Race/Faction Mapping:**

| Race | Faction |
|------|---------|
| Human | Exile |
| Granok | Exile |
| Aurin | Exile |
| Mordesh | Exile |
| Cassian | Dominion |
| Draken | Dominion |
| Mechari | Dominion |
| Chua | Dominion |

**Character Limits:**
- Max 12 characters per account (adjustable)
- Name: 3-20 characters, alphanumeric + spaces

---

## Next Phase Preview

**Phase 6: World Entry** will:
- Load static game data (zones, maps)
- Spawn player in world at saved position
- Handle basic movement packets
- Implement zone/map system

---

## Implementation Notes

**Files Implemented:**
- `apps/bezgelor_db/lib/bezgelor_db/schema/character.ex` - Character schema with full attributes
- `apps/bezgelor_db/lib/bezgelor_db/schema/character_appearance.ex` - Appearance customization
- `apps/bezgelor_db/lib/bezgelor_db/characters.ex` - Characters context module
- `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/client_hello_realm.ex` - World auth packet
- `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_character_list.ex` - Character list response
- `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/client_character_select.ex` - Character selection
- `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/client_character_create.ex` - Character creation request
- `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_character_create.ex` - Character creation response
- `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/client_character_delete.ex` - Character deletion
- `apps/bezgelor_protocol/lib/bezgelor_protocol/handler/world_auth_handler.ex` - World authentication handler
- `apps/bezgelor_protocol/lib/bezgelor_protocol/handler/character_create_handler.ex` - Character creation handler
- `apps/bezgelor_protocol/lib/bezgelor_protocol/handler/character_select_handler.ex` - Character selection handler
- `apps/bezgelor_protocol/lib/bezgelor_protocol/handler/character_delete_handler.ex` - Character deletion handler
- `apps/bezgelor_world/lib/bezgelor_world/application.ex` - World server application
- `apps/bezgelor_world/test/integration/character_flow_test.exs` - Integration tests

**Design Notes:**
- Character CRUD handlers implemented as separate modules (CharacterCreateHandler, CharacterSelectHandler, CharacterDeleteHandler) rather than combined into a single handler as originally sketched in Task 10
- Port 24000 configuration in `config/config.exs`
