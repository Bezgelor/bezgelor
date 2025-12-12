# Development Capture System with Claude Integration

## Overview

A development-mode infrastructure for capturing unknown/unhandled WildStar protocol packets during gameplay, collecting rich context, and optionally using Claude API to assist with reverse engineering.

## Design Goals

1. **Zero overhead when disabled** - No function calls, no checks in hot paths
2. **Compile-time elimination** - Use macros to completely remove dev code in production
3. **Config-driven modes** - `:disabled`, `:logging`, `:interactive`
4. **Interactive sub-modes** - `:log_only` or `:llm_assisted`
5. **Rich context capture** - Player state, recent packets, zone info, timestamps
6. **Player commentary** - Prompt for "what were you doing?" in interactive mode

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        DEVELOPMENT MODE ARCHITECTURE                         │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌──────────┐     ┌─────────────────────┐                                   │
│  │ WildStar │────▶│   Connection.ex     │                                   │
│  │  Client  │◀────│   (with dev hooks)  │                                   │
│  └──────────┘     └──────────┬──────────┘                                   │
│                              │                                               │
│                              │ (compile-time macro)                          │
│                              ▼                                               │
│                   ┌──────────────────────┐                                   │
│                   │  BezgelorDev.Hooks   │  ◀── Only compiled in dev mode   │
│                   │  (capture events)    │                                   │
│                   └──────────┬───────────┘                                   │
│                              │                                               │
│              ┌───────────────┼───────────────┐                               │
│              │               │               │                               │
│              ▼               ▼               ▼                               │
│     ┌────────────┐  ┌────────────┐  ┌────────────┐                          │
│     │  DISABLED  │  │  LOGGING   │  │INTERACTIVE │                          │
│     │  (no-op)   │  │ (to file)  │  │  (prompt)  │                          │
│     └────────────┘  └─────┬──────┘  └─────┬──────┘                          │
│                           │               │                                  │
│                           ▼               ▼                                  │
│                   ┌───────────────────────────────┐                          │
│                   │     DevCapture GenServer      │                          │
│                   │  • Event buffer (last N)      │                          │
│                   │  • Context snapshots          │                          │
│                   │  • Report generation          │                          │
│                   └───────────────┬───────────────┘                          │
│                                   │                                          │
│                    ┌──────────────┴──────────────┐                           │
│                    │                             │                           │
│                    ▼                             ▼                           │
│           ┌────────────────┐          ┌──────────────────┐                  │
│           │  LOG_ONLY      │          │  CLAUDE_ASSISTED │                  │
│           │  (JSON files)  │          │  (API calls)     │                  │
│           └────────────────┘          └────────┬─────────┘                  │
│                                                │                             │
│                                                ▼                             │
│                                    ┌──────────────────────┐                  │
│                                    │  LlmAssistant        │                  │
│                                    │  GenServer           │                  │
│                                    │  • Analyze packets   │                  │
│                                    │  • Generate stubs    │                  │
│                                    │  • Search patterns   │                  │
│                                    └──────────────────────┘                  │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

## Configuration

```elixir
# config/dev.exs
config :bezgelor_dev,
  # Master switch: :disabled | :logging | :interactive
  mode: :interactive,

  # Interactive sub-mode: :log_only | :llm_assisted
  interactive_mode: :llm_assisted,

  # Claude API settings (only used when interactive_mode: :llm_assisted)
  claude_api_key: System.get_env("ANTHROPIC_API_KEY"),
  claude_model: "claude-sonnet-4-20250514",

  # Capture settings
  packet_history_size: 20,
  capture_directory: "priv/dev_captures",

  # Auto-generate stubs when Claude suggests them
  auto_generate_stubs: false

# config/prod.exs
config :bezgelor_dev,
  mode: :disabled  # Always disabled in production
```

## Module Structure

### New Umbrella App: `bezgelor_dev`

```
apps/bezgelor_dev/
├── lib/
│   ├── bezgelor_dev.ex              # Main module, mode checks
│   ├── bezgelor_dev/
│   │   ├── application.ex           # OTP Application
│   │   ├── hooks.ex                 # Compile-time macros for Connection.ex
│   │   ├── dev_capture.ex           # GenServer for capture/context
│   │   ├── llm_assistant.ex         # LLM prompt generation
│   │   ├── interactive_prompt.ex    # Terminal UI for player input
│   │   ├── report_generator.ex      # Markdown/JSON report generation
│   │   ├── stub_generator.ex        # Auto-generate packet/handler stubs
│   │   └── packet_context.ex        # Context struct definition
│   └── mix.exs
├── priv/
│   └── dev_captures/                # Captured packet reports
└── test/
```

