defmodule BezgelorProtocol.Packets.World.ClientRespawn do
  @moduledoc """
  Client request to respawn after death.

  ## Overview

  Sent by the client when the player chooses to respawn.
  For now, we only support respawning at current location.

  ## Wire Format

  ```
  respawn_type : uint32 - Type of respawn (0=same location, 1=graveyard)
  ```
  """

  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct respawn_type: :same_location

  @type respawn_type :: :same_location | :graveyard

  @type t :: %__MODULE__{
          respawn_type: respawn_type()
        }

  @impl true
  def opcode, do: :client_respawn

  @impl true
  def read(reader) do
    with {:ok, type_int, reader} <- PacketReader.read_uint32(reader) do
      respawn_type = int_to_respawn_type(type_int)

      {:ok,
       %__MODULE__{
         respawn_type: respawn_type
       }, reader}
    end
  end

  defp int_to_respawn_type(0), do: :same_location
  defp int_to_respawn_type(1), do: :graveyard
  defp int_to_respawn_type(_), do: :same_location
end
