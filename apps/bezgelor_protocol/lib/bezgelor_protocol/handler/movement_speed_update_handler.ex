defmodule BezgelorProtocol.Handler.MovementSpeedUpdateHandler do
  @moduledoc """
  Handles ClientPlayerMovementSpeedUpdate packets (opcode 0x063B).

  Sent by the client when movement speed changes (mounting, buffs, etc.).
  The exact packet structure is not fully documented in NexusForever.

  ## Notes

  This appears to be related to ServerInstanceSettings (0x00F1) which
  triggers this packet and 0x00D5.
  """

  @behaviour BezgelorProtocol.Handler

  require Logger

  @impl true
  def handle(payload, state) do
    Logger.debug(
      "[MovementSpeedUpdate] Received update (#{byte_size(payload)} bytes)"
    )

    # TODO: Parse and validate speed changes
    # TODO: Anti-cheat: verify speed is within expected bounds

    {:ok, state}
  end
end
