defmodule BezgelorProtocol.Packets.World.ClientAddFriend do
  @moduledoc """
  Request to add a friend.

  ## Wire Format
  target_name : wstring - Name of player to add
  note        : wstring - Optional note
  """
  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:target_name, :note]

  @impl true
  def opcode, do: :client_add_friend

  @impl true
  def read(reader) do
    with {:ok, target_name, reader} <- PacketReader.read_wide_string(reader),
         {:ok, note, reader} <- PacketReader.read_wide_string(reader) do
      {:ok, %__MODULE__{target_name: target_name, note: note}, reader}
    end
  end
end
