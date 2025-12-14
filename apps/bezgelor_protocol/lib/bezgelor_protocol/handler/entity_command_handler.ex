defmodule BezgelorProtocol.Handler.EntityCommandHandler do
  @moduledoc """
  Handles ClientEntityCommand packets (opcode 0x0637).

  This is the primary movement packet sent by the client. It contains
  a list of entity commands that describe movement, rotation, and state changes.

  ## Packet Structure (from NexusForever)

  - Time: uint32 - client timestamp
  - CommandCount: uint32 - number of commands
  - Commands: list of EntityCommand structures
    - Command: 5 bits - EntityCommand enum value
    - Model: variable - command-specific data

  ## EntityCommand Types

  - SetTime (0): Time synchronization
  - SetPlatform (1): Platform attachment
  - SetPosition (2): Position update
  - SetPositionKeys (3): Position keyframes
  - SetPositionPath (4): Path following
  - SetPositionSpline (5): Spline movement
  - SetPositionMultiSpline (6): Multi-spline movement
  - SetPositionProjectile (7): Projectile movement
  - SetVelocity (8): Velocity update
  - SetVelocityKeys (9): Velocity keyframes
  - SetVelocityDefaults (10): Reset velocity
  - SetMove (11): Movement state
  - SetMoveKeys (12): Movement keyframes
  - SetMoveDefaults (13): Reset movement
  - SetRotation (14): Rotation update
  - SetRotationKeys (15): Rotation keyframes
  - SetRotationSpline (16): Rotation spline
  - SetRotationMultiSpline (17): Multi-spline rotation
  - SetRotationFaceUnit (18): Face target unit
  - SetRotationFacePosition (19): Face position
  - SetRotationSpin (20): Spin rotation
  - SetRotationDefaults (21): Reset rotation
  - SetScale (22): Scale update
  - SetScaleKeys (23): Scale keyframes
  - SetState (24): State update
  - SetStateKeys (25): State keyframes
  - SetStateDefault (26): Reset state
  - SetMode (27): Mode update
  - SetModeKeys (28): Mode keyframes
  """

  @behaviour BezgelorProtocol.Handler

  alias BezgelorProtocol.PacketReader

  require Logger

  @impl true
  def handle(payload, state) do
    reader = PacketReader.new(payload)

    with {:ok, time, reader} <- PacketReader.read_uint32(reader),
         {:ok, command_count, reader} <- PacketReader.read_uint32(reader) do
      # For now, we just acknowledge the commands without processing them
      # Full implementation would parse each command and update entity position

      if command_count > 0 do
        Logger.debug(
          "[EntityCommand] Received #{command_count} commands at time #{time}"
        )

        # Parse commands for debugging (simplified - doesn't handle all command types)
        _commands = parse_commands(reader, command_count)
      end

      # TODO: Broadcast position updates to other players in zone
      # TODO: Update character position in database periodically
      # TODO: Validate movement (anti-cheat)

      {:ok, state}
    else
      {:error, reason} ->
        Logger.warning("[EntityCommand] Failed to parse: #{inspect(reason)}")
        {:ok, state}
    end
  end

  defp parse_commands(_reader, 0), do: []

  defp parse_commands(reader, count) do
    # Read command type (5 bits)
    case PacketReader.read_bits(reader, 5) do
      {:ok, command_type, reader} ->
        Logger.debug("[EntityCommand] Command type: #{command_type}")

        # For now, just skip the rest - full parsing would depend on command_type
        # Each command type has a different structure
        [{command_type, nil} | parse_commands(reader, count - 1)]

      {:error, _reason} ->
        # End of data
        []
    end
  end
end
