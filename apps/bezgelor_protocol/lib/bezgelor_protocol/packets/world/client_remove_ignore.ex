defmodule BezgelorProtocol.Packets.World.ClientRemoveIgnore do
  @moduledoc """
  Request to remove a player from ignore list.

  ## Wire Format
  ignore_id : uint64 - Character ID to unignore
  """
  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:ignore_id]

  @impl true
  def opcode, do: :client_remove_ignore

  @impl true
  def read(reader) do
    with {:ok, ignore_id, reader} <- PacketReader.read_uint64(reader) do
      {:ok, %__MODULE__{ignore_id: ignore_id}, reader}
    end
  end
end
