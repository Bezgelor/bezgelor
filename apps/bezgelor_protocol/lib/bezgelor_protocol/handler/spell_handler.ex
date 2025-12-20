defmodule BezgelorProtocol.Handler.SpellHandler do
  @moduledoc """
  Handler for spell casting packets.

  Currently a stub that acknowledges spell cast requests without processing.
  Full implementation will handle spell validation, cooldowns, and effects.
  """

  @behaviour BezgelorProtocol.Handler

  require Logger

  @impl true
  def handle(_payload, state) do
    # TODO: Implement spell casting
    # For now, just acknowledge the packet to suppress warnings
    Logger.debug("SpellHandler: received spell cast request (not yet implemented)")
    {:ok, state}
  end
end
