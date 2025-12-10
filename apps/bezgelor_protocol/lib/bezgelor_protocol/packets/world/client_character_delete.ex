defmodule BezgelorProtocol.Packets.World.ClientCharacterDelete do
  @moduledoc """
  Character deletion request.

  ## Overview

  Client requests deletion of a character. The server will
  soft-delete the character (mark as deleted but keep data).

  ## Wire Format

  ```
  character_id : uint64 - ID of character to delete
  ```

  Note: The character must belong to the authenticated account.
  """

  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:character_id]

  @type t :: %__MODULE__{
          character_id: non_neg_integer()
        }

  @impl true
  def opcode, do: :client_character_delete

  @impl true
  def read(reader) do
    with {:ok, character_id, reader} <- PacketReader.read_uint64(reader) do
      {:ok, %__MODULE__{character_id: character_id}, reader}
    end
  end
end
