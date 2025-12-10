# Phase 6: World Entry - Implementation Plan

**Goal:** Implement world entry so players can spawn in-game after selecting a character.

**Outcome:** After character selection, clients enter the game world at their saved position with basic world state.

---

## Overview

After selecting a character (Phase 5), players need to:
1. Receive world initialization data
2. Spawn at their saved position (or default spawn)
3. See basic world state
4. Be able to move around

This phase focuses on the minimum viable world entry. Advanced features like NPCs, combat, and chat are future phases.

### World Entry Flow

```
Character selected (Phase 5)
        │
        ▼
┌───────────────────────────────────────┐
│ Server sends: ServerWorldEnter        │
│   - Character data                    │
│   - World/Zone info                   │
│   - Initial position                  │
└───────────────────────────────────────┘
        │
        ▼
┌───────────────────────────────────────┐
│ Client loads world assets             │
│ Client sends: ClientEnteredWorld      │
│   - Acknowledgment                    │
└───────────────────────────────────────┘
        │
        ▼
┌───────────────────────────────────────┐
│ Server spawns player entity           │
│ Server sends: ServerEntityCreate      │
│   - Player entity with position       │
└───────────────────────────────────────┘
        │
        ▼
┌───────────────────────────────────────┐
│ Player is in-world                    │
│ Can send movement packets             │
│ ClientMovement → ServerMovement       │
└───────────────────────────────────────┘
```

### Key Packets

| Opcode | Name | Direction | Description |
|--------|------|-----------|-------------|
| 0x00F2 | ClientEnteredWorld | C→S | Client finished loading |
| 0x00F3 | ServerWorldEnter | S→C | World entry initialization |
| 0x0100 | ServerEntityCreate | S→C | Spawn entity (player/npc) |
| 0x0101 | ServerEntityDestroy | S→C | Remove entity |
| 0x07F4 | ClientMovement | C→S | Player position update |
| 0x07F5 | ServerMovement | S→C | Entity position update |

---

## Tasks

### Batch 1: World Data Structures (Tasks 1-3)

| Task | Description |
|------|-------------|
| 1 | Create Entity struct for in-world objects |
| 2 | Create WorldSession GenServer for player state |
| 3 | Create basic Zone/World data structures |

### Batch 2: World Entry Packets (Tasks 4-6)

| Task | Description |
|------|-------------|
| 4 | Define ServerWorldEnter packet |
| 5 | Define ServerEntityCreate packet |
| 6 | Define movement packets |

### Batch 3: World Entry Handlers (Tasks 7-9)

| Task | Description |
|------|-------------|
| 7 | Implement character select → world entry flow |
| 8 | Implement ClientEnteredWorld handler |
| 9 | Implement movement handler |

### Batch 4: Integration (Tasks 10-12)

| Task | Description |
|------|-------------|
| 10 | Create WorldManager supervisor |
| 11 | Integration tests for world entry |
| 12 | Verify full test suite passes |

---

## Task 1: Entity Struct

**Files:**
- Create: `apps/bezgelor_world/lib/bezgelor_world/entity.ex`

Entities are anything that exists in the game world (players, NPCs, objects).

```elixir
defmodule BezgelorWorld.Entity do
  @moduledoc """
  In-world entity representation.

  Entities have:
  - Unique ID (guid)
  - Type (player, creature, object, etc.)
  - Position and rotation
  - Display info
  """

  defstruct [
    :guid,
    :type,
    :display_info,
    :name,
    :faction,
    :level,
    # Position
    :world_id,
    :zone_id,
    :position,    # {x, y, z}
    :rotation,    # {x, y, z}
    # For players
    :account_id,
    :character_id,
    # State
    :health,
    :max_health,
    :flags
  ]

  @type entity_type :: :player | :creature | :object | :vehicle

  @type t :: %__MODULE__{
    guid: non_neg_integer(),
    type: entity_type(),
    ...
  }

  @doc "Create a player entity from character data."
  def from_character(character, guid) do
    %__MODULE__{
      guid: guid,
      type: :player,
      name: character.name,
      level: character.level,
      faction: character.faction_id,
      world_id: character.world_id,
      zone_id: character.world_zone_id,
      position: {character.location_x, character.location_y, character.location_z},
      rotation: {character.rotation_x, character.rotation_y, character.rotation_z},
      account_id: character.account_id,
      character_id: character.id
    }
  end
end
```

