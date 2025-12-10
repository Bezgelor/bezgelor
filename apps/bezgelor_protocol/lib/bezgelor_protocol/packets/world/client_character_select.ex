defmodule BezgelorProtocol.Packets.World.ClientCharacterSelect do
  @moduledoc """
  Character selection request.

  ## Overview

  Client selects which character to play. Sent after viewing
  the character list when the player clicks on a character.

  ## Wire Format

  ```
  character_id : uint64 - ID of character to select
  ```
  """

  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:character_id]

  @type t :: %__MODULE__{
          character_id: non_neg_integer()
        }

  @impl true
  def opcode, do: :client_character_select

  @impl true
  def read(reader) do
    with {:ok, character_id, reader} <- PacketReader.read_uint64(reader) do
      {:ok, %__MODULE__{character_id: character_id}, reader}
    end
  end
end
