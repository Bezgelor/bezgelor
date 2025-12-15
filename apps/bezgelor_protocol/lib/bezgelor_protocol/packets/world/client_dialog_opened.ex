defmodule BezgelorProtocol.Packets.World.ClientDialogOpened do
  @moduledoc """
  Client packet sent when a dialog window is opened.

  ## Packet Structure

  Zero-byte message - just an acknowledgment that the dialog opened.
  """

  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct []

  @type t :: %__MODULE__{}

  @impl true
  def opcode, do: :client_dialog_opened

  @impl true
  @spec read(PacketReader.t()) :: {:ok, t(), PacketReader.t()} | {:error, term()}
  def read(reader) do
    # Zero-byte message
    {:ok, %__MODULE__{}, reader}
  end
end