---

## Task 2: WorldSession GenServer

**Files:**
- Create: `apps/bezgelor_world/lib/bezgelor_world/world_session.ex`

Each connected player has a WorldSession tracking their state.

```elixir
defmodule BezgelorWorld.WorldSession do
  @moduledoc """
  Per-player world session state.

  Manages:
  - Player entity
  - Connection state
  - Position updates
  - Visibility (what entities player can see)
  """

  use GenServer

  defstruct [
    :account_id,
    :character_id,
    :entity,
    :connection_pid,
    :state  # :loading, :in_world, :disconnecting
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(opts) do
    state = %__MODULE__{
      account_id: opts[:account_id],
      character_id: opts[:character_id],
      connection_pid: opts[:connection_pid],
      state: :loading
    }
    {:ok, state}
  end

  # Called when client sends ClientEnteredWorld
  def handle_cast(:entered_world, state) do
    # Spawn player entity
    # Notify nearby players
    {:noreply, %{state | state: :in_world}}
  end

  # Handle movement
  def handle_cast({:movement, position, rotation}, state) do
    # Update entity position
    # Broadcast to nearby players
    {:noreply, state}
  end
end
```

---

## Task 3: Zone/World Data Structures

**Files:**
- Create: `apps/bezgelor_world/lib/bezgelor_world/zone.ex`

Basic zone information for spawn locations.

```elixir
defmodule BezgelorWorld.Zone do
  @moduledoc """
  Zone data and spawn points.

  For Phase 6, we use hardcoded default zones.
  Static game data loading is a future enhancement.
  """

  # Default starting zones by faction
  @exile_start %{
    world_id: 870,      # Everstar Grove
    zone_id: 1,
    position: {-3200.0, -800.0, -580.0},
    rotation: {0.0, 0.0, 0.0}
  }

  @dominion_start %{
    world_id: 870,      # Levian Bay
    zone_id: 2,
    position: {-3200.0, -800.0, -580.0},
    rotation: {0.0, 0.0, 0.0}
  }

  @doc "Get default spawn location for faction."
  def default_spawn(faction_id) when faction_id == 166, do: @exile_start
  def default_spawn(faction_id) when faction_id == 167, do: @dominion_start
  def default_spawn(_), do: @exile_start

  @doc "Get spawn for character (saved position or default)."
  def spawn_location(character) do
    if valid_position?(character) do
      %{
        world_id: character.world_id,
        zone_id: character.world_zone_id,
        position: {character.location_x, character.location_y, character.location_z},
        rotation: {character.rotation_x, character.rotation_y, character.rotation_z}
      }
    else
      default_spawn(character.faction_id)
    end
  end

  defp valid_position?(char) do
    char.world_id != nil and char.world_id > 0
  end
end
```

---

## Task 4: ServerWorldEnter Packet

**Files:**
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_world_enter.ex`

```elixir
defmodule BezgelorProtocol.Packets.World.ServerWorldEnter do
  @moduledoc """
  World entry initialization packet.

  Sent when player enters the world after character selection.
  Contains character data and initial position.
  """

  @behaviour BezgelorProtocol.Packet.Writable

  defstruct [
    :character_id,
    :world_id,
    :zone_id,
    :position_x,
    :position_y,
    :position_z,
    :rotation_x,
    :rotation_y,
    :rotation_z,
    :time_of_day,
    :weather
  ]

  @impl true
  def opcode, do: :server_world_enter

  @impl true
  def write(packet, writer) do
    writer
    |> PacketWriter.write_uint64(packet.character_id)
    |> PacketWriter.write_uint32(packet.world_id)
    |> PacketWriter.write_uint32(packet.zone_id)
    |> PacketWriter.write_float32(packet.position_x)
    |> PacketWriter.write_float32(packet.position_y)
    |> PacketWriter.write_float32(packet.position_z)
    |> PacketWriter.write_float32(packet.rotation_x)
    |> PacketWriter.write_float32(packet.rotation_y)
    |> PacketWriter.write_float32(packet.rotation_z)
    |> PacketWriter.write_uint32(packet.time_of_day || 0)
    |> PacketWriter.write_uint32(packet.weather || 0)
    |> then(&{:ok, &1})
  end
