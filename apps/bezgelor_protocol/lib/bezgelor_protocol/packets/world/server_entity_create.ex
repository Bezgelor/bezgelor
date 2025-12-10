defmodule BezgelorProtocol.Packets.World.ServerEntityCreate do
  @moduledoc """
  Entity spawn packet.

  ## Overview

  Sent to spawn players, NPCs, and objects in the world.
  Each entity has a unique GUID, type, and position.

  ## Wire Format

  ```
  guid         : uint64  - Unique entity identifier
  entity_type  : uint32  - Type (1=player, 2=creature, 3=object, 4=vehicle)
  name_length  : uint32  - Length of name string
  name         : wstring - Entity name (UTF-16LE)
  level        : uint32  - Entity level
  faction      : uint32  - Faction ID
  display_info : uint32  - Display/model info
  position_x   : float32 - X coordinate
  position_y   : float32 - Y coordinate
  position_z   : float32 - Z coordinate
  rotation_x   : float32 - X rotation
  rotation_y   : float32 - Y rotation
  rotation_z   : float32 - Z rotation
  health       : uint32  - Current health
  max_health   : uint32  - Maximum health
  ```

  ## Entity Types

  | Type | Value | Description |
  |------|-------|-------------|
  | Player | 1 | Player character |
  | Creature | 2 | NPC/mob |
  | Object | 3 | World object |
  | Vehicle | 4 | Mount/vehicle |
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  # Entity type constants
  @entity_type_player 1
  @entity_type_creature 2
  @entity_type_object 3
  @entity_type_vehicle 4

  defstruct [
    :guid,
    :entity_type,
    :name,
    :position_x,
    :position_y,
    :position_z,
    level: 1,
    faction: 0,
    display_info: 0,
    rotation_x: 0.0,
    rotation_y: 0.0,
    rotation_z: 0.0,
    health: 100,
    max_health: 100
  ]

  @type entity_type :: :player | :creature | :object | :vehicle

  @type t :: %__MODULE__{
          guid: non_neg_integer(),
          entity_type: entity_type(),
          name: String.t() | nil,
          level: non_neg_integer(),
          faction: non_neg_integer(),
          display_info: non_neg_integer(),
          position_x: float(),
          position_y: float(),
          position_z: float(),
          rotation_x: float(),
          rotation_y: float(),
          rotation_z: float(),
          health: non_neg_integer(),
          max_health: non_neg_integer()
        }

  @impl true
  def opcode, do: :server_entity_create

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    entity_type_int = entity_type_to_int(packet.entity_type)

    writer =
      writer
      |> PacketWriter.write_uint64(packet.guid)
      |> PacketWriter.write_uint32(entity_type_int)
      |> PacketWriter.write_wide_string(packet.name || "")
      |> PacketWriter.write_uint32(packet.level || 1)
      |> PacketWriter.write_uint32(packet.faction || 0)
      |> PacketWriter.write_uint32(packet.display_info || 0)
      |> PacketWriter.write_float32(packet.position_x)
      |> PacketWriter.write_float32(packet.position_y)
      |> PacketWriter.write_float32(packet.position_z)
      |> PacketWriter.write_float32(packet.rotation_x || 0.0)
      |> PacketWriter.write_float32(packet.rotation_y || 0.0)
      |> PacketWriter.write_float32(packet.rotation_z || 0.0)
      |> PacketWriter.write_uint32(packet.health || 100)
      |> PacketWriter.write_uint32(packet.max_health || 100)

    {:ok, writer}
  end

  @doc "Create entity packet from Entity struct."
  @spec from_entity(map()) :: t()
  def from_entity(entity) do
    {pos_x, pos_y, pos_z} = entity.position
    {rot_x, rot_y, rot_z} = entity.rotation

    %__MODULE__{
      guid: entity.guid,
      entity_type: entity.type,
      name: entity.name,
      level: entity.level,
      faction: entity.faction,
      display_info: entity.display_info,
      position_x: pos_x,
      position_y: pos_y,
      position_z: pos_z,
      rotation_x: rot_x,
      rotation_y: rot_y,
      rotation_z: rot_z,
      health: entity.health,
      max_health: entity.max_health
    }
  end

  @doc "Convert entity type atom to integer."
  @spec entity_type_to_int(entity_type()) :: non_neg_integer()
  def entity_type_to_int(:player), do: @entity_type_player
  def entity_type_to_int(:creature), do: @entity_type_creature
  def entity_type_to_int(:object), do: @entity_type_object
  def entity_type_to_int(:vehicle), do: @entity_type_vehicle
  def entity_type_to_int(_), do: @entity_type_object

  @doc "Convert integer to entity type atom."
  @spec int_to_entity_type(non_neg_integer()) :: entity_type()
  def int_to_entity_type(@entity_type_player), do: :player
  def int_to_entity_type(@entity_type_creature), do: :creature
  def int_to_entity_type(@entity_type_object), do: :object
  def int_to_entity_type(@entity_type_vehicle), do: :vehicle
  def int_to_entity_type(_), do: :object
end
