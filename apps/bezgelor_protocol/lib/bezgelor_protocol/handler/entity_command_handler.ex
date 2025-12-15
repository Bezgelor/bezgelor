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
  alias BezgelorWorld.VisibilityBroadcaster

  require Logger

  @impl true
  def handle(payload, state) do
    reader = PacketReader.new(payload)

    with {:ok, time, reader} <- PacketReader.read_uint32(reader),
         {:ok, command_count, reader} <- PacketReader.read_uint32(reader) do
      if command_count > 0 do
        Logger.debug(
          "[EntityCommand] Received #{command_count} commands at time #{time}"
        )

        # Parse commands for debugging (simplified - doesn't handle all command types)
        _commands = parse_commands(reader, command_count)
      end

      # Broadcast movement to other players in zone
      broadcast_movement(payload, state)

      # Position persistence handled by:
      # - MovementHandler: periodic saves every 5 seconds
      # - Connection.terminate: save on logout/disconnect
      # Anti-cheat: MovementSpeedUpdateHandler validates speed bounds

      {:ok, state}
    else
      {:error, reason} ->
        Logger.warning("[EntityCommand] Failed to parse: #{inspect(reason)}")
        {:ok, state}
    end
  end

  # Broadcast player movement to other players in the same zone
  defp broadcast_movement(payload, state) do
    entity_guid = state.session_data[:entity_guid]
    zone_id = state.session_data[:zone_id]
    instance_id = state.session_data[:instance_id] || 1

    if entity_guid && zone_id do
      # Build a server entity command packet from the client data
      # The format is similar - we just need to prepend the entity GUID
      # Client sends: time(4) + count(4) + commands
      # Server sends: guid(4) + time(4) + flags(1 bit) + server_controlled(1 bit) + count(5 bits) + commands

      # For simplicity, we relay the raw client movement data with the entity GUID prepended
      # This works because ServerEntityCommand has a similar structure
      movement_packet = build_server_entity_command(entity_guid, payload)

      VisibilityBroadcaster.broadcast_player_movement(entity_guid, movement_packet, zone_id, instance_id)
    end
  end

  # Build a ServerEntityCommand packet from client movement data
  defp build_server_entity_command(entity_guid, client_payload) do
    alias BezgelorProtocol.PacketWriter

    # Parse client payload to extract time and commands
    reader = PacketReader.new(client_payload)

    case PacketReader.read_uint32(reader) do
      {:ok, time, reader} ->
        case PacketReader.read_uint32(reader) do
          {:ok, command_count, _reader} ->
            # Get remaining bytes for commands (after time and count)
            commands_start = 8
            commands_data = binary_part(client_payload, commands_start, byte_size(client_payload) - commands_start)

            # Build server packet
            writer =
              PacketWriter.new()
              |> PacketWriter.write_uint32(entity_guid)
              |> PacketWriter.write_uint32(time)
              |> PacketWriter.write_bits(0, 1)  # time_reset = false
              |> PacketWriter.write_bits(0, 1)  # server_controlled = false
              |> PacketWriter.write_bits(command_count, 5)

            # The command data format is the same between client and server
            # so we can append the raw command bytes
            writer = PacketWriter.flush_bits(writer)
            PacketWriter.to_binary(writer) <> commands_data

          _ ->
            # Fallback: just prepend guid to original payload
            <<entity_guid::little-32>> <> client_payload
        end

      _ ->
        # Fallback: just prepend guid to original payload
        <<entity_guid::little-32>> <> client_payload
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
