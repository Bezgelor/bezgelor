defmodule BezgelorProtocol.Packets.World.ServerEntityCommand do
  @moduledoc """
  Server-to-client entity command packet for movement and state updates.

  This packet tells the client how an entity should move or change state.
  Used for NPC/creature movement, following, and other server-controlled
  entity behaviors.

  ## Packet Structure

  - guid: uint32 - Entity GUID
  - time: uint32 - Server timestamp
  - time_reset: 1 bit - Whether to reset client time
  - server_controlled: 1 bit - Server controls entity movement
  - command_count: 5 bits - Number of commands (max 31)
  - commands: list of EntityCommand maps

  ## Command Types

  Commands are maps with a `:type` key. Supported types:

  - `:set_position` - Instant position change
  - `:set_position_path` - Path following with waypoints
  - `:set_state` - State change (idle, moving, etc.)
  - `:set_rotation` - Rotation update
  - `:set_move` - Movement direction
  - `:set_move_defaults` - Reset movement

  ## Example

      alias BezgelorProtocol.Packets.World.ServerEntityCommand

      # Make creature walk along a path
      path = [
        {100.0, 0.0, 100.0},
        {102.0, 0.0, 102.0},
        {104.0, 0.0, 104.0}
      ]

      commands = [
        %{type: :set_state, state: 0x01},
        %{type: :set_move_defaults, blend: false},
        %{
          type: :set_position_path,
          positions: path,
          speed: 4.0,
          spline_type: :linear,
          spline_mode: :one_shot,
          offset: 0,
          blend: true
        }
      ]

      packet = %ServerEntityCommand{
        guid: creature_guid,
        time: System.monotonic_time(:millisecond) |> rem(0xFFFFFFFF),
        time_reset: false,
        server_controlled: true,
        commands: commands
      }
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  # Entity command types (5 bits) - only defining those currently in use
  @cmd_set_position 2
  @cmd_set_position_path 4
  @cmd_set_move 11
  @cmd_set_move_defaults 13
  @cmd_set_rotation 14
  @cmd_set_rotation_defaults 21
  @cmd_set_state 24

  # Spline types (2 bits)
  @spline_type_linear 0
  @spline_type_catmull_rom 1

  # Spline modes (4 bits)
  @spline_mode_one_shot 0
  @spline_mode_back_and_forth 1
  @spline_mode_cyclic 2
  @spline_mode_one_shot_reverse 3
  @spline_mode_back_and_forth_reverse 4
  @spline_mode_cyclic_reverse 5

  @type position :: {float(), float(), float()}

  @type command ::
          %{type: :set_position, position: position(), blend: boolean()}
          | %{
              type: :set_position_path,
              positions: [position()],
              speed: float(),
              spline_type: :linear | :catmull_rom,
              spline_mode:
                :one_shot
                | :back_and_forth
                | :cyclic
                | :one_shot_reverse
                | :back_and_forth_reverse
                | :cyclic_reverse,
              offset: non_neg_integer(),
              blend: boolean()
            }
          | %{type: :set_state, state: non_neg_integer()}
          | %{type: :set_rotation, rotation: position(), blend: boolean()}
          | %{type: :set_rotation_defaults, blend: boolean()}
          | %{type: :set_move, move: position(), blend: boolean()}
          | %{type: :set_move_defaults, blend: boolean()}

  @type t :: %__MODULE__{
          guid: non_neg_integer(),
          time: non_neg_integer(),
          time_reset: boolean(),
          server_controlled: boolean(),
          commands: [command()]
        }

  defstruct guid: 0,
            time: 0,
            time_reset: false,
            server_controlled: true,
            commands: []

  @impl true
  def opcode, do: :server_entity_command

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_u32(packet.guid)
      |> PacketWriter.write_u32(packet.time)
      |> PacketWriter.write_bits(bool_to_bit(packet.time_reset), 1)
      |> PacketWriter.write_bits(bool_to_bit(packet.server_controlled), 1)
      |> PacketWriter.write_bits(length(packet.commands), 5)

    writer = Enum.reduce(packet.commands, writer, &write_command/2)

    {:ok, PacketWriter.flush_bits(writer)}
  end

  defp bool_to_bit(true), do: 1
  defp bool_to_bit(false), do: 0

  # Write individual commands based on :type key
  defp write_command(%{type: :set_position} = cmd, writer) do
    writer
    |> PacketWriter.write_bits(@cmd_set_position, 5)
    |> PacketWriter.write_vector3(cmd.position)
    |> PacketWriter.write_bits(bool_to_bit(Map.get(cmd, :blend, false)), 1)
  end

  defp write_command(%{type: :set_position_path} = cmd, writer) do
    positions = Map.get(cmd, :positions, [])

    writer
    |> PacketWriter.write_bits(@cmd_set_position_path, 5)
    |> PacketWriter.write_bits(length(positions), 10)
    |> write_positions(positions)
    |> PacketWriter.write_packed_float(Map.get(cmd, :speed, 4.0))
    |> PacketWriter.write_bits(spline_type_to_int(Map.get(cmd, :spline_type, :linear)), 2)
    |> PacketWriter.write_bits(spline_mode_to_int(Map.get(cmd, :spline_mode, :one_shot)), 4)
    |> PacketWriter.write_u32(Map.get(cmd, :offset, 0))
    |> PacketWriter.write_bits(bool_to_bit(Map.get(cmd, :blend, true)), 1)
  end

  defp write_command(%{type: :set_state} = cmd, writer) do
    writer
    |> PacketWriter.write_bits(@cmd_set_state, 5)
    |> PacketWriter.write_u32(Map.get(cmd, :state, 0))
  end

  defp write_command(%{type: :set_rotation} = cmd, writer) do
    writer
    |> PacketWriter.write_bits(@cmd_set_rotation, 5)
    |> PacketWriter.write_vector3(Map.get(cmd, :rotation, {0.0, 0.0, 0.0}))
    |> PacketWriter.write_bits(bool_to_bit(Map.get(cmd, :blend, false)), 1)
  end

  defp write_command(%{type: :set_rotation_defaults} = cmd, writer) do
    writer
    |> PacketWriter.write_bits(@cmd_set_rotation_defaults, 5)
    |> PacketWriter.write_bits(bool_to_bit(Map.get(cmd, :blend, false)), 1)
  end

  defp write_command(%{type: :set_move} = cmd, writer) do
    writer
    |> PacketWriter.write_bits(@cmd_set_move, 5)
    |> PacketWriter.write_vector3(Map.get(cmd, :move, {0.0, 0.0, 0.0}))
    |> PacketWriter.write_bits(bool_to_bit(Map.get(cmd, :blend, false)), 1)
  end

  defp write_command(%{type: :set_move_defaults} = cmd, writer) do
    writer
    |> PacketWriter.write_bits(@cmd_set_move_defaults, 5)
    |> PacketWriter.write_bits(bool_to_bit(Map.get(cmd, :blend, false)), 1)
  end

  defp write_positions(writer, positions) do
    Enum.reduce(positions, writer, fn pos, w ->
      PacketWriter.write_vector3(w, pos)
    end)
  end

  defp spline_type_to_int(:linear), do: @spline_type_linear
  defp spline_type_to_int(:catmull_rom), do: @spline_type_catmull_rom
  defp spline_type_to_int(_), do: @spline_type_linear

  defp spline_mode_to_int(:one_shot), do: @spline_mode_one_shot
  defp spline_mode_to_int(:back_and_forth), do: @spline_mode_back_and_forth
  defp spline_mode_to_int(:cyclic), do: @spline_mode_cyclic
  defp spline_mode_to_int(:one_shot_reverse), do: @spline_mode_one_shot_reverse
  defp spline_mode_to_int(:back_and_forth_reverse), do: @spline_mode_back_and_forth_reverse
  defp spline_mode_to_int(:cyclic_reverse), do: @spline_mode_cyclic_reverse
  defp spline_mode_to_int(_), do: @spline_mode_one_shot
end
