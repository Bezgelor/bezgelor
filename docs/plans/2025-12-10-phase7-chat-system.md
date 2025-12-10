# Phase 7: Chat System - Implementation Plan

**Goal:** Implement basic chat functionality so players can communicate in the game world.

**Outcome:** Players can send and receive chat messages in various channels (say, yell, whisper).

---

## Overview

Chat is essential for MMO gameplay. This phase implements:
- Local chat (say, yell)
- Private messages (whisper)
- System messages
- Command parsing (/commands)

Guild and party chat require guild/party systems (future phases).

### Chat Flow

```
Player types message
        │
        ▼
┌───────────────────────────────────────┐
│ Client sends: ClientChat              │
│   - Channel type                      │
│   - Message text                      │
│   - Target (for whisper)              │
└───────────────────────────────────────┘
        │
        ▼
┌───────────────────────────────────────┐
│ Server validates message              │
│   - Check permissions                 │
│   - Filter profanity (future)         │
│   - Parse commands                    │
└───────────────────────────────────────┘
        │
        ▼
┌───────────────────────────────────────┐
│ Server broadcasts: ServerChat         │
│   - To nearby players (say/yell)      │
│   - To specific player (whisper)      │
│   - To sender (echo/error)            │
└───────────────────────────────────────┘
```

### Key Packets

| Opcode | Name | Direction | Description |
|--------|------|-----------|-------------|
| 0x0300 | ClientChat | C→S | Player sends chat message |
| 0x0301 | ServerChat | S→C | Server broadcasts message |
| 0x0302 | ServerChatResult | S→C | Chat result/error |

### Chat Channels

| Channel | Value | Description | Range |
|---------|-------|-------------|-------|
| Say | 0 | Local chat | ~30m |
| Yell | 1 | Loud local chat | ~100m |
| Whisper | 2 | Private message | Global |
| System | 3 | System messages | N/A |
| Emote | 4 | Character emotes | ~30m |
| Party | 5 | Party chat | Party members |
| Guild | 6 | Guild chat | Guild members |
| Zone | 7 | Zone-wide chat | Current zone |

---

## Tasks

### Batch 1: Chat Data Structures (Tasks 1-2)

| Task | Description |
|------|-------------|
| 1 | Add chat opcodes to Opcode module |
| 2 | Create ChatChannel enum/constants |

### Batch 2: Chat Packets (Tasks 3-5)

| Task | Description |
|------|-------------|
| 3 | Define ClientChat packet (readable) |
| 4 | Define ServerChat packet (writable) |
| 5 | Define ServerChatResult packet |

### Batch 3: Chat Handler (Tasks 6-8)

| Task | Description |
|------|-------------|
| 6 | Implement ChatHandler for ClientChat |
| 7 | Implement command parsing (/commands) |
| 8 | Add chat broadcast to WorldManager |

### Batch 4: Integration (Tasks 9-10)

| Task | Description |
|------|-------------|
| 9 | Add integration tests for chat |
| 10 | Run full test suite |

---

## Task 1: Chat Opcodes

**Files:**
- Modify: `apps/bezgelor_protocol/lib/bezgelor_protocol/opcode.ex`

Add chat-related opcodes:

```elixir
# Chat opcodes
@client_chat 0x0300
@server_chat 0x0301
@server_chat_result 0x0302
```

---

## Task 2: Chat Channel Constants

**Files:**
- Create: `apps/bezgelor_core/lib/bezgelor_core/chat.ex`

```elixir
defmodule BezgelorCore.Chat do
  @moduledoc """
  Chat channel definitions and utilities.
  """

  @type channel ::
          :say
          | :yell
          | :whisper
          | :system
          | :emote
          | :party
          | :guild
          | :zone

  # Channel values
  @channel_say 0
  @channel_yell 1
  @channel_whisper 2
  @channel_system 3
  @channel_emote 4
  @channel_party 5
  @channel_guild 6
  @channel_zone 7

  # Channel ranges (in game units)
  @say_range 30.0
  @yell_range 100.0
  @emote_range 30.0

  def channel_to_int(:say), do: @channel_say
  def channel_to_int(:yell), do: @channel_yell
  # ... etc

  def int_to_channel(@channel_say), do: :say
  # ... etc

  def range(:say), do: @say_range
  def range(:yell), do: @yell_range
  def range(:emote), do: @emote_range
  def range(_), do: nil  # Global or N/A
end
```

