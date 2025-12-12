# Development Capture System

A comprehensive infrastructure for reverse engineering the WildStar protocol through intelligent packet capture, rich context collection, and AI-assisted analysis.

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Problem Statement](#problem-statement)
3. [Solution Overview](#solution-overview)
4. [Design Philosophy](#design-philosophy)
5. [Architecture](#architecture)
6. [Implementation Details](#implementation-details)
7. [Usage Guide](#usage-guide)
8. [Configuration Reference](#configuration-reference)
9. [File Output Structure](#file-output-structure)
10. [Testing](#testing)
11. [Future Enhancements](#future-enhancements)
12. [Decision Log](#decision-log)

---

## Executive Summary

The Development Capture System is a zero-overhead infrastructure for capturing unknown and unhandled WildStar protocol packets during gameplay. It enables a self-sustaining reverse engineering workflow where:

1. A developer plays the game with the server in development mode
2. Unknown packets are automatically captured with rich context
3. The developer provides commentary on what action triggered the packet
4. Rich reports and LLM-ready analysis prompts are generated
5. The prompts can be fed to an LLM for offline analysis
6. LLM suggests implementations that can be directly integrated

**Key Achievement**: Complete elimination of development code paths in production through compile-time macros, ensuring zero runtime overhead.

---

## Problem Statement

### The Reverse Engineering Challenge

Building a WildStar server emulator requires understanding thousands of client-server protocol messages. The traditional approach involves:

1. Packet sniffing between client and official servers (no longer possible)
2. Static analysis of client binaries
3. Reference implementations (NexusForever C#)
4. Trial and error

### Pain Points

1. **Missing Context**: When an unknown packet appears in logs, we don't know what player action triggered it
2. **Lost Opportunities**: Unknown packets are logged and forgotten; no systematic approach to analyze them
3. **Manual Process**: Each unknown packet requires manual investigation, cross-referencing, and implementation
4. **Performance Concerns**: Development instrumentation shouldn't impact production performance

### The Vision

Create a development workflow that captures packets *with full gameplay context*, enabling AI-assisted analysis that can suggest implementations. The system should be invisible in production.

---

## Solution Overview

### Self-Sustaining Reverse Engineering Loop

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    REVERSE ENGINEERING WORKFLOW                         │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   ┌──────────┐      ┌──────────────┐      ┌──────────────┐              │
│   │  Play    │─────▶│   Capture    │─────▶│  Generate    │              │
│   │  Game    │      │   Packets    │      │   Reports    │              │
│   └──────────┘      └──────────────┘      └──────────────┘              │
│        │                   │                     │                      │
│        │                   │                     ▼                      │
│        │                   │            ┌──────────────┐                │
│        │                   │            │ Feed to      │                │
│        │                   │            │ an LLM       │                │
│        │                   │            └──────────────┘                │
│        │                   │                     │                      │
│        │                   │                     ▼                      │
│        │                   │            ┌──────────────┐                │
│   ┌────┴────┐              │            │   LLM        │                │
│   │ Test    │◀─────────────┼────────────│   Analysis   │                │
│   │ Changes │              │            └──────────────┘                │
│   └─────────┘              │                     │                      │
│        ▲                   │                     ▼                      │
│        │                   │            ┌──────────────┐                │
│        │                   │            │  Implement   │                │
│        └───────────────────┴────────────│   Handler    │                │
│                                         └──────────────┘                │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Core Features

| Feature | Description |
|---------|-------------|
| **Zero-Overhead Hooks** | Compile-time macros that expand to `:ok` in production |
| **Rich Context Capture** | Player state, zone, position, recent packet history |
| **Interactive Mode** | Terminal UI prompts for player commentary |
| **LLM Integration** | Generated prompts ready for offline analysis |
| **Multiple Output Formats** | Markdown reports, JSON data, analysis prompts |

---

## Design Philosophy

### 1. Zero Production Overhead

The most critical requirement: development code must have **zero impact** on production performance. This is achieved through compile-time elimination using Elixir macros.

```elixir
# When mode is :disabled (production), this:
Hooks.on_unknown_opcode(opcode, payload, state)

# Compiles to simply:
:ok
```

No function calls, no condition checks, no code paths - just a literal `:ok` atom.

### 2. Context is King

A packet dump without context is nearly useless. The system captures:

- **Player State**: Character ID, name, position, zone
- **Session State**: Authentication status, in-world flag
- **Packet History**: Last N packets in both directions with timing
- **Player Commentary**: What the developer was doing when the packet appeared

### 3. Offline Analysis Over Live API

The original design considered live LLM API integration during gameplay. This wasn't done because:

1. **Latency**: API calls would interrupt gameplay flow
2. **Cost**: Each unknown packet would incur API costs
3. **Control**: Developers want to review analysis, not auto-apply it
4. **Batching**: Multiple similar packets can be analyzed together

Instead, the system generates rich prompts that can be fed to an LLM at the developer's convenience.

### 4. Non-Intrusive Integration

The capture system is a separate umbrella app (`bezgelor_dev`) with minimal coupling to the protocol layer. Integration requires only:

```elixir
require BezgelorDev.Hooks
alias BezgelorDev.Hooks

# In packet handling:
Hooks.on_unknown_opcode(opcode, payload, state)
```

---

## Architecture

### Module Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           bezgelor_dev                                   │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌────────────────────┐  ┌────────────────────┐  ┌──────────────────┐   │
│  │  BezgelorDev.Hooks │  │ BezgelorDev        │  │ BezgelorDev.     │   │
│  │  (Compile-time)    │  │ DevCapture         │  │ PacketContext    │   │
│  │                    │  │ (GenServer)        │  │ (Struct)         │   │
│  │  • on_unknown_     │  │                    │  │                  │   │
│  │    opcode          │  │  • Event capture   │  │  • Player state  │   │
│  │  • on_unhandled_   │  │  • Context mgmt    │  │  • Zone info     │   │
│  │    opcode          │  │  • Mode routing    │  │  • Packet history│   │
│  │  • on_handler_     │  │  • File output     │  │  • Timing data   │   │
│  │    error           │  │                    │  │                  │   │
│  │  • track_packet    │  │                    │  │                  │   │
│  └────────────────────┘  └────────────────────┘  └──────────────────┘   │
│                                                                          │
│  ┌────────────────────┐  ┌────────────────────┐  ┌──────────────────┐   │
│  │ BezgelorDev.       │  │ BezgelorDev.       │  │ BezgelorDev.     │   │
│  │ InteractivePrompt  │  │ ReportGenerator    │  │ LlmAssistant     │   │
│  │                    │  │                    │  │                  │   │
│  │  • Terminal UI     │  │  • Markdown output │  │  • Analysis      │   │
│  │  • Colored display │  │  • JSON output     │  │    prompts       │   │
│  │  • Player input    │  │  • Summary reports │  │  • Batch prompts │   │
│  │  • Action menu     │  │  • Hex dumps       │  │  • File saving   │   │
│  └────────────────────┘  └────────────────────┘  └──────────────────┘   │
│                                                                          │
│  ┌────────────────────┐                                                  │
│  │ BezgelorDev.       │                                                  │
│  │ StubGenerator      │                                                  │
│  │                    │                                                  │
│  │  • Opcode entries  │                                                  │
│  │  • Packet structs  │                                                  │
│  │  • Handler stubs   │                                                  │
│  └────────────────────┘                                                  │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Data Flow

```
                          Compile Time
                               │
                               ▼
┌──────────────────────────────────────────────────────────────────────┐
│ config :bezgelor_dev, mode: :disabled | :logging | :interactive      │
└──────────────────────────────────────┬───────────────────────────────┘
                                       │
                                       ▼
                          ┌────────────────────┐
                          │  BezgelorDev.Hooks │
                          │  @dev_mode_enabled │
                          │ = mode != :disabled│
                          └────────────┬───────┘
                                       │
         ┌─────────────────────────────┼─────────────────────────────┐
         │                             │                             │
         ▼                             ▼                             ▼
   mode = :disabled            mode = :logging              mode = :interactive
         │                             │                             │
         ▼                             ▼                             ▼
   Macros expand to:          GenServer.cast to           GenServer.cast to
   quote do: :ok              DevCapture                  DevCapture
         │                             │                             │
         ▼                             │                             │
   Zero runtime cost                   │                             │
                                       ▼                             ▼
                              Save to files              InteractivePrompt
                              silently                   displays UI
                                       │                             │
                                       │                             ▼
                                       │                    Player provides
                                       │                    commentary
                                       │                             │
                                       ▼                             ▼
                              ┌─────────────────────────────────────────┐
                              │           Save Outputs                  │
                              │  • Markdown report (*.md)               │
                              │  • JSON data (*.json)                   │
                              │  • LLM prompt (*_prompt.md)             │
                              └─────────────────────────────────────────┘
```

### Connection Integration

The hooks are integrated into `BezgelorProtocol.Connection` at strategic points:

```elixir
# apps/bezgelor_protocol/lib/bezgelor_protocol/connection.ex

defp handle_packet(opcode, payload, state) do
  case Opcode.from_integer(opcode) do
    {:ok, opcode_atom} ->
      # Track inbound for context history
      Hooks.track_packet(:inbound, opcode_atom, payload, state)
      dispatch_to_handler(opcode_atom, payload, state)

    {:error, :unknown_opcode} ->
      # Capture unknown opcode
      Hooks.on_unknown_opcode(opcode, payload, state)
      {:ok, state}
  end
end

defp dispatch_to_handler(opcode_atom, payload, state) do
  case PacketRegistry.lookup(opcode_atom) do
    nil ->
      # Capture unhandled (known but no handler)
      Hooks.on_unhandled_opcode(opcode_atom, payload, state)
      {:ok, state}

    handler ->
      case handler.handle(payload, state) do
        {:reply, opcode, reply_payload, new_state} ->
          # Track outbound for context history
          Hooks.track_packet(:outbound, opcode, reply_payload, new_state)
          # ...

        {:error, reason} ->
          # Capture handler errors
          Hooks.on_handler_error(opcode_atom, payload, reason, state)
          # ...
      end
  end
end
```

---

## Implementation Details

### Compile-Time Mode Detection

The key to zero-overhead is evaluating the mode at compile time:

```elixir
# apps/bezgelor_dev/lib/bezgelor_dev/hooks.ex

defmodule BezgelorDev.Hooks do
  # Evaluated ONCE at compile time
  @dev_mode_enabled Application.compile_env(:bezgelor_dev, :mode, :disabled) != :disabled

  defmacro on_unknown_opcode(opcode_int, payload, state) do
    # This condition is evaluated at compile time, not runtime
    if @dev_mode_enabled do
      quote do
        BezgelorDev.DevCapture.capture_unknown_opcode(
          unquote(opcode_int),
          unquote(payload),
          unquote(state)
        )
      end
    else
      quote do: :ok
    end
  end
end
```

**Critical**: The `@dev_mode_enabled` module attribute is evaluated when the `Hooks` module is compiled. The macros then check this attribute at compile time, resulting in either the capture code or `:ok` being injected into the calling module.

### Capture Event Structure

Each capture event contains:

```elixir
%{
  type: :unknown_opcode | :unhandled_opcode | :handler_error,
  timestamp: ~U[2024-01-15 12:00:00Z],
  opcode: 0x1234,                    # Integer or atom
  opcode_hex: "0x1234",              # Formatted string
  payload: <<binary>>,               # Raw bytes
  payload_hex: "0102030405...",      # Hex string
  error: nil | term(),               # For handler errors
  context: %PacketContext{},         # Rich context
  player_commentary: "I clicked..." # From interactive prompt
}
```

### Context Structure

```elixir
%BezgelorDev.PacketContext{
  connection_id: "conn_A3F2",
  connection_type: :world,
  timestamp: ~U[2024-01-15 12:00:00Z],

  # Player state (from session_data)
  player_id: 12345,
  player_name: "TestCharacter",
  player_position: {2847.3, 103.2, -892.1},
  player_zone_id: 6,
  player_zone_name: "Thayd",

  # Session state
  session_state: :authenticated,
  in_world: true,

  # Packet history (most recent first)
  recent_packets: [
    %{direction: :inbound, opcode: :client_move, size: 48, time_ago_ms: 300},
    %{direction: :outbound, opcode: :server_entity_update, size: 124, time_ago_ms: 450},
    # ...
  ],

  last_packet_received_at: ~U[2024-01-15 11:59:59.700Z],
  last_packet_sent_at: ~U[2024-01-15 11:59:59.550Z]
}
```

### Interactive Prompt UI

When an unknown packet is captured in interactive mode:

```
═══════════════════════════════════════════════════════════════
  UNKNOWN PACKET DETECTED
═══════════════════════════════════════════════════════════════

  Opcode: 0x0847 (2119 decimal)
  Size: 24 bytes
  Raw: 47 08 18 00 00 00 01 00 00 00 ff ff 00 00 ...

  Recent context:
  • ← ClientMovement (300ms ago)
  • → ServerEntityUpdate (450ms ago)
  • → ServerEntityCreate (1.2s ago)
  • Zone: Thayd
  • Position: (2847.3, 103.2, -892.1)

───────────────────────────────────────────────────────────────
  What were you doing when this happened?
  (Press Enter to skip)
  > I opened my inventory and clicked on a consumable item

───────────────────────────────────────────────────────────────
  [L]og for Analysis  [S]kip  [Q]uit dev mode
  > l

  Saved to: priv/dev_captures/sessions/2025-12-11_14-32-18/captures/001_0847_unknown_prompt.md
  Feed this to an LLM later for analysis.
```

### LLM Prompt Generation

The generated prompts are designed to give an LLM all necessary context:

```markdown
# WildStar Packet Analysis Request

I'm working on Bezgelor, an Elixir WildStar server emulator (port of NexusForever).
I captured an unknown packet during gameplay and need help analyzing it.

## Packet Data
- **Opcode**: 0x0847 (2119 decimal)
- **Size**: 24 bytes
- **Direction**: Client → Server

### Raw Bytes (hex)
```
00000000  47 08 18 00 00 00 01 00  00 00 ff ff 00 00 00 00  |G...............|
00000010  01 00 00 00 00 00 00 00                           |........        |
```

### Raw Bytes (base64)
```
RwgYAAAAAQAAAAD//wAAAAABAAAAAAAAAAA=
```

## Capture Context

### Player State
- **Zone**: Thayd
- **Position**: (2847.3, 103.2, -892.1)
- **Player**: TestCharacter
- **In World**: true
- **Session State**: authenticated

### Recent Packets (before this one)
| Dir | Opcode | Time Ago |
|-----|--------|----------|
| ← | ClientMovement | 300ms |
| → | ServerEntityUpdate | 450ms |
| → | ServerEntityCreate | 1200ms |

### What I Was Doing
> I opened my inventory and clicked on a consumable item

## What I Need

1. **Suggest an opcode name** following WildStar/NexusForever conventions
   (e.g., ClientInventoryMove, ClientQuestAccept)

2. **Analyze the byte structure** - identify likely fields:
   - Data types (uint32, uint16, uint8, float32, string, etc.)
   - Offsets and sizes
   - Likely meanings based on context

3. **Generate Elixir code** for:
   - Opcode entry for `apps/bezgelor_protocol/lib/bezgelor_protocol/opcode.ex`
   - Packet struct module with `Readable` behaviour
   - Handler stub module

4. **Reference NexusForever** if you can find similar patterns in the C# codebase
```

---

## Usage Guide

### Enabling Development Mode

Edit `config/dev.exs`:

```elixir
config :bezgelor_dev,
  mode: :interactive,              # or :logging
  capture_directory: "priv/dev_captures",
  packet_history_size: 20
```

**Important**: After changing the mode, you must recompile the protocol module:

```bash
mix compile --force
```

### Mode Descriptions

| Mode | Behavior |
|------|----------|
| `:disabled` | All hooks compile to `:ok`. Zero overhead. |
| `:logging` | Captures silently to files. No interaction. |
| `:interactive` | Displays UI, prompts for commentary, saves to files. |

### Running in Interactive Mode

1. Start the server with dev mode enabled
2. Connect a WildStar client
3. Play the game normally
4. When unknown packets appear, the terminal will prompt you
5. Describe what you were doing
6. Choose to Log, Skip, or Quit

### Analyzing Captures with an LLM

After a gameplay session:

```bash
# Find your session
ls apps/bezgelor_dev/priv/dev_captures/sessions/

# Open the generated prompt in your editor
cat apps/bezgelor_dev/priv/dev_captures/sessions/2025-12-11_14-32-18/captures/001_0847_unknown_prompt.md

# Or use the batch analysis prompt for multiple captures
cat apps/bezgelor_dev/priv/dev_captures/sessions/2025-12-11_14-32-18/captures/batch_analysis.md
```

Then paste the prompt content into an LLM and ask for analysis.

### Exporting Session Summary

From IEx:

```elixir
# Export as markdown
BezgelorDev.DevCapture.export_captures(:markdown)
# => {:ok, "priv/dev_captures/reports/summary_2025-12-11_session_abc123.md"}

# Export as JSON
BezgelorDev.DevCapture.export_captures(:json)
# => {:ok, "priv/dev_captures/reports/summary_2025-12-11_session_abc123.json"}
```

---

## Configuration Reference

### All Options

```elixir
config :bezgelor_dev,
  # Master mode switch
  # :disabled - No capture, zero overhead (default)
  # :logging  - Silent capture to files
  # :interactive - Terminal prompts for commentary
  mode: :disabled,

  # Where to save capture files (relative to bezgelor_dev app)
  capture_directory: "priv/dev_captures",

  # Number of recent packets to track for context
  packet_history_size: 20,

  # Interactive sub-mode (for future LLM API integration)
  # :log_only - Just save to files (current behavior)
  # :llm_assisted - Reserved for future live API calls
  interactive_mode: :log_only
```

### Environment-Specific Defaults

**config/config.exs** (base):
```elixir
config :bezgelor_dev, mode: :disabled
```

**config/dev.exs** (development):
```elixir
config :bezgelor_dev,
  mode: :disabled,  # Enable as needed
  capture_directory: "priv/dev_captures",
  packet_history_size: 20
```

**config/prod.exs** (production):
```elixir
config :bezgelor_dev, mode: :disabled  # Always disabled
```

**config/test.exs** (testing):
```elixir
config :bezgelor_dev, mode: :disabled  # Tests don't need capture
```

---

## File Output Structure

```
apps/bezgelor_dev/priv/dev_captures/
├── sessions/
│   └── 2025-12-11_14-32-18_a7b3c9f2/
│       ├── session_info.json           # Session metadata
│       ├── captures/
│       │   ├── 001_0847_unknown_opcode.md      # Human-readable report
│       │   ├── 001_0847_unknown_opcode.json    # Machine-readable data
│       │   ├── 001_0847_unknown_opcode_prompt.md # LLM Code prompt
│       │   ├── 002_0923_unhandled_opcode.md
│       │   ├── 002_0923_unhandled_opcode.json
│       │   └── 002_0923_unhandled_opcode_prompt.md
│       └── generated_stubs/            # For future auto-generation
├── reports/
│   ├── summary_2025-12-11_session_a7b3c9f2.md
│   └── summary_2025-12-11_session_a7b3c9f2.json
└── analysis_prompts/                   # Batch prompts directory
    └── batch_2025-12-11.md
```

### File Formats

**session_info.json**:
```json
{
  "session_id": "2025-12-11_14-32-18_a7b3c9f2",
  "started_at": "2025-12-11T14:32:18Z",
  "mode": "interactive",
  "interactive_mode": "log_only"
}
```

**capture.json**:
```json
{
  "type": "unknown_opcode",
  "timestamp": "2025-12-11T14:35:22Z",
  "opcode": {
    "value": 2119,
    "hex": "0x0847",
    "decimal": "2119"
  },
  "payload": {
    "size": 24,
    "hex": "470818000000010000...",
    "base64": "RwgYAAAAAQAAAAD//wAA..."
  },
  "context": {
    "connection_type": "world",
    "player": {
      "name": "TestCharacter",
      "zone_name": "Thayd",
      "position": {"x": 2847.3, "y": 103.2, "z": -892.1}
    },
    "recent_packets": [...]
  },
  "player_commentary": "I opened my inventory and clicked..."
}
```

---

## Testing

### Test Suite

The system includes 66 tests covering all modules:

| Test File | Tests | Coverage |
|-----------|-------|----------|
| `bezgelor_dev_test.exs` | 14 | Configuration helpers |
| `packet_context_test.exs` | 12 | Context creation, packet tracking |
| `report_generator_test.exs` | 18 | Markdown/JSON generation |
| `llm_assistant_test.exs` | 22 | Prompt generation, file saving |
| `hooks_test.exs` | 2 | Macro compilation verification |

### Running Tests

```bash
# Run all bezgelor_dev tests
mix test apps/bezgelor_dev/test/

# Run with trace output
mix test apps/bezgelor_dev/test/ --trace

# Run a specific test file
mix test apps/bezgelor_dev/test/packet_context_test.exs
```

### Testing Compile-Time Elimination

To verify hooks compile to `:ok` in disabled mode:

1. Set `mode: :disabled` in config
2. Run `mix compile --force`
3. Check compiled beam file for hook calls (should be absent)

---

## Future Enhancements

### Near-Term

1. **Batch Analysis Prompts**: Generate combined prompts for multiple similar packets
2. **Pattern Detection**: Identify packets that frequently appear together
3. **Auto-Stub Generation**: Generate Elixir stub code directly from LLM responses

### Medium-Term

1. **Web Dashboard**: Phoenix LiveView interface for viewing and managing captures
2. **NexusForever Search**: Direct integration to search NexusForever C# codebase
3. **Packet Similarity Scoring**: Group similar unknown packets automatically

### Long-Term

1. **Live LLM Integration**: Optional real-time API calls for immediate analysis
2. **Auto-Implementation**: LLM generates complete handler implementations
3. **Learning System**: Track which patterns lead to successful implementations

---

## Decision Log

### Decision 1: Offline Analysis vs Live API

**Context**: Original design included live LLM API calls during gameplay.

**Decision**: Generate prompts for offline analysis instead.

**Rationale**:
- API latency would interrupt gameplay
- Per-call costs accumulate
- Developers want control over when/how analysis happens
- Batch analysis is more efficient

### Decision 2: Compile-Time vs Runtime Mode Check

**Context**: Should mode checking happen at compile time or runtime?

**Decision**: Compile-time using module attributes.

**Rationale**:
- Zero runtime overhead in production
- No function calls in hot paths
- Mode changes require recompilation (acceptable trade-off)

### Decision 3: Separate Umbrella App

**Context**: Where should capture code live?

**Decision**: New `bezgelor_dev` umbrella app.

**Rationale**:
- Clear separation of concerns
- Easy to exclude from production builds
- No circular dependencies
- Clean dependency graph

### Decision 4: No BezgelorProtocol Dependency

**Context**: bezgelor_dev initially depended on bezgelor_protocol for Opcode module.

**Decision**: Remove the dependency; access Opcode at runtime only.

**Rationale**:
- Avoids circular dependency (protocol needs dev for hooks)
- Runtime access via `BezgelorProtocol.Opcode.to_integer/1` is fine
- Compile-time elimination still works

### Decision 5: GenServer for Capture State

**Context**: How to manage capture state and packet history?

**Decision**: Use GenServer (DevCapture) with per-connection context maps.

**Rationale**:
- Single point of state management
- Easy to add features (export, stats)
- Process isolation from connection handlers
- Async cast for non-blocking capture

---

## Appendix: Module Reference

### BezgelorDev

Main module with configuration helpers.

```elixir
BezgelorDev.mode()                    # => :disabled | :logging | :interactive
BezgelorDev.enabled?()                # => boolean()
BezgelorDev.interactive_mode()        # => :log_only | :llm_assisted
BezgelorDev.capture_directory()       # => "priv/dev_captures"
BezgelorDev.packet_history_size()     # => 20
```

### BezgelorDev.Hooks

Compile-time macros for zero-overhead capture.

```elixir
# Must be required in calling module
require BezgelorDev.Hooks

# Available macros
Hooks.on_unknown_opcode(opcode_int, payload, state)
Hooks.on_unhandled_opcode(opcode_atom, payload, state)
Hooks.on_handler_error(opcode_atom, payload, error, state)
Hooks.track_packet(direction, opcode, payload, state)

# Helper function
Hooks.dev_mode_enabled?()  # => boolean (compile-time value)
```

### BezgelorDev.DevCapture

GenServer for capture management.

```elixir
# Client API (async)
DevCapture.capture_unknown_opcode(opcode_int, payload, conn_state)
DevCapture.capture_unhandled_opcode(opcode_atom, payload, conn_state)
DevCapture.capture_handler_error(opcode_atom, payload, error, conn_state)
DevCapture.track_packet(direction, opcode, payload, conn_state)

# Client API (sync)
DevCapture.get_recent_packets(connection_id, count \\ 20)
DevCapture.get_pending_captures()
DevCapture.export_captures(format \\ :markdown)
DevCapture.get_stats()
```

### BezgelorDev.PacketContext

Context struct with creation and manipulation functions.

```elixir
PacketContext.from_connection_state(conn_state)  # => %PacketContext{}
PacketContext.add_packet(context, direction, opcode, size)  # => %PacketContext{}
PacketContext.update_time_deltas(context)  # => %PacketContext{}
PacketContext.to_map(context)  # => map()
```

### BezgelorDev.InteractivePrompt

Terminal UI for player interaction.

```elixir
InteractivePrompt.prompt_for_context(event)  # => {commentary, action}
InteractivePrompt.display_save_confirmation(path)  # => :ok
```

### BezgelorDev.ReportGenerator

Report generation in multiple formats.

```elixir
ReportGenerator.generate_markdown_report(event)  # => String.t()
ReportGenerator.generate_json_report(event)  # => String.t()
ReportGenerator.generate_summary_report(captures, state)  # => String.t()
```

### BezgelorDev.LlmAssistant

LLM Code prompt generation.

```elixir
LlmAssistant.generate_analysis_prompt(event)  # => String.t()
LlmAssistant.generate_batch_prompt(events)  # => String.t()
LlmAssistant.save_prompts_for_analysis(session_id, events)  # => {:ok, path}
```

### BezgelorDev.StubGenerator

Code stub generation (for future auto-implementation).

```elixir
StubGenerator.generate_opcode_entry(opcode_int, suggested_name)  # => String.t()
StubGenerator.generate_packet_struct(suggested_name, field_analysis)  # => String.t()
StubGenerator.generate_handler_stub(suggested_name)  # => String.t()
```

---

*Document Version: 1.0*
*Last Updated: 2025-12-11*
*Implementation Status: Complete*
