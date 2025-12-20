defmodule BezgelorWorld.Handler.CastSpellContinuousHandler do
  @moduledoc """
  Handles ClientCastSpellContinuous packets for continuous casting input.
  """

  @behaviour BezgelorProtocol.Handler

  alias BezgelorDb.Inventory
  alias BezgelorProtocol.PacketReader
  alias BezgelorProtocol.Packets.World.{ClientCastSpell, ClientCastSpellContinuous}
  alias BezgelorWorld.Handler.SpellHandler

  require Logger

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
      character_id = state.session_data[:character_id]

      case Inventory.get_item_at(character_id, :ability, packet.bag_index, 0) do
        nil ->
          Logger.warning("Continuous cast missing ability item at bag_index=#{packet.bag_index}")

          {:ok, state}

        item ->
          cast_packet = %ClientCastSpell{
            spell_id: item.item_id,
            target_guid: packet.guid || 0,
            target_position: {0.0, 0.0, 0.0}
          }

          SpellHandler.handle_cast_request(cast_packet, state)
      end
    else
      {:ok, state}
    end
  end
end
