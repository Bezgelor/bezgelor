defmodule BezgelorProtocol.Packets.World.ClientEntitySelect do
  @moduledoc """
  Client packet sent when the player selects/targets an entity.

  ## Packet Structure

  ```
  guid : uint32 - Entity GUID (0 = deselect)
  ```
  """

  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct guid: 0

  @type t :: %__MODULE__{
          guid: non_neg_integer()
        }

  @impl true
  def opcode, do: :client_entity_select

  @impl true
  @spec read(PacketReader.t()) :: {:ok, t(), PacketReader.t()} | {:error, term()}
  def read(reader) do
    case PacketReader.read_uint32(reader) do
      {:ok, guid, reader} ->
        packet = %__MODULE__{guid: guid}
        {:ok, packet, reader}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