end
```

---

## Task 5: ServerEntityCreate Packet

**Files:**
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_entity_create.ex`

```elixir
defmodule BezgelorProtocol.Packets.World.ServerEntityCreate do
  @moduledoc """
  Entity spawn packet.

  Sent to spawn players, NPCs, objects in the world.
  """

  @behaviour BezgelorProtocol.Packet.Writable

  @entity_type_player 1
  @entity_type_creature 2
  @entity_type_object 3

  defstruct [
    :guid,
    :entity_type,
    :name,
    :level,
    :faction,
    :display_info,
    :position_x,
    :position_y,
    :position_z,
    :rotation_x,
    :rotation_y,
    :rotation_z,
    :health,
    :max_health
  ]

  @impl true
  def opcode, do: :server_entity_create

  @impl true
  def write(packet, writer) do
    entity_type = entity_type_to_int(packet.entity_type)

    writer
    |> PacketWriter.write_uint64(packet.guid)
    |> PacketWriter.write_uint32(entity_type)
    |> PacketWriter.write_wide_string(packet.name || "")
    |> PacketWriter.write_uint32(packet.level || 1)
    |> PacketWriter.write_uint32(packet.faction || 0)
    |> PacketWriter.write_uint32(packet.display_info || 0)
    |> PacketWriter.write_float32(packet.position_x)
    |> PacketWriter.write_float32(packet.position_y)
    |> PacketWriter.write_float32(packet.position_z)
    |> PacketWriter.write_float32(packet.rotation_x || 0.0)
    |> PacketWriter.write_float32(packet.rotation_y || 0.0)
    |> PacketWriter.write_float32(packet.rotation_z || 0.0)
    |> PacketWriter.write_uint32(packet.health || 100)
    |> PacketWriter.write_uint32(packet.max_health || 100)
    |> then(&{:ok, &1})
  end

  defp entity_type_to_int(:player), do: @entity_type_player
  defp entity_type_to_int(:creature), do: @entity_type_creature
  defp entity_type_to_int(:object), do: @entity_type_object
  defp entity_type_to_int(_), do: @entity_type_object
end
```

---

## Task 6: Movement Packets

**Files:**
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/client_movement.ex`
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_movement.ex`

```elixir
defmodule BezgelorProtocol.Packets.World.ClientMovement do
  @moduledoc """
  Client position/movement update.
  """

  @behaviour BezgelorProtocol.Packet.Readable

  defstruct [
    :position_x,
    :position_y,
    :position_z,
    :rotation_x,
    :rotation_y,
    :rotation_z,
    :velocity_x,
    :velocity_y,
    :velocity_z,
    :movement_flags,
    :timestamp
  ]

  @impl true
  def opcode, do: :client_movement

  @impl true
  def read(reader) do
    with {:ok, pos_x, reader} <- PacketReader.read_float32(reader),
         {:ok, pos_y, reader} <- PacketReader.read_float32(reader),
         {:ok, pos_z, reader} <- PacketReader.read_float32(reader),
         {:ok, rot_x, reader} <- PacketReader.read_float32(reader),
         {:ok, rot_y, reader} <- PacketReader.read_float32(reader),
         {:ok, rot_z, reader} <- PacketReader.read_float32(reader),
         {:ok, vel_x, reader} <- PacketReader.read_float32(reader),
         {:ok, vel_y, reader} <- PacketReader.read_float32(reader),
         {:ok, vel_z, reader} <- PacketReader.read_float32(reader),
         {:ok, flags, reader} <- PacketReader.read_uint32(reader),
         {:ok, timestamp, reader} <- PacketReader.read_uint32(reader) do
      {:ok, %__MODULE__{
        position_x: pos_x,
        position_y: pos_y,
        position_z: pos_z,
        rotation_x: rot_x,
        rotation_y: rot_y,
        rotation_z: rot_z,
        velocity_x: vel_x,
        velocity_y: vel_y,
        velocity_z: vel_z,
        movement_flags: flags,
        timestamp: timestamp
      }, reader}
    end
  end
end

defmodule BezgelorProtocol.Packets.World.ServerMovement do
  @moduledoc """
  Server broadcasts entity movement to nearby players.
  """

  @behaviour BezgelorProtocol.Packet.Writable

  defstruct [
    :guid,
    :position_x,
    :position_y,
    :position_z,
    :rotation_x,
    :rotation_y,
    :rotation_z,
    :velocity_x,
    :velocity_y,
    :velocity_z,
    :movement_flags,
    :timestamp
  ]

  @impl true
  def opcode, do: :server_movement

  @impl true
  def write(packet, writer) do
    writer
    |> PacketWriter.write_uint64(packet.guid)
    |> PacketWriter.write_float32(packet.position_x)
    |> PacketWriter.write_float32(packet.position_y)
    |> PacketWriter.write_float32(packet.position_z)
    |> PacketWriter.write_float32(packet.rotation_x || 0.0)
    |> PacketWriter.write_float32(packet.rotation_y || 0.0)
    |> PacketWriter.write_float32(packet.rotation_z || 0.0)
    |> PacketWriter.write_float32(packet.velocity_x || 0.0)
    |> PacketWriter.write_float32(packet.velocity_y || 0.0)
    |> PacketWriter.write_float32(packet.velocity_z || 0.0)
    |> PacketWriter.write_uint32(packet.movement_flags || 0)
    |> PacketWriter.write_uint32(packet.timestamp || 0)
    |> then(&{:ok, &1})
  end
end
```

