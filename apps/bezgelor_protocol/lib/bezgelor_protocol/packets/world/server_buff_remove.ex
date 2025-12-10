defmodule BezgelorProtocol.Packets.World.ServerBuffRemove do
  @moduledoc """
  Buff/debuff removal notification.

  ## Wire Format

  ```
  target_guid : uint64  - Entity losing the buff
  buff_id     : uint32  - Buff instance ID being removed
  reason      : uint8   - Removal reason (0=dispel, 1=expired, 2=cancelled)
  ```
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  # Removal reasons
  @reason_dispel 0
  @reason_expired 1
  @reason_cancelled 2

  defstruct [:target_guid, :buff_id, :reason]

  @type removal_reason :: :dispel | :expired | :cancelled
  @type t :: %__MODULE__{
          target_guid: non_neg_integer(),
          buff_id: non_neg_integer(),
          reason: non_neg_integer()
        }

  @impl true
  def opcode, do: :server_buff_remove

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_uint64(packet.target_guid)
      |> PacketWriter.write_uint32(packet.buff_id)
      |> PacketWriter.write_byte(packet.reason)

    {:ok, writer}
  end

  @doc """
  Create a new buff remove packet.
  """
  @spec new(non_neg_integer(), non_neg_integer(), removal_reason() | non_neg_integer()) :: t()
  def new(target_guid, buff_id, reason) do
    reason_int = if is_atom(reason), do: reason_to_int(reason), else: reason

    %__MODULE__{
      target_guid: target_guid,
      buff_id: buff_id,
      reason: reason_int
    }
  end

  defp reason_to_int(:dispel), do: @reason_dispel
  defp reason_to_int(:expired), do: @reason_expired
  defp reason_to_int(:cancelled), do: @reason_cancelled
  defp reason_to_int(_), do: @reason_expired
end
