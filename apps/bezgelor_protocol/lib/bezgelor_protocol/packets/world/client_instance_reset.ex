defmodule BezgelorProtocol.Packets.World.ClientInstanceReset do
  @moduledoc """
  Request to reset an instance (group leader only).

  ## Wire Format
  instance_id : uint32
  difficulty  : uint8
  """
  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:instance_id, :difficulty]

  @impl true
  def opcode, do: :client_instance_reset

  @impl true
  def read(reader) do
    with {:ok, instance_id, reader} <- PacketReader.read_uint32(reader),
         {:ok, diff_byte, reader} <- PacketReader.read_byte(reader) do
      {:ok,
       %__MODULE__{
         instance_id: instance_id,
         difficulty: int_to_difficulty(diff_byte)
       }, reader}
    end
  end

  defp int_to_difficulty(0), do: :normal
  defp int_to_difficulty(1), do: :veteran
  defp int_to_difficulty(2), do: :challenge
  defp int_to_difficulty(3), do: :mythic_plus
  defp int_to_difficulty(_), do: :normal
end