## Key Components

### 1. BezgelorDev.Hooks (Compile-time Macros)

Zero-overhead hooks that compile to no-ops when disabled:

```elixir
defmodule BezgelorDev.Hooks do
  @moduledoc """
  Compile-time hooks for development capture.

  These macros expand to no-ops when dev mode is disabled,
  ensuring zero runtime overhead in production.
  """

  defmacro on_unknown_opcode(opcode_int, payload, state) do
    if dev_mode_enabled?() do
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

  defmacro on_unhandled_opcode(opcode_atom, payload, state) do
    if dev_mode_enabled?() do
      quote do
        BezgelorDev.DevCapture.capture_unhandled_opcode(
          unquote(opcode_atom),
          unquote(payload),
          unquote(state)
        )
      end
    else
      quote do: :ok
    end
  end

  defmacro on_handler_error(opcode_atom, payload, error, state) do
    if dev_mode_enabled?() do
      quote do
        BezgelorDev.DevCapture.capture_handler_error(
          unquote(opcode_atom),
          unquote(payload),
          unquote(error),
          unquote(state)
        )
      end
    else
      quote do: :ok
    end
  end

  defmacro track_packet(direction, opcode, payload, state) do
    if dev_mode_enabled?() do
      quote do
        BezgelorDev.DevCapture.track_packet(
          unquote(direction),
          unquote(opcode),
          unquote(payload),
          unquote(state)
        )
      end
    else
      quote do: :ok
    end
  end

  defp dev_mode_enabled? do
    Application.compile_env(:bezgelor_dev, :mode, :disabled) != :disabled
  end
end
```

### 2. BezgelorDev.DevCapture (GenServer)

Central capture and context management:

```elixir
defmodule BezgelorDev.DevCapture do
  use GenServer

  @type capture_event :: %{
    type: :unknown_opcode | :unhandled_opcode | :handler_error,
    timestamp: DateTime.t(),
    opcode: integer() | atom(),
    payload: binary(),
    payload_hex: String.t(),
    context: PacketContext.t(),
    player_commentary: String.t() | nil,
    llm_analysis: map() | nil
  }

  # Public API
  def capture_unknown_opcode(opcode_int, payload, conn_state)
  def capture_unhandled_opcode(opcode_atom, payload, conn_state)
  def capture_handler_error(opcode_atom, payload, error, conn_state)
  def track_packet(direction, opcode, payload, conn_state)
  def get_recent_packets(connection_id, count \\ 20)
  def get_pending_captures()
  def export_captures(format \\ :markdown)
end
```

### 3. BezgelorDev.PacketContext

Rich context captured with each event:

```elixir
defmodule BezgelorDev.PacketContext do
  @type t :: %__MODULE__{
    connection_id: String.t(),
    connection_type: :auth | :realm | :world,
    timestamp: DateTime.t(),

    # Player state (if available)
    player_id: integer() | nil,
    player_name: String.t() | nil,
    player_position: {float(), float(), float()} | nil,
    player_zone_id: integer() | nil,
    player_zone_name: String.t() | nil,

    # Session state
    session_state: atom(),
    in_world: boolean(),

    # Recent packet history
    recent_packets: [packet_record()],

    # Timing
    last_packet_received_at: DateTime.t() | nil,
    last_packet_sent_at: DateTime.t() | nil
  }

  @type packet_record :: %{
    direction: :inbound | :outbound,
    opcode: atom() | integer(),
    opcode_name: String.t(),
    size: integer(),
    timestamp: DateTime.t(),
    time_ago_ms: integer()
  }
end
```

### 4. BezgelorDev.InteractivePrompt

Terminal UI for player commentary:

```elixir
defmodule BezgelorDev.InteractivePrompt do
  @moduledoc """
  Interactive terminal prompt for capturing player context.

  When an unknown packet is captured in interactive mode,
  this module displays packet info and prompts the player
  for what they were doing.
  """

  def prompt_for_context(capture_event) do
    # Display formatted packet info
    display_capture_header(capture_event)
    display_packet_data(capture_event)
    display_recent_context(capture_event)

    # Prompt for player input
    commentary = prompt_player_commentary()

    # Show action menu
    action = prompt_action_menu()

    {commentary, action}
  end

  defp display_capture_header(event) do
    IO.puts """

    ═══════════════════════════════════════════════════════════════
      #{capture_type_label(event.type)} DETECTED
    ═══════════════════════════════════════════════════════════════
    """
  end

  defp prompt_player_commentary do
    IO.puts "───────────────────────────────────────────────────────────────"
    IO.gets("  What were you doing when this happened?\n  > ")
    |> String.trim()
  end

  defp prompt_action_menu do
    IO.puts """
    ───────────────────────────────────────────────────────────────
      [A]nalyze with Claude  [L]og for later  [S]kip  [Q]uit dev mode
    """

    case IO.gets("  > ") |> String.trim() |> String.downcase() do
      "a" -> :analyze
      "l" -> :log
      "s" -> :skip
      "q" -> :quit
      _ -> :log  # Default to logging
    end
  end
end
```

