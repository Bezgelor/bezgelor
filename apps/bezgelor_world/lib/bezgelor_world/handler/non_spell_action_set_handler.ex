defmodule BezgelorWorld.Handler.NonSpellActionSetHandler do
  @moduledoc """
  Handles non-spell Limited Action Set shortcut changes.
  """

  @behaviour BezgelorProtocol.Handler

  alias BezgelorDb.ActionSets
  alias BezgelorProtocol.PacketReader
  alias BezgelorProtocol.Packets.World.ClientNonSpellActionSetChanges

  require Logger

  @impl true
  def handle(payload, state) do
    reader = PacketReader.new(payload)

    case ClientNonSpellActionSetChanges.read(reader) do
      {:ok, packet, _reader} ->
        handle_change(packet, state)

      {:error, reason} ->
        Logger.warning("Failed to parse non-spell action set change: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp handle_change(packet, state) do
    character_id = state.session_data[:character_id]

    cond do
      packet.shortcut_type == 4 ->
        Logger.warning("Non-spell action set change received for spell shortcut")
        {:ok, state}

      packet.object_id == 0 ->
        ActionSets.delete_shortcut(character_id, packet.spec_index, packet.action_bar_index)
        {:ok, state}

      true ->
        _ =
          ActionSets.upsert_shortcut(%{
            character_id: character_id,
            spec_index: packet.spec_index,
            slot: packet.action_bar_index,
            shortcut_type: packet.shortcut_type,
            object_id: packet.object_id,
            spell_id: packet.object_id,
            tier: 0
          })

        {:ok, state}
    end
  end
end
