defmodule BezgelorProtocol.Packets.World.ClientMovement do
  @moduledoc """
  Client position/movement update.

  ## Overview

  Sent by client to update player position in the world.
  Contains position, rotation, velocity, and movement state.

  ## Wire Format

  ```
  position_x      : float32 - X coordinate
  position_y      : float32 - Y coordinate
  position_z      : float32 - Z coordinate
  rotation_x      : float32 - X rotation
  rotation_y      : float32 - Y rotation
  rotation_z      : float32 - Z rotation
  velocity_x      : float32 - X velocity
  velocity_y      : float32 - Y velocity
  velocity_z      : float32 - Z velocity
  movement_flags  : uint32  - Movement state flags
  timestamp       : uint32  - Client timestamp
  ```

  ## Movement Flags

  | Flag | Value | Description |
  |------|-------|-------------|
  | None | 0x0000 | Standing still |
  | Forward | 0x0001 | Moving forward |
  | Backward | 0x0002 | Moving backward |
  | StrafeLeft | 0x0004 | Strafing left |
  | StrafeRight | 0x0008 | Strafing right |
  | Jump | 0x0010 | Jumping |
  | Falling | 0x0020 | In freefall |
  | Swimming | 0x0040 | In water |
  | Sprinting | 0x0080 | Sprint active |
  """

  @behaviour BezgelorProtocol.Packet.Readable

  import Bitwise

  alias BezgelorProtocol.PacketReader

  # Movement flag constants
  @flag_none 0x0000
  @flag_forward 0x0001
  @flag_backward 0x0002
  @flag_strafe_left 0x0004
  @flag_strafe_right 0x0008
  @flag_jump 0x0010
  @flag_falling 0x0020
  @flag_swimming 0x0040
  @flag_sprinting 0x0080

  defstruct [
    :position_x,
    :position_y,
    :position_z,
    :rotation_x,
    :rotation_y,
    :rotation_z,
    velocity_x: 0.0,
    velocity_y: 0.0,
    velocity_z: 0.0,
    movement_flags: 0,
    timestamp: 0
  ]

  @type t :: %__MODULE__{
          position_x: float(),
          position_y: float(),
          position_z: float(),
          rotation_x: float(),
          rotation_y: float(),
          rotation_z: float(),
          velocity_x: float(),
          velocity_y: float(),
          velocity_z: float(),
          movement_flags: non_neg_integer(),
          timestamp: non_neg_integer()
        }

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
      {:ok,
       %__MODULE__{
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

  @doc "Get position as tuple."
  @spec position(t()) :: {float(), float(), float()}
  def position(%__MODULE__{} = packet) do
    {packet.position_x, packet.position_y, packet.position_z}
  end

  @doc "Get rotation as tuple."
  @spec rotation(t()) :: {float(), float(), float()}
  def rotation(%__MODULE__{} = packet) do
    {packet.rotation_x, packet.rotation_y, packet.rotation_z}
  end

  @doc "Get velocity as tuple."
  @spec velocity(t()) :: {float(), float(), float()}
  def velocity(%__MODULE__{} = packet) do
    {packet.velocity_x, packet.velocity_y, packet.velocity_z}
  end

  @doc "Check if movement flag is set."
  @spec has_flag?(t(), atom()) :: boolean()
  def has_flag?(%__MODULE__{movement_flags: flags}, :forward), do: (flags &&& @flag_forward) != 0

  def has_flag?(%__MODULE__{movement_flags: flags}, :backward),
    do: (flags &&& @flag_backward) != 0

  def has_flag?(%__MODULE__{movement_flags: flags}, :strafe_left),
    do: (flags &&& @flag_strafe_left) != 0

  def has_flag?(%__MODULE__{movement_flags: flags}, :strafe_right),
    do: (flags &&& @flag_strafe_right) != 0

  def has_flag?(%__MODULE__{movement_flags: flags}, :jump), do: (flags &&& @flag_jump) != 0
  def has_flag?(%__MODULE__{movement_flags: flags}, :falling), do: (flags &&& @flag_falling) != 0

  def has_flag?(%__MODULE__{movement_flags: flags}, :swimming),
    do: (flags &&& @flag_swimming) != 0

  def has_flag?(%__MODULE__{movement_flags: flags}, :sprinting),
    do: (flags &&& @flag_sprinting) != 0

  def has_flag?(%__MODULE__{movement_flags: flags}, :none), do: flags == @flag_none
  def has_flag?(_, _), do: false

  @doc "Check if entity is moving."
  @spec moving?(t()) :: boolean()
  def moving?(%__MODULE__{movement_flags: flags}) do
    movement_mask = @flag_forward ||| @flag_backward ||| @flag_strafe_left ||| @flag_strafe_right
    (flags &&& movement_mask) != 0
  end
end