### 5. BezgelorDev.LlmAssistant

LLM prompt generation for analysis:

```elixir
defmodule BezgelorDev.LlmAssistant do
  @moduledoc """
  Generates LLM-ready prompts for packet analysis.

  Creates rich analysis prompts that can be fed into any LLM
  for offline packet analysis and reverse engineering.
  """

  # Public API
  def analyze_packet(capture_event)
  def suggest_opcode_name(opcode_int, payload, context)
  def generate_packet_struct(opcode_name, payload, context)
  def generate_handler_stub(opcode_name, packet_struct)
  def search_nexusforever_patterns(opcode_int)

  # Analysis prompt template
  defp build_analysis_prompt(capture_event) do
    """
    You are analyzing an unknown WildStar game protocol packet for the Bezgelor server emulator.

    ## Packet Data
    - Opcode: 0x#{Integer.to_string(capture_event.opcode, 16)} (#{capture_event.opcode} decimal)
    - Size: #{byte_size(capture_event.payload)} bytes
    - Raw hex: #{capture_event.payload_hex}

    ## Player Context
    #{format_player_context(capture_event.context)}

    ## Recent Packets
    #{format_recent_packets(capture_event.context.recent_packets)}

    ## Player Description
    "#{capture_event.player_commentary}"

    ## Your Task
    Based on this information:
    1. Suggest a descriptive opcode name (e.g., ClientInventoryMove, ClientQuestAccept)
    2. Analyze the byte structure - identify likely fields (uint32, uint16, strings, etc.)
    3. Provide confidence level (high/medium/low) with reasoning
    4. If possible, reference similar patterns from NexusForever or WildStar documentation

    Respond in JSON format:
    {
      "suggested_name": "ClientSomething",
      "confidence": "medium",
      "reasoning": "...",
      "field_analysis": [
        {"offset": 0, "size": 4, "type": "uint32", "likely_meaning": "item_id"},
        ...
      ],
      "nexusforever_reference": "Similar to ClientItemMove in NexusForever" | null
    }
    """
  end
end
```

### 6. BezgelorDev.StubGenerator

Auto-generate code from Claude analysis:

```elixir
defmodule BezgelorDev.StubGenerator do
  @moduledoc """
  Generates stub code for new packets and handlers.
  """

  def generate_opcode_entry(opcode_int, suggested_name) do
    atom_name = Macro.underscore(suggested_name) |> String.to_atom()

    """
    # Add to @opcode_map in opcode.ex:
    #{atom_name}: 0x#{Integer.to_string(opcode_int, 16)},

    # Add to @names:
    #{atom_name}: "#{suggested_name}",
    """
  end

  def generate_packet_struct(suggested_name, field_analysis) do
    module_name = "BezgelorProtocol.Packets.#{suggested_name}"
    fields = Enum.map(field_analysis, &field_to_struct_field/1)

    """
    defmodule #{module_name} do
      @moduledoc \"\"\"
      #{suggested_name} packet.

      Auto-generated stub - needs verification.
      \"\"\"

      defstruct #{inspect(fields)}

      @behaviour BezgelorProtocol.Readable

      @impl true
      def read(reader) do
        # TODO: Implement based on field analysis
        {:ok, %__MODULE__{}}
      end
    end
    """
  end

  def generate_handler_stub(suggested_name) do
    handler_name = String.replace(suggested_name, ~r/^Client/, "") <> "Handler"

    """
    defmodule BezgelorProtocol.Handler.#{handler_name} do
      @moduledoc \"\"\"
      Handler for #{suggested_name}.

      Auto-generated stub - needs implementation.
      \"\"\"

      @behaviour BezgelorProtocol.Handler

      alias BezgelorProtocol.PacketReader

      @impl true
      def handle(payload, state) do
        reader = PacketReader.new(payload)

        # TODO: Parse packet and implement logic

        {:ok, state}
      end
    end
    """
  end
end
```

### 7. BezgelorDev.ReportGenerator