---

## Task 7: Character Select → World Entry Flow

**Files:**
- Modify: `apps/bezgelor_protocol/lib/bezgelor_protocol/handler/character_select_handler.ex`

Update CharacterSelectHandler to initiate world entry:

```elixir
defp do_select(account_id, character_id, state) do
  case Characters.get_character(account_id, character_id) do
    nil -> {:error, :character_not_found}
    character ->
      # Update last login
      {:ok, _} = Characters.update_last_online(character)

      # Get spawn location
      spawn = Zone.spawn_location(character)

      # Build world enter packet
      world_enter = %ServerWorldEnter{
        character_id: character.id,
        world_id: spawn.world_id,
        zone_id: spawn.zone_id,
        position_x: elem(spawn.position, 0),
        position_y: elem(spawn.position, 1),
        position_z: elem(spawn.position, 2),
        rotation_x: elem(spawn.rotation, 0),
        rotation_y: elem(spawn.rotation, 1),
        rotation_z: elem(spawn.rotation, 2)
      }

      # Update session state
      state = put_in(state.session_data[:character_id], character.id)
      state = put_in(state.session_data[:character], character)

      {:reply, :server_world_enter, encode_packet(world_enter), state}
  end
end
```

---

## Task 8: ClientEnteredWorld Handler

**Files:**
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/handler/world_entry_handler.ex`

```elixir
defmodule BezgelorProtocol.Handler.WorldEntryHandler do
  @moduledoc """
  Handler for ClientEnteredWorld packet.

  Called when client finishes loading the world.
  Spawns the player entity.
  """

  @behaviour BezgelorProtocol.Handler

  def handle(_payload, state) do
    character = state.session_data[:character]

    if is_nil(character) do
      {:error, :no_character_selected}
    else
      spawn_player(character, state)
    end
  end

  defp spawn_player(character, state) do
    # Generate unique entity GUID
    guid = generate_guid()

    # Create entity spawn packet
    entity = %ServerEntityCreate{
      guid: guid,
      entity_type: :player,
      name: character.name,
      level: character.level,
      faction: character.faction_id,
      position_x: character.location_x,
      position_y: character.location_y,
      position_z: character.location_z,
      rotation_x: character.rotation_x,
      rotation_y: character.rotation_y,
      rotation_z: character.rotation_z
    }

    state = put_in(state.session_data[:entity_guid], guid)
    state = put_in(state.session_data[:in_world], true)

    {:reply, :server_entity_create, encode_packet(entity), state}
  end

  defp generate_guid do
    # Simple GUID generation - account_id + character_id + timestamp
    :erlang.unique_integer([:positive, :monotonic])
  end
end
```

---

## Task 9: Movement Handler

**Files:**
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/handler/movement_handler.ex`

