defmodule BezgelorProtocol.Packets.World.ServerHousingDecorUpdate do
  @moduledoc """
  Single decor item update (place, move, or remove).

  ## Wire Format

  ```
  plot_id     : uint32  - Plot instance ID
  action      : uint8   - 0=placed, 1=moved, 2=removed
  decor_db_id : uint32  - Database row ID
  decor_id    : uint32  - Decor type ID (0 if removed)
  pos_x       : float32 - X position
  pos_y       : float32 - Y position
  pos_z       : float32 - Z position
  rot_pitch   : float32 - Pitch rotation
  rot_yaw     : float32 - Yaw rotation
  rot_roll    : float32 - Roll rotation
  scale       : float32 - Scale factor
  is_exterior : uint8   - 1 if exterior, 0 if interior
  ```
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [
    :plot_id,
    :action,
    :decor_db_id,
    :decor_id,
    :pos_x,
    :pos_y,
    :pos_z,
    :rot_pitch,
    :rot_yaw,
    :rot_roll,
    :scale,
    :is_exterior
  ]

  @type action :: :placed | :moved | :removed
  @type t :: %__MODULE__{
          plot_id: non_neg_integer(),
          action: action(),
          decor_db_id: non_neg_integer(),
          decor_id: non_neg_integer(),
          pos_x: float(),
          pos_y: float(),
          pos_z: float(),
          rot_pitch: float(),
          rot_yaw: float(),
          rot_roll: float(),
          scale: float(),
          is_exterior: boolean()
        }

  @impl true
  def opcode, do: :server_housing_decor_update

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    action_byte = action_to_byte(packet.action)
    exterior_byte = if packet.is_exterior, do: 1, else: 0

    writer =
      writer
      |> PacketWriter.write_u32(packet.plot_id)
      |> PacketWriter.write_u8(action_byte)
      |> PacketWriter.write_u32(packet.decor_db_id)
      |> PacketWriter.write_u32(packet.decor_id || 0)
      |> PacketWriter.write_f32(packet.pos_x || 0.0)
      |> PacketWriter.write_f32(packet.pos_y || 0.0)
      |> PacketWriter.write_f32(packet.pos_z || 0.0)
      |> PacketWriter.write_f32(packet.rot_pitch || 0.0)
      |> PacketWriter.write_f32(packet.rot_yaw || 0.0)
      |> PacketWriter.write_f32(packet.rot_roll || 0.0)
      |> PacketWriter.write_f32(packet.scale || 1.0)
      |> PacketWriter.write_u8(exterior_byte)

    {:ok, writer}
  end

  defp action_to_byte(:placed), do: 0
  defp action_to_byte(:moved), do: 1
  defp action_to_byte(:removed), do: 2

  @doc "Create a placed update from a HousingDecor struct."
  @spec placed(non_neg_integer(), map()) :: t()
  def placed(plot_id, decor) do
    %__MODULE__{
      plot_id: plot_id,
      action: :placed,
      decor_db_id: decor.id,
      decor_id: decor.decor_id,
      pos_x: decor.pos_x,
      pos_y: decor.pos_y,
      pos_z: decor.pos_z,
      rot_pitch: decor.rot_pitch,
      rot_yaw: decor.rot_yaw,
      rot_roll: decor.rot_roll,
      scale: decor.scale,
      is_exterior: decor.is_exterior
    }
  end

  @doc "Create a moved update from a HousingDecor struct."
  @spec moved(non_neg_integer(), map()) :: t()
  def moved(plot_id, decor) do
    %__MODULE__{placed(plot_id, decor) | action: :moved}
  end

  @doc "Create a removed update."
  @spec removed(non_neg_integer(), non_neg_integer()) :: t()
  def removed(plot_id, decor_db_id) do
    %__MODULE__{
      plot_id: plot_id,
      action: :removed,
      decor_db_id: decor_db_id,
      decor_id: 0,
      pos_x: 0.0,
      pos_y: 0.0,
      pos_z: 0.0,
      rot_pitch: 0.0,
      rot_yaw: 0.0,
      rot_roll: 0.0,
      scale: 1.0,
      is_exterior: false
    }
  end
end
