defmodule BezgelorProtocol.Handler.EntitySelectHandler do
  @moduledoc """
  Handler for ClientEntitySelect packets.

  Called when the player selects/targets an entity in the game world.
  A GUID of 0 means the player has deselected their current target.
  """

  @behaviour BezgelorProtocol.Handler

  alias BezgelorProtocol.Packets.World.ClientEntitySelect
  alias BezgelorProtocol.PacketReader

  require Logger

  @impl true
  def handle(payload, state) do
    reader = PacketReader.new(payload)
    {:ok, packet, _reader} = ClientEntitySelect.read(reader)

    if packet.guid > 0 do
      Logger.debug("Player selected entity: #{packet.guid}")
      # TODO: Store target in session/player state for combat targeting
    else
      Logger.debug("Player deselected target")
    end

    {:ok, state}
  end
end