Generate reports for later analysis:

```elixir
defmodule BezgelorDev.ReportGenerator do
  @moduledoc """
  Generates markdown and JSON reports for captured packets.
  """

  def generate_markdown_report(capture_event) do
    """
    # Unknown Packet Report: 0x#{Integer.to_string(capture_event.opcode, 16)}

    ## Capture Details
    - **Timestamp**: #{DateTime.to_iso8601(capture_event.timestamp)}
    - **Type**: #{capture_event.type}
    - **Connection**: #{capture_event.context.connection_type}

    ## Packet Data
    - **Opcode**: 0x#{Integer.to_string(capture_event.opcode, 16)} (#{capture_event.opcode} decimal)
    - **Size**: #{byte_size(capture_event.payload)} bytes
    - **Direction**: Client → Server

    ### Raw Bytes (hex)
    ```
    #{format_hex_dump(capture_event.payload)}
    ```

    ## Context
    ### Player State
    #{format_player_state(capture_event.context)}

    ### Recent Packets
    #{format_recent_packets_table(capture_event.context.recent_packets)}

    ## Player Description
    > "#{capture_event.player_commentary || "No description provided"}"

    #{format_llm_analysis(capture_event.llm_analysis)}
    """
  end

  def generate_json_report(capture_event) do
    %{
      opcode: capture_event.opcode,
      opcode_hex: "0x" <> Integer.to_string(capture_event.opcode, 16),
      type: capture_event.type,
      timestamp: DateTime.to_iso8601(capture_event.timestamp),
      payload_hex: capture_event.payload_hex,
      payload_base64: Base.encode64(capture_event.payload),
      context: serialize_context(capture_event.context),
      player_commentary: capture_event.player_commentary,
      llm_analysis: capture_event.llm_analysis
    }
    |> Jason.encode!(pretty: true)
  end
end
```

## Connection.ex Integration

Minimal changes to Connection.ex using the hooks:

```elixir
defmodule BezgelorProtocol.Connection do
  # Add at top of module
  require BezgelorDev.Hooks
  alias BezgelorDev.Hooks

  # ... existing code ...

  defp handle_packet(opcode, payload, state) do
    alias BezgelorProtocol.PacketRegistry

    case Opcode.from_integer(opcode) do
      {:ok, opcode_atom} ->
        # Track received packet for context
        Hooks.track_packet(:inbound, opcode_atom, payload, state)

        Logger.debug("Received packet: #{Opcode.name(opcode_atom)} (#{byte_size(payload)} bytes)")
        dispatch_to_handler(opcode_atom, payload, state)

      {:error, :unknown_opcode} ->
        Logger.warning("Unknown opcode: 0x#{Integer.to_string(opcode, 16)}")

        # Dev capture hook - compiles to :ok when disabled
        Hooks.on_unknown_opcode(opcode, payload, state)

        {:ok, state}
    end
  end

  defp dispatch_to_handler(opcode_atom, payload, state) do
    alias BezgelorProtocol.PacketRegistry

    case PacketRegistry.lookup(opcode_atom) do
      nil ->
        Logger.debug("No handler registered for #{Opcode.name(opcode_atom)}")

        # Dev capture hook - compiles to :ok when disabled
        Hooks.on_unhandled_opcode(opcode_atom, payload, state)

        {:ok, state}

      handler ->
        case handler.handle(payload, state) do
          {:ok, new_state} ->
            {:ok, new_state}

          {:reply, reply_opcode, reply_payload, new_state} ->
            # Track sent packet for context
            Hooks.track_packet(:outbound, reply_opcode, reply_payload, new_state)

            do_send_packet(%{state | session_data: new_state.session_data}, reply_opcode, reply_payload)
            {:ok, new_state}

          {:error, reason} = error ->
            Logger.warning("Handler error for #{Opcode.name(opcode_atom)}: #{inspect(reason)}")

            # Dev capture hook - compiles to :ok when disabled
            Hooks.on_handler_error(opcode_atom, payload, reason, state)

            error
        end
    end
  end
end
```