---

## Task 3: ClientChat Packet

**Files:**
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/client_chat.ex`

```elixir
defmodule BezgelorProtocol.Packets.World.ClientChat do
  @moduledoc """
  Chat message from client.

  ## Wire Format

  channel      : uint32  - Chat channel
  target_len   : uint32  - Target name length (for whisper)
  target       : wstring - Target name (for whisper)
  message_len  : uint32  - Message length
  message      : wstring - Message text
  """

  @behaviour BezgelorProtocol.Packet.Readable

  defstruct [:channel, :target, :message]

  def read(reader) do
    with {:ok, channel_int, reader} <- PacketReader.read_uint32(reader),
         {:ok, target, reader} <- PacketReader.read_wide_string(reader),
         {:ok, message, reader} <- PacketReader.read_wide_string(reader) do
      channel = Chat.int_to_channel(channel_int)
      {:ok, %__MODULE__{channel: channel, target: target, message: message}, reader}
    end
  end
end
```

---

## Task 4: ServerChat Packet

**Files:**
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_chat.ex`

```elixir
defmodule BezgelorProtocol.Packets.World.ServerChat do
  @moduledoc """
  Chat message broadcast to clients.

  ## Wire Format

  channel      : uint32  - Chat channel
  sender_guid  : uint64  - Sender entity GUID
  sender_len   : uint32  - Sender name length
  sender       : wstring - Sender name
  message_len  : uint32  - Message length
  message      : wstring - Message text
  """

  @behaviour BezgelorProtocol.Packet.Writable

  defstruct [:channel, :sender_guid, :sender_name, :message]

  def write(packet, writer) do
    channel_int = Chat.channel_to_int(packet.channel)

    writer
    |> PacketWriter.write_uint32(channel_int)
    |> PacketWriter.write_uint64(packet.sender_guid || 0)
    |> PacketWriter.write_wide_string(packet.sender_name || "")
    |> PacketWriter.write_wide_string(packet.message || "")
    |> then(&{:ok, &1})
  end
end
```

---

## Task 5: ServerChatResult Packet

**Files:**
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_chat_result.ex`

```elixir
defmodule BezgelorProtocol.Packets.World.ServerChatResult do
  @moduledoc """
  Chat operation result/error.

  ## Result Codes

  | Code | Name | Description |
  |------|------|-------------|
  | 0 | success | Message sent |
  | 1 | player_not_found | Whisper target not found |
  | 2 | player_offline | Target is offline |
  | 3 | muted | You are muted |
  | 4 | channel_unavailable | Channel not available |
  """

  @behaviour BezgelorProtocol.Packet.Writable

  @result_success 0
  @result_player_not_found 1
  @result_player_offline 2
  @result_muted 3
  @result_channel_unavailable 4

  defstruct [:result, :channel]

  def write(packet, writer) do
    result_code = result_to_code(packet.result)
    channel_int = Chat.channel_to_int(packet.channel)

    writer
    |> PacketWriter.write_uint32(result_code)
    |> PacketWriter.write_uint32(channel_int)
    |> then(&{:ok, &1})
  end
end
```

---

## Task 6: ChatHandler

**Files:**
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/handler/chat_handler.ex`

```elixir
defmodule BezgelorProtocol.Handler.ChatHandler do
  @moduledoc """
  Handler for ClientChat packets.

  Processes chat messages and broadcasts to appropriate recipients.
  """

  @behaviour BezgelorProtocol.Handler

  def handle(payload, state) do
    reader = PacketReader.new(payload)

    case ClientChat.read(reader) do
      {:ok, packet, _} ->
        process_chat(packet, state)
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp process_chat(packet, state) do
    case packet.channel do
      :say -> handle_say(packet, state)
      :yell -> handle_yell(packet, state)
      :whisper -> handle_whisper(packet, state)
      :emote -> handle_emote(packet, state)
      _ -> {:error, :channel_unavailable}
    end
  end

  defp handle_say(packet, state) do
    # Broadcast to nearby players within say range
    broadcast_local(packet.message, :say, state)
  end

  defp handle_whisper(packet, state) do
    # Send to specific player
    send_whisper(packet.target, packet.message, state)
  end
end
```

