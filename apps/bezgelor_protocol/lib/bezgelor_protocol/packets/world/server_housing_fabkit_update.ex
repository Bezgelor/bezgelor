defmodule BezgelorProtocol.Packets.World.ServerHousingFabkitUpdate do
  @moduledoc """
  Single FABkit update (install or remove).

  ## Wire Format

  ```
  plot_id       : uint32  - Plot instance ID
  action        : uint8   - 0=installed, 1=removed
  fabkit_db_id  : uint32  - Database row ID
  socket_index  : uint8   - Socket index (0-5)
  fabkit_id     : uint32  - FABkit type ID (0 if removed)
  ```
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:plot_id, :action, :fabkit_db_id, :socket_index, :fabkit_id]

  @type action :: :installed | :removed
  @type t :: %__MODULE__{
          plot_id: non_neg_integer(),
          action: action(),
          fabkit_db_id: non_neg_integer(),
          socket_index: non_neg_integer(),
          fabkit_id: non_neg_integer()
        }

  @impl true
  def opcode, do: :server_housing_fabkit_update

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    action_byte = action_to_byte(packet.action)

    writer =
      writer
      |> PacketWriter.write_uint32(packet.plot_id)
      |> PacketWriter.write_byte(action_byte)
      |> PacketWriter.write_uint32(packet.fabkit_db_id)
      |> PacketWriter.write_byte(packet.socket_index)
      |> PacketWriter.write_uint32(packet.fabkit_id || 0)

    {:ok, writer}
  end

  defp action_to_byte(:installed), do: 0
  defp action_to_byte(:removed), do: 1

  @doc "Create an installed update from a HousingFabkit struct."
  @spec installed(non_neg_integer(), map()) :: t()
  def installed(plot_id, fabkit) do
    %__MODULE__{
      plot_id: plot_id,
      action: :installed,
      fabkit_db_id: fabkit.id,
      socket_index: fabkit.socket_index,
      fabkit_id: fabkit.fabkit_id
    }
  end

  @doc "Create a removed update."
  @spec removed(non_neg_integer(), non_neg_integer(), non_neg_integer()) :: t()
  def removed(plot_id, fabkit_db_id, socket_index) do
    %__MODULE__{
      plot_id: plot_id,
      action: :removed,
      fabkit_db_id: fabkit_db_id,
      socket_index: socket_index,
      fabkit_id: 0
    }
  end
end
