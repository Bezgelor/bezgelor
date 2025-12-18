defmodule BezgelorProtocol.Packets.World.ServerMountUpdate do
  @moduledoc """
  Mount state update from server.

  Sent when a player's mount status changes (summoned/dismissed).

  ## Wire Format
  entity_guid : uint64  - Entity whose mount changed
  mount_id    : uint32  - Mount ID (0 = dismounted)
  mount_state : uint8   - 0=dismounted, 1=mounting, 2=mounted
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  @mount_state_dismounted 0
  @mount_state_mounting 1
  @mount_state_mounted 2

  defstruct [:entity_guid, :mount_id, :mount_state]

  @type mount_state :: :dismounted | :mounting | :mounted

  @type t :: %__MODULE__{
          entity_guid: non_neg_integer(),
          mount_id: non_neg_integer(),
          mount_state: mount_state()
        }

  @impl true
  def opcode, do: :server_mount_update

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    state_byte = mount_state_to_byte(packet.mount_state)

    writer =
      writer
      |> PacketWriter.write_u64(packet.entity_guid)
      |> PacketWriter.write_u32(packet.mount_id || 0)
      |> PacketWriter.write_u8(state_byte)

    {:ok, writer}
  end

  defp mount_state_to_byte(:dismounted), do: @mount_state_dismounted
  defp mount_state_to_byte(:mounting), do: @mount_state_mounting
  defp mount_state_to_byte(:mounted), do: @mount_state_mounted

  # Constructors for common states
  def mounted(entity_guid, mount_id) do
    %__MODULE__{entity_guid: entity_guid, mount_id: mount_id, mount_state: :mounted}
  end

  def dismounted(entity_guid) do
    %__MODULE__{entity_guid: entity_guid, mount_id: 0, mount_state: :dismounted}
  end
end
