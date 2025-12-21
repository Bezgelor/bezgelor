defmodule BezgelorProtocol.Handler.EntitySelectHandler do
  @moduledoc """
  Handler for ClientEntitySelect packets.

  Called when the player selects/targets an entity in the game world.
  A GUID of 0 means the player has deselected their current target.
  """

  @behaviour BezgelorProtocol.Handler
  @compile {:no_warn_undefined, [BezgelorWorld.World.Instance]}

  alias BezgelorProtocol.Packets.World.ClientEntitySelect
  alias BezgelorProtocol.PacketReader

  require Logger

  @impl true
  def handle(payload, state) do
    reader = PacketReader.new(payload)
    {:ok, packet, _reader} = ClientEntitySelect.read(reader)

    player_name = state.session_data[:character_name] || "Unknown"
    player_guid = state.session_data[:entity_guid]

    if packet.guid > 0 do
      log_entity_selection(player_name, player_guid, packet.guid, state)
      # TODO: Store target in session/player state for combat targeting
    else
      Logger.debug("[EntitySelect] #{player_name} (#{player_guid}) deselected target")
    end

    {:ok, state}
  end

  defp log_entity_selection(player_name, player_guid, target_guid, state) do
    # Zone.Instance is keyed by world_id, not zone_id
    world_id = state.session_data[:world_id]
    instance_id = state.session_data[:instance_id] || 1

    if world_id do
      try do
        case BezgelorWorld.World.Instance.get_entity({world_id, instance_id}, target_guid) do
          {:ok, entity} ->
            {x, y, z} = entity.position
            {rx, ry, rz} = entity.rotation

            Logger.info("""
            [EntitySelect] #{player_name} (#{player_guid}) selected entity:
              GUID: #{target_guid}
              Type: #{entity.type}
              Name: #{entity.name || "unnamed"}
              Level: #{entity.level}
              Health: #{entity.health}/#{entity.max_health}
              Position: (#{Float.round(x, 2)}, #{Float.round(y, 2)}, #{Float.round(z, 2)})
              Rotation: (#{Float.round(rx, 2)}, #{Float.round(ry, 2)}, #{Float.round(rz, 2)})
              CreatureID: #{entity.creature_id || "N/A"}
              DisplayInfo: #{entity.display_info}
              Faction: #{entity.faction}
              Flags: #{entity.flags}
              IsDead: #{entity.is_dead}
            """)

          :error ->
            Logger.debug(
              "[EntitySelect] #{player_name} (#{player_guid}) selected unknown entity: #{target_guid}"
            )
        end
      catch
        :exit, {:noproc, _} ->
          Logger.debug(
            "[EntitySelect] #{player_name} (#{player_guid}) selected entity #{target_guid} (world #{world_id} instance #{instance_id} not active)"
          )
      end
    else
      Logger.debug(
        "[EntitySelect] #{player_name} (#{player_guid}) selected entity #{target_guid} (no world context)"
      )
    end
  end
end
