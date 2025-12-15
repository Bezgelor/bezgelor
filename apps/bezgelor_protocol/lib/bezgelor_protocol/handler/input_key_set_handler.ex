defmodule BezgelorProtocol.Handler.InputKeySetHandler do
  @moduledoc """
  Handler for ClientRequestInputKeySet packets.

  Responds with BiInputKeySet containing the keybinding configuration.
  Currently returns empty bindings - client will use defaults.
  """

  @behaviour BezgelorProtocol.Handler

  alias BezgelorProtocol.Packets.World.{ClientRequestInputKeySet, BiInputKeySet}
  alias BezgelorProtocol.{PacketReader, PacketWriter}

  require Logger

  @impl true
  def handle(payload, state) do
    reader = PacketReader.new(payload)
    {:ok, packet, _reader} = ClientRequestInputKeySet.read(reader)
    handle_request(packet, state)
  end

  defp handle_request(packet, state) do
    # Respond with empty keybindings - client will use defaults
    # Character ID 0 means account-level bindings, otherwise character-specific
    character_id = packet.character_id

    Logger.debug("ClientRequestInputKeySet for character_id=#{character_id}")

    response = %BiInputKeySet{
      bindings: [],
      character_id: character_id
    }

    writer = PacketWriter.new()
    {:ok, writer} = BiInputKeySet.write(response, writer)
    response_data = PacketWriter.to_binary(writer)

    {:reply_world_encrypted, {:bi_input_key_set, response_data}, state}
  end
end
