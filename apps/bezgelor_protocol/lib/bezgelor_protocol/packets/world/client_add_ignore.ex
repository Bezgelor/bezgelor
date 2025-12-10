defmodule BezgelorProtocol.Packets.World.ClientAddIgnore do
  @moduledoc """
  Request to add a player to ignore list.

  ## Wire Format
  target_name : wstring - Name of player to ignore
  """
  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:target_name]

  @impl true
  def opcode, do: :client_add_ignore

  @impl true
  def read(reader) do
    with {:ok, target_name, reader} <- PacketReader.read_wide_string(reader) do
      {:ok, %__MODULE__{target_name: target_name}, reader}
    end
  end
end
