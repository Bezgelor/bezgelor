defmodule BezgelorProtocol.Packets.World.ClientGroupFinderJoin do
  @moduledoc """
  Request to join the group finder queue.

  ## Wire Format
  instance_type : uint8    (0=dungeon, 1=adventure, 2=raid, 3=expedition)
  difficulty    : uint8    (0=normal, 1=veteran, 2=challenge, 3=mythic_plus)
  role          : uint8    (0=tank, 1=healer, 2=dps)
  instance_count: uint8
  instance_ids  : [uint32] * count
  """
  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:instance_type, :difficulty, :role, instance_ids: []]

  @impl true
  def opcode, do: :client_group_finder_join

  @impl true
  def read(reader) do
    with {:ok, type_byte, reader} <- PacketReader.read_byte(reader),
         {:ok, diff_byte, reader} <- PacketReader.read_byte(reader),
         {:ok, role_byte, reader} <- PacketReader.read_byte(reader),
         {:ok, count, reader} <- PacketReader.read_byte(reader),
         {:ok, instance_ids, reader} <- read_instance_ids(reader, count) do
      {:ok,
       %__MODULE__{
         instance_type: int_to_instance_type(type_byte),
         difficulty: int_to_difficulty(diff_byte),
         role: int_to_role(role_byte),
         instance_ids: instance_ids
       }, reader}
    end
  end

  defp read_instance_ids(reader, count) do
    read_instance_ids(reader, count, [])
  end

  defp read_instance_ids(reader, 0, acc), do: {:ok, Enum.reverse(acc), reader}

  defp read_instance_ids(reader, count, acc) do
    with {:ok, id, reader} <- PacketReader.read_uint32(reader) do
      read_instance_ids(reader, count - 1, [id | acc])
    end
  end

  defp int_to_instance_type(0), do: :dungeon
  defp int_to_instance_type(1), do: :adventure
  defp int_to_instance_type(2), do: :raid
  defp int_to_instance_type(3), do: :expedition
  defp int_to_instance_type(_), do: :dungeon

  defp int_to_difficulty(0), do: :normal
  defp int_to_difficulty(1), do: :veteran
  defp int_to_difficulty(2), do: :challenge
  defp int_to_difficulty(3), do: :mythic_plus
  defp int_to_difficulty(_), do: :normal

  defp int_to_role(0), do: :tank
  defp int_to_role(1), do: :healer
  defp int_to_role(2), do: :dps
  defp int_to_role(_), do: :dps
end