## Interactive Mode Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                    INTERACTIVE MODE FLOW                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  1. Unknown packet arrives                                       │
│     │                                                            │
│     ▼                                                            │
│  2. DevCapture captures context                                  │
│     │                                                            │
│     ▼                                                            │
│  3. InteractivePrompt displays info:                            │
│     ┌─────────────────────────────────────────────────────┐     │
│     │ ═══════════════════════════════════════════════════ │     │
│     │   UNKNOWN PACKET DETECTED                           │     │
│     │ ═══════════════════════════════════════════════════ │     │
│     │   Opcode: 0x0847 (2119 decimal)                     │     │
│     │   Size: 24 bytes                                    │     │
│     │   Raw: 47 08 18 00 00 00 01 00 00 00 FF FF...       │     │
│     │                                                     │     │
│     │   Recent context:                                   │     │
│     │   • Last sent: ServerEntityCreate (1.2s ago)        │     │
│     │   • Last received: ClientMovement (0.3s ago)        │     │
│     │   • Zone: Thayd (ID: 6)                             │     │
│     │   • Position: (2847.3, 103.2, -892.1)               │     │
│     │ ─────────────────────────────────────────────────── │     │
│     │   What were you doing when this happened?           │     │
│     │   > I opened my inventory and clicked an item_      │     │
│     │ ─────────────────────────────────────────────────── │     │
│     │   [A]nalyze with Claude  [L]og  [S]kip  [Q]uit      │     │
│     └─────────────────────────────────────────────────────┘     │
│     │                                                            │
│     ├─── User presses 'A' ───┐                                  │
│     │                         │                                  │
│     ▼                         ▼                                  │
│  4a. LOG_ONLY mode:        4b. LLM_ASSISTED mode:               │
│      Save to JSON file         Send to LlmAssistant              │
│      Continue playing          │                                 │
│                                ▼                                 │
│                             5. Claude analyzes packet            │
│                                │                                 │
│                                ▼                                 │
│                             6. Display analysis:                 │
│     ┌─────────────────────────────────────────────────────┐     │
│     │ ═══════════════════════════════════════════════════ │     │
│     │   CLAUDE ANALYSIS                                   │     │
│     │ ═══════════════════════════════════════════════════ │     │
│     │   Suggested name: ClientInventoryUseItem            │     │
│     │   Confidence: HIGH                                  │     │
│     │                                                     │     │
│     │   Field analysis:                                   │     │
│     │   • Offset 0-3: uint32 - likely item_id             │     │
│     │   • Offset 4-7: uint32 - likely inventory_slot      │     │
│     │   • Offset 8-11: uint32 - likely target_id          │     │
│     │                                                     │     │
│     │   Reference: Similar to ClientItemUse in NexusForever│    │
│     │ ─────────────────────────────────────────────────── │     │
│     │   [G]enerate stubs  [S]ave report  [C]ontinue       │     │
│     └─────────────────────────────────────────────────────┘     │
│                                │                                 │
│                                ▼                                 │
│                             7. Optional: Generate stubs          │
│                                │                                 │
│                                ▼                                 │
│                             8. Save report, continue playing     │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## File Output Structure

```
priv/dev_captures/
├── sessions/
│   └── 2025-12-11_14-32-18/
│       ├── session_info.json
│       ├── captures/
│       │   ├── 001_0x0847_unknown.md
│       │   ├── 001_0x0847_unknown.json
│       │   ├── 002_0x0923_unhandled.md
│       │   └── 002_0x0923_unhandled.json
│       └── generated_stubs/
│           ├── client_inventory_use_item.ex
│           └── inventory_use_item_handler.ex
├── reports/
│   └── summary_2025-12-11.md
└── pending_analysis/
    └── batch_2025-12-11.json
```

## Dependencies

Add to `apps/bezgelor_dev/mix.exs`:

```elixir
defp deps do
  [
    {:anthropic, "~> 0.4.0", hex: :anthropic_community},
    {:jason, "~> 1.4"},
    # For colored terminal output
    {:io_ansi_table, "~> 1.0", only: :dev}
  ]
end
```

## Implementation Order

1. **Create bezgelor_dev umbrella app** with basic structure
2. **Implement Hooks module** with compile-time macros
3. **Implement DevCapture GenServer** for context tracking
4. **Implement PacketContext** struct
5. **Implement InteractivePrompt** terminal UI
6. **Implement ReportGenerator** for file output
7. **Modify Connection.ex** to use hooks
8. **Implement LlmAssistant** module
9. **Implement StubGenerator** for code generation
10. **Add configuration and documentation**
11. **Write tests**

## Testing Strategy

- Unit tests for each module
- Integration tests with mock Claude API responses
- Test compile-time elimination in production config
- Test interactive prompt with simulated input

## Future Enhancements

1. **Web UI** - Phoenix LiveView dashboard for viewing captures
2. **Batch analysis** - Send multiple captures to Claude at once
3. **Pattern learning** - Track which opcodes appear together
4. **Auto-implementation** - Claude generates complete implementations
5. **NexusForever integration** - Direct search of NexusForever C# code
