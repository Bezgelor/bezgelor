defmodule BezgelorProtocol.Handler.WorldEntryHandler do
  @moduledoc """
  Handler for ClientEnteredWorld packets.

  Called when the client finishes loading the world after receiving
  ServerWorldEnter. Spawns the player entity.

  ## Flow

  1. Verify character is selected
  2. Generate unique entity GUID
  3. Create player entity
  4. Send ServerEntityCreate to spawn the player
  5. Mark session as in-world
  """

  @behaviour BezgelorProtocol.Handler

  import Bitwise

  alias BezgelorProtocol.Packets.World.ServerEntityCreate
  alias BezgelorProtocol.PacketWriter
  alias BezgelorCore.Entity

  require Logger

  @impl true
  def handle(_payload, state) do
    character = state.session_data[:character]

    if is_nil(character) do
      Logger.warning("ClientEnteredWorld received without character selected")
      {:error, :no_character_selected}
    else
      spawn_player(character, state)
    end
  end

  defp spawn_player(character, state) do
    # Generate unique entity GUID
    guid = generate_guid(character)

    # Create entity from character data
    entity = Entity.from_character(character, guid)

    # Build entity spawn packet
    entity_packet = ServerEntityCreate.from_entity(entity)

    # Encode packet
    writer = PacketWriter.new()
    {:ok, writer} = ServerEntityCreate.write(entity_packet, writer)
    packet_data = PacketWriter.to_binary(writer)

    # Update session state
    state = put_in(state.session_data[:entity_guid], guid)
    state = put_in(state.session_data[:entity], entity)
    state = put_in(state.session_data[:in_world], true)

    Logger.info(
      "Player '#{character.name}' (GUID: #{guid}) entered world at " <>
        "#{inspect(entity.position)}"
    )

    {:reply, :server_entity_create, packet_data, state}
  end

  # Generate a unique GUID for the entity
  # In a production system, this would be managed by WorldManager
  defp generate_guid(character) do
    # Simple GUID: combine character ID with timestamp for uniqueness
    # High bits: entity type (1 = player)
    # Low bits: character_id + monotonic counter
    entity_type = 1
    counter = :erlang.unique_integer([:positive, :monotonic])

    # Format: [type:4][reserved:12][character_id:24][counter:24]
    bsl(entity_type, 60) ||| bsl(character.id &&& 0xFFFFFF, 24) ||| (counter &&& 0xFFFFFF)
  end
end
