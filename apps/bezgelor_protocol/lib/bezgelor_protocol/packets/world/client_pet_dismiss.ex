defmodule BezgelorProtocol.Packets.World.ClientPetDismiss do
  @moduledoc """
  Pet dismiss request from client.

  ## Wire Format
  (empty - no additional data needed)
  """

  @behaviour BezgelorProtocol.Packet.Readable

  defstruct []

  @type t :: %__MODULE__{}

  @impl true
  def opcode, do: :client_pet_dismiss

  @impl true
  def read(reader) do
    {:ok, %__MODULE__{}, reader}
  end
end
