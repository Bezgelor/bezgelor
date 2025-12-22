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

  ### 0x00E3
  - Falls between ServerDatacubeVolumeUpdate (0xE2) and ClientResurrectRequest (0xE4)
  - Not present in NexusForever opcode list (gap in enum)
  - Trigger conditions unknown - log for investigation

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

defmodule BezgelorProtocol.Handler.Unknown0x00E3Handler do
  @moduledoc """
  Handler for unknown opcode 0x00E3.

  This opcode falls between ServerDatacubeVolumeUpdate (0xE2) and
  ClientResurrectRequest (0xE4). Purpose unknown - logging for investigation.
  """
  @behaviour BezgelorProtocol.Handler
  require Logger

  @impl true
  def handle(payload, state) do
    payload_hex = if byte_size(payload) > 0, do: Base.encode16(payload), else: "(empty)"
    Logger.info("[Unknown:0x00E3] Received #{byte_size(payload)} bytes: #{payload_hex}")
    {:ok, state}
  end
end

defmodule BezgelorProtocol.Handler.P2PTradingCancelHandler do
  @moduledoc """
  Handler for ClientP2PTradingCancelTrade (0x018F).

  Player-to-player trading is not yet implemented. When implementing, the following
  telemetry should be added to track trade activity:

  ## Telemetry Integration Points

  ### Trade Completion (when both players commit)
  When a trade is successfully completed, emit telemetry using:

      alias BezgelorCore.Economy.TelemetryEvents

      TelemetryEvents.emit_trade_complete(
        items_exchanged: total_items_count,
        currency_exchanged: total_currency_amount,
        initiator_id: initiator_character_id,
        acceptor_id: acceptor_character_id,
        duration_ms: trade_duration_ms
      )

  Where:
  - `items_exchanged`: Total number of items exchanged (items from both players)
  - `currency_exchanged`: Total currency exchanged (sum from both players)
  - `initiator_id`: Character ID of player who initiated the trade
  - `acceptor_id`: Character ID of player who accepted the trade invite
  - `duration_ms`: Time from trade initiation to completion in milliseconds

  ### Related Packets to Implement

  Client packets:
  - ClientP2PTradingInitiateTrade - Start trade with target player
  - ClientP2PTradingAcceptInvite - Accept trade invitation
  - ClientP2PTradingDeclineInvite - Decline trade invitation
  - ClientP2PTradingAddItem - Add item to trade window
  - ClientP2PTradingRemoveItem - Remove item from trade window
  - ClientP2PTradingSetMoney - Set currency amount to trade
  - ClientP2PTradingCommit - Commit to trade (ready to complete)
  - ClientP2PTradingCancelTrade - Cancel ongoing trade (this handler)

  Server packets:
  - ServerP2PTradeInvite - Send trade invitation to target
  - ServerP2PTradeUpdateItem - Update items in trade window
  - ServerP2PTradeUpdateMoney - Update currency in trade window
  - ServerP2PTradeItemRemoved - Notify item removed from trade
  - ServerP2PTradeResult - Send trade completion result

  ## Implementation Notes

  Trade flow:
  1. Player A initiates trade with Player B
  2. Player B accepts or declines
  3. Both players add items and set currency amounts
  4. Both players commit when ready
  5. Trade completes or is cancelled
  6. On completion, emit telemetry event
  """
  @behaviour BezgelorProtocol.Handler
  require Logger

  @impl true
  def handle(_payload, state) do
    # Player is canceling a P2P trade - currently not implemented
    Logger.debug("[P2PTrading] Trade cancel request (trading not implemented)")

    # TODO: When implementing P2P trading, track cancellations separately from completions
    # TODO: Consider adding telemetry for trade cancellations to monitor player behavior
    # TODO: Validate that a trade session exists before processing cancel

    {:ok, state}
  end
end
