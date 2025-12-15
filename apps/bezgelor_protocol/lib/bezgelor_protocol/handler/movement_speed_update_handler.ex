defmodule BezgelorProtocol.Handler.MovementSpeedUpdateHandler do
  @moduledoc """
  Handles ClientPlayerMovementSpeedUpdate packets (opcode 0x063B).

  Sent by the client when movement speed changes (mounting, buffs, etc.).
  Includes anti-cheat validation to detect speed hacking.

  ## Speed Bounds

  The server validates that reported speeds fall within acceptable ranges:

  | Movement Type | Max Speed (units/sec) |
  |---------------|----------------------|
  | Walking       | 5.0                  |
  | Running       | 10.0                 |
  | Sprinting     | 15.0                 |
  | Mounted       | 25.0                 |
  | Buffed        | 35.0 (absolute max)  |

  ## Violation Handling

  Speed violations are logged and tracked per-session. Repeated violations
  (>3 in 60 seconds) trigger a warning that can be used for moderation.
  """

  @behaviour BezgelorProtocol.Handler

  alias BezgelorProtocol.PacketReader

  require Logger

  # Maximum allowed speeds (units per second)
  # These include reasonable margins for lag/interpolation
  # Walking/running/sprinting thresholds reserved for future granular validation
  @max_mounted_speed 25.0
  @absolute_max_speed 35.0

  # Anti-cheat: max violations before flagging
  @violation_threshold 3
  @violation_window_ms 60_000

  @impl true
  def handle(payload, state) do
    case parse_speed_update(payload) do
      {:ok, speed_value} ->
        validate_and_process(speed_value, payload, state)

      {:error, :insufficient_data} ->
        Logger.debug("[MovementSpeedUpdate] Packet too small (#{byte_size(payload)} bytes)")
        {:ok, state}
    end
  end

  # Parse the speed value from the packet
  # Based on typical WildStar packet patterns, speed is likely a float32
  defp parse_speed_update(payload) when byte_size(payload) >= 4 do
    reader = PacketReader.new(payload)

    case PacketReader.read_float32(reader) do
      {:ok, speed, _reader} -> {:ok, speed}
      {:error, _} -> {:error, :insufficient_data}
    end
  end

  defp parse_speed_update(_payload), do: {:error, :insufficient_data}

  # Validate speed and update state
  defp validate_and_process(speed, _payload, state) do
    character_name = state.session_data[:character_name] || "unknown"
    account_id = state.session_data[:account_id] || 0

    cond do
      # Invalid speed value (NaN, negative, or zero)
      not is_number(speed) or speed < 0.0 ->
        Logger.warning(
          "[AntiCheat] Invalid speed value: #{inspect(speed)}, " <>
            "account=#{account_id}, char=#{character_name}"
        )

        record_violation(state)

      # Speed exceeds absolute maximum (clear cheat)
      speed > @absolute_max_speed ->
        Logger.warning(
          "[AntiCheat] Speed hack detected: #{Float.round(speed, 2)} exceeds max #{@absolute_max_speed}, " <>
            "account=#{account_id}, char=#{character_name}"
        )

        record_violation(state)

      # Speed is suspiciously high (could be legitimate with buffs)
      speed > @max_mounted_speed ->
        Logger.info(
          "[AntiCheat] High speed: #{Float.round(speed, 2)}, " <>
            "account=#{account_id}, char=#{character_name} (may be legitimate with buffs)"
        )

        {:ok, state}

      # Normal speed range
      true ->
        Logger.debug(
          "[MovementSpeedUpdate] speed=#{Float.round(speed, 2)}, char=#{character_name}"
        )

        {:ok, state}
    end
  end

  # Record a speed violation and check if threshold exceeded
  defp record_violation(state) do
    now = System.monotonic_time(:millisecond)

    # Get existing violations, filtering out old ones
    violations =
      (state.session_data[:speed_violations] || [])
      |> Enum.filter(fn timestamp -> now - timestamp < @violation_window_ms end)

    # Add new violation
    violations = [now | violations]
    state = put_in(state.session_data[:speed_violations], violations)

    # Check if threshold exceeded
    if length(violations) >= @violation_threshold do
      account_id = state.session_data[:account_id] || 0
      character_name = state.session_data[:character_name] || "unknown"

      Logger.warning(
        "[AntiCheat] ALERT: #{length(violations)} speed violations in #{@violation_window_ms}ms, " <>
          "account=#{account_id}, char=#{character_name}"
      )

      # Could add: kick player, flag account, notify admins
      # For now, just log the alert for manual review
    end

    {:ok, state}
  end
end
