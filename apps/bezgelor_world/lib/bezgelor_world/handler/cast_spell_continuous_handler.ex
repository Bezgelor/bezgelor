defmodule BezgelorWorld.Handler.CastSpellContinuousHandler do
  @moduledoc """
  Handles ClientCastSpellContinuous packets for continuous casting input.
  """

  @behaviour BezgelorProtocol.Handler

  alias BezgelorProtocol.PacketReader
  alias BezgelorProtocol.Packets.World.{ClientCastSpell, ClientCastSpellContinuous}
  alias BezgelorWorld.Handler.SpellHandler

  @impl true
  def handle(payload, state) do
    reader = PacketReader.new(payload)

    case ClientCastSpellContinuous.read(reader) do
      {:ok, packet, _reader} -> handle_continuous(packet, state)
      {:error, _} -> {:error, :invalid_packet}
    end
  end

  defp handle_continuous(%ClientCastSpellContinuous{} = packet, state) do
    if packet.button_pressed do
      # Build a ClientCastSpell with the bag_index - spell resolution happens in SpellHandler
      cast_packet = %ClientCastSpell{
        client_unique_id: 0,
        bag_index: packet.bag_index,
        caster_id: state.session_data[:entity_id] || 0,
        button_pressed: true
      }

      SpellHandler.handle_cast_request(cast_packet, state)
    else
      {:ok, state}
    end
  end
end
