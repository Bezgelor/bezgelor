defmodule BezgelorProtocol.Packets.World.ClientCharacterList do
  @moduledoc """
  Client packet requesting the character list.

  ## Overview

  Sent by the client after connecting to the world server to request
  the character list. This is a zero-byte message - no payload.

  The server responds with character list packets including:
  - ServerAccountCurrencySet
  - ServerGenericUnlockAccountList
  - ServerAccountEntitlements
  - ServerAccountTier
  - ServerMaxCharacterLevelAchieved
  - ServerCharacterList
  """

  @behaviour BezgelorProtocol.Packet.Readable

  defstruct []

  @type t :: %__MODULE__{}

  @impl true
  def opcode, do: :client_character_list

  @impl true
  @spec read(BezgelorProtocol.PacketReader.t()) ::
          {:ok, t(), BezgelorProtocol.PacketReader.t()} | {:error, term()}
  def read(reader) do
    # Zero-byte message - no payload to read
    {:ok, %__MODULE__{}, reader}
  end
end
