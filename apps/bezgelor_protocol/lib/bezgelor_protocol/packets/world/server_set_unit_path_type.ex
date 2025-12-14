defmodule BezgelorProtocol.Packets.World.ServerSetUnitPathType do
  @moduledoc """
  Server packet to set a unit's path type (Soldier, Settler, Scientist, Explorer).

  Sent after ServerEntityCreate for player entities.

  ## Wire Format (from NexusForever)

  ```
  unit_id : uint32 - Entity GUID
  path    : 3 bits - Path enum (0=Soldier, 1=Settler, 2=Scientist, 3=Explorer)
  ```
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  # Path enum values
  @path_soldier 0
  @path_settler 1
  @path_scientist 2
  @path_explorer 3

  defstruct unit_id: 0,
            path: @path_soldier

  @type t :: %__MODULE__{
          unit_id: non_neg_integer(),
          path: non_neg_integer()
        }

  @impl true
  def opcode, do: :server_set_unit_path_type

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_bits(packet.unit_id, 32)
      |> PacketWriter.write_bits(packet.path, 3)
      |> PacketWriter.flush_bits()

    {:ok, writer}
  end

  # Path enum accessors
  def path_soldier, do: @path_soldier
  def path_settler, do: @path_settler
  def path_scientist, do: @path_scientist
  def path_explorer, do: @path_explorer
end
