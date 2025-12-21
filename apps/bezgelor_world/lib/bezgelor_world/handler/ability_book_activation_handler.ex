defmodule BezgelorWorld.Handler.AbilityBookActivationHandler do
  @moduledoc """
  Handles ability book activation toggles.
  """

  @behaviour BezgelorProtocol.Handler

  alias BezgelorProtocol.PacketReader
  alias BezgelorProtocol.Packets.World.ClientAbilityBookActivateSpell

  require Logger

  @impl true
  def handle(payload, state) do
    reader = PacketReader.new(payload)

    case ClientAbilityBookActivateSpell.read(reader) do
      {:ok, packet, _reader} ->
        Logger.debug(
          "Ability book activation toggle: spell_id=#{packet.spell_id} active=#{packet.active}"
        )

        {:ok, state}

      {:error, reason} ->
        Logger.warning("Failed to parse ability book activation: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
