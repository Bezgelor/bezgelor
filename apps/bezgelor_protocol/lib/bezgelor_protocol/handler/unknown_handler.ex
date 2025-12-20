defmodule BezgelorProtocol.Handler.UnknownHandler do
  @moduledoc """
  Handles unknown/undocumented opcodes.

  This handler is used for opcodes that are not documented in NexusForever
  but are observed being sent by the client. Each opcode is logged for
  future investigation.

  ## Known Unknown Opcodes

  ### 0x0269
  - Sent immediately after world entry
  - Purpose unknown
  - Not present in NexusForever source
  - Payload appears to be 4 bytes

  ### 0x07CC
  - Sent periodically during gameplay
  - Might be related to client state/heartbeat
  - Not present in NexusForever source
  - Payload appears to be 6 bytes

  ### 0x00D5
  - Related to ServerInstanceSettings (per NexusForever comments)
  - Sent after receiving instance settings
  - Purpose unknown

  ### 0x00FB
  - Observed during gameplay
  - Might be path-related (near path opcodes in enum)
  - Purpose unknown

  ## Investigation Notes

  To investigate these opcodes:
  1. Capture full packet payloads when logged
  2. Correlate with client actions (UI, movement, etc.)
  3. Check WildStar client disassembly for handlers
  4. Compare with other private server implementations
  """

  @behaviour BezgelorProtocol.Handler

  require Logger

  @doc """
  Factory function to create a handler for a specific unknown opcode.
  """
  def for_opcode(opcode_hex) do
    fn payload, state ->
      handle_unknown(opcode_hex, payload, state)
    end
  end

  @impl true
  def handle(payload, state) do
    handle_unknown("unknown", payload, state)
  end

  defp handle_unknown(opcode_hex, payload, state) do
    # Log the unknown packet for investigation
    payload_hex =
      if byte_size(payload) > 0 do
        Base.encode16(payload)
      else
        "(empty)"
      end

    Logger.debug("[Unknown:0x#{opcode_hex}] Received #{byte_size(payload)} bytes: #{payload_hex}")

    # Don't error - just acknowledge and continue
    {:ok, state}
  end
end

# Specific handlers for each unknown opcode
defmodule BezgelorProtocol.Handler.Unknown0x0269Handler do
  @moduledoc "Handler for unknown opcode 0x0269"
  @behaviour BezgelorProtocol.Handler
  require Logger

  @impl true
  def handle(payload, state) do
    Logger.debug("[Unknown:0x0269] Received #{byte_size(payload)} bytes after world entry")
    {:ok, state}
  end
end

defmodule BezgelorProtocol.Handler.Unknown0x07CCHandler do
  @moduledoc "Handler for unknown opcode 0x07CC"
  @behaviour BezgelorProtocol.Handler
  require Logger

  @impl true
  def handle(payload, state) do
    # This is sent frequently, so only log at debug level
    if byte_size(payload) > 0 do
      Logger.debug("[Unknown:0x07CC] Periodic packet (#{byte_size(payload)} bytes)")
    end

    {:ok, state}
  end
end

defmodule BezgelorProtocol.Handler.Unknown0x00D5Handler do
  @moduledoc "Handler for unknown opcode 0x00D5 (related to instance settings)"
  @behaviour BezgelorProtocol.Handler
  require Logger

  @impl true
  def handle(payload, state) do
    Logger.debug("[Unknown:0x00D5] Instance settings related (#{byte_size(payload)} bytes)")
    {:ok, state}
  end
end

defmodule BezgelorProtocol.Handler.Unknown0x00FBHandler do
  @moduledoc "Handler for unknown opcode 0x00FB"
  @behaviour BezgelorProtocol.Handler
  require Logger

  @impl true
  def handle(payload, state) do
    Logger.debug("[Unknown:0x00FB] Received #{byte_size(payload)} bytes")
    {:ok, state}
  end
end

defmodule BezgelorProtocol.Handler.Unknown0x0635Handler do
  @moduledoc "Handler for unknown opcode 0x0635 (labeled Server0635 in NexusForever)"
  @behaviour BezgelorProtocol.Handler
  require Logger

  @impl true
  def handle(payload, state) do
    Logger.debug("[Unknown:0x0635] Received #{byte_size(payload)} bytes")
    {:ok, state}
  end
end

defmodule BezgelorProtocol.Handler.Unknown0x00DEHandler do
  @moduledoc "Handler for unknown opcode 0x00DE (possibly dash/sprint related)"
  @behaviour BezgelorProtocol.Handler
  require Logger

  @impl true
  def handle(payload, state) do
    payload_hex = if byte_size(payload) > 0, do: Base.encode16(payload), else: "(empty)"
    Logger.debug("[Unknown:0x00DE] Received #{byte_size(payload)} bytes: #{payload_hex}")
    {:ok, state}
  end
end

defmodule BezgelorProtocol.Handler.P2PTradingCancelHandler do
  @moduledoc "Handler for ClientP2PTradingCancelTrade (0x018F)"
  @behaviour BezgelorProtocol.Handler
  require Logger

  @impl true
  def handle(_payload, state) do
    # Player is canceling a P2P trade - currently not implemented
    Logger.debug("[P2PTrading] Trade cancel request (trading not implemented)")
    {:ok, state}
  end
end