```elixir
defmodule BezgelorProtocol.Handler.MovementHandler do
  @moduledoc """
  Handler for ClientMovement packets.

  Updates character position and broadcasts to nearby players.
  """

  @behaviour BezgelorProtocol.Handler

  def handle(payload, state) do
    reader = PacketReader.new(payload)

    case ClientMovement.read(reader) do
      {:ok, packet, _} ->
        process_movement(packet, state)
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp process_movement(packet, state) do
    character_id = state.session_data[:character_id]

    if is_nil(character_id) do
      {:error, :not_in_world}
    else
      # Update character position in database periodically
      # For now, just acknowledge
      update_position(character_id, packet)
      {:ok, state}
    end
  end

  defp update_position(character_id, packet) do
    # Throttle database updates (every N seconds)
    # For Phase 6, we just update on significant movement
    case Characters.get_character(character_id) do
      nil -> :ok
      character ->
        Characters.update_position(character, %{
          location_x: packet.position_x,
          location_y: packet.position_y,
          location_z: packet.position_z,
          rotation_x: packet.rotation_x,
          rotation_y: packet.rotation_y,
          rotation_z: packet.rotation_z
        })
    end
  end
end
```

---

## Task 10: WorldManager Supervisor

**Files:**
- Create: `apps/bezgelor_world/lib/bezgelor_world/world_manager.ex`

```elixir
defmodule BezgelorWorld.WorldManager do
  @moduledoc """
  Manages active world sessions and entity state.

  For Phase 6, this is a simple registry.
  Future phases will add zones, visibility, etc.
  """

  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    state = %{
      sessions: %{},     # account_id => session_pid
      entities: %{},     # guid => entity
      next_guid: 1
    }
    {:ok, state}
  end

  @doc "Generate a unique entity GUID."
  def generate_guid do
    GenServer.call(__MODULE__, :generate_guid)
  end

  @doc "Register a player session."
  def register_session(account_id, character_id, connection_pid) do
    GenServer.call(__MODULE__, {:register, account_id, character_id, connection_pid})
  end

  @doc "Unregister a session."
  def unregister_session(account_id) do
    GenServer.cast(__MODULE__, {:unregister, account_id})
  end

  # Callbacks

  def handle_call(:generate_guid, _from, state) do
    guid = state.next_guid
    {:reply, guid, %{state | next_guid: guid + 1}}
  end

  def handle_call({:register, account_id, character_id, connection_pid}, _from, state) do
    sessions = Map.put(state.sessions, account_id, %{
      character_id: character_id,
      connection_pid: connection_pid
    })
    {:reply, :ok, %{state | sessions: sessions}}
  end

  def handle_cast({:unregister, account_id}, state) do
    sessions = Map.delete(state.sessions, account_id)
    {:noreply, %{state | sessions: sessions}}
  end
end
```

---

## Task 11: Integration Tests

**Files:**
- Create: `apps/bezgelor_world/test/integration/world_entry_test.exs`

```elixir
defmodule BezgelorWorld.Integration.WorldEntryTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  describe "world entry flow" do
    test "character select sends world enter packet"
    test "client entered world spawns player entity"
    test "movement updates position"
  end
end
```

---

## Success Criteria

Phase 6 is complete when:

1. ✅ Entity struct represents in-world objects
2. ✅ Zone module provides spawn locations
3. ✅ Character select triggers world entry
4. ✅ ServerWorldEnter packet sends spawn data
5. ✅ ClientEnteredWorld spawns player entity
6. ✅ Movement packets update position
7. ✅ WorldManager tracks sessions
8. ✅ Integration tests pass
9. ✅ All tests pass

---

## Data Structures

### Entity GUID

GUIDs are 64-bit identifiers:
- High bits: entity type
- Low bits: unique counter

### Movement Flags

| Flag | Value | Description |
|------|-------|-------------|
| None | 0x0000 | Standing still |
| Forward | 0x0001 | Moving forward |
| Backward | 0x0002 | Moving backward |
| Left | 0x0004 | Strafing left |
| Right | 0x0008 | Strafing right |
| Jump | 0x0010 | Jumping |
| Falling | 0x0020 | In freefall |
| Swimming | 0x0040 | In water |

---

## Next Phase Preview

**Phase 7: Chat System** will:
- Implement chat channels (say, yell, whisper)
- Add guild/party chat (requires guilds)
- Handle emotes
- Command parsing (/commands)
