defmodule BezgelorProtocol.Packets.World.ServerHousingEnter do
  @moduledoc """
  Response to housing plot entry request.

  ## Wire Format

  ```
  plot_id     : uint32  - Plot instance ID
  owner_guid  : uint64  - Character GUID of plot owner
  result      : uint8   - 0=success, 1=denied, 2=not_found
  ```
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:plot_id, :owner_guid, :result]

  @type result :: :success | :denied | :not_found
  @type t :: %__MODULE__{
          plot_id: non_neg_integer(),
          owner_guid: non_neg_integer(),
          result: result()
        }

  @impl true
  def opcode, do: :server_housing_enter

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    result_byte = result_to_byte(packet.result)

    writer =
      writer
      |> PacketWriter.write_u32(packet.plot_id)
      |> PacketWriter.write_u64(packet.owner_guid)
      |> PacketWriter.write_u8(result_byte)

    {:ok, writer}
  end

  defp result_to_byte(:success), do: 0
  defp result_to_byte(:denied), do: 1
  defp result_to_byte(:not_found), do: 2

  @doc "Create a success response."
  @spec success(non_neg_integer(), non_neg_integer()) :: t()
  def success(plot_id, owner_guid) do
    %__MODULE__{plot_id: plot_id, owner_guid: owner_guid, result: :success}
  end

  @doc "Create a denied response."
  @spec denied() :: t()
  def denied do
    %__MODULE__{plot_id: 0, owner_guid: 0, result: :denied}
  end

  @doc "Create a not_found response."
  @spec not_found() :: t()
  def not_found do
    %__MODULE__{plot_id: 0, owner_guid: 0, result: :not_found}
  end
end