---

## Task 7: Command Parsing

**Files:**
- Create: `apps/bezgelor_core/lib/bezgelor_core/chat_command.ex`

Commands start with "/" and perform special actions.

```elixir
defmodule BezgelorCore.ChatCommand do
  @moduledoc """
  Chat command parsing and execution.

  ## Built-in Commands

  | Command | Description |
  |---------|-------------|
  | /say | Send local message |
  | /yell | Send yell message |
  | /whisper | Send private message |
  | /w | Alias for whisper |
  | /who | List nearby players |
  | /loc | Show current location |
  """

  @type command_result ::
          {:chat, atom(), String.t()}
          | {:action, atom(), list()}
          | {:error, atom()}

  @doc "Parse a chat message for commands."
  @spec parse(String.t()) :: command_result()
  def parse("/" <> rest) do
    parse_command(rest)
  end

  def parse(message) do
    {:chat, :say, message}
  end

  defp parse_command(text) do
    case String.split(text, " ", parts: 2) do
      ["say" | rest] -> {:chat, :say, Enum.join(rest, " ")}
      ["yell" | rest] -> {:chat, :yell, Enum.join(rest, " ")}
      ["whisper", rest] -> parse_whisper(rest)
      ["w", rest] -> parse_whisper(rest)
      ["who"] -> {:action, :who, []}
      ["loc"] -> {:action, :loc, []}
      _ -> {:error, :unknown_command}
    end
  end

  defp parse_whisper(text) do
    case String.split(text, " ", parts: 2) do
      [target, message] -> {:whisper, target, message}
      _ -> {:error, :invalid_whisper}
    end
  end
end
```

---

## Task 8: Chat Broadcast in WorldManager

**Files:**
- Modify: `apps/bezgelor_world/lib/bezgelor_world/world_manager.ex`

Add functions to broadcast chat to nearby players:

```elixir
@doc "Broadcast chat to players within range."
def broadcast_chat(sender_guid, channel, message, position) do
  GenServer.cast(__MODULE__, {:broadcast_chat, sender_guid, channel, message, position})
end

@doc "Send whisper to specific player."
def send_whisper(sender_guid, target_name, message) do
  GenServer.call(__MODULE__, {:send_whisper, sender_guid, target_name, message})
end

# In handle_cast
def handle_cast({:broadcast_chat, sender_guid, channel, message, position}, state) do
  range = Chat.range(channel)

  # Find players within range
  recipients = find_players_in_range(state.sessions, position, range)

  # Send to each recipient
  Enum.each(recipients, fn {_account_id, session} ->
    send_chat_to_connection(session.connection_pid, sender_guid, channel, message)
  end)

  {:noreply, state}
end
```

---

## Task 9: Integration Tests

**Files:**
- Create: `apps/bezgelor_world/test/integration/chat_test.exs`

```elixir
defmodule BezgelorWorld.Integration.ChatTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  describe "chat flow" do
    test "say message is echoed back to sender"
    test "whisper to online player succeeds"
    test "whisper to offline player returns error"
    test "command parsing works for /say"
  end
end
```

---

## Success Criteria

Phase 7 is complete when:

1. ✅ Chat opcodes defined
2. ✅ Chat channel constants defined
3. ✅ ClientChat packet parses messages
4. ✅ ServerChat packet broadcasts messages
5. ✅ ChatHandler processes say/yell/whisper
6. ✅ Command parsing for /say /yell /whisper
7. ✅ Integration tests pass
8. ✅ All tests pass

---

## Future Enhancements

- **Party Chat** - Requires party system (Phase 8+)
- **Guild Chat** - Requires guild system (Phase 9+)
- **Profanity Filter** - Content moderation
- **Chat Logging** - Audit trail for moderation
- **Rate Limiting** - Spam prevention
- **Ignore List** - Block messages from players

---

## Next Phase Preview

**Phase 8: Basic Combat** will:
- Implement targeting system
- Add basic attack packets
- Implement damage calculation
- Add health regeneration
