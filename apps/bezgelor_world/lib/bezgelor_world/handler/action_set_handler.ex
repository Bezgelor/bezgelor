defmodule BezgelorWorld.Handler.ActionSetHandler do
  @moduledoc """
  Handles Limited Action Set updates.
  """

  @behaviour BezgelorProtocol.Handler

  alias BezgelorDb.ActionSets
  alias BezgelorProtocol.PacketReader
  alias BezgelorProtocol.PacketWriter

  alias BezgelorProtocol.Packets.World.{
    ClientRequestActionSetChanges,
    ServerAbilityPoints,
    ServerActionSet,
    ServerActionSetClearCache
  }

  alias BezgelorWorld.Abilities

  require Logger

  @impl true
  def handle(payload, state) do
    reader = PacketReader.new(payload)

    case ClientRequestActionSetChanges.read(reader) do
      {:ok, packet, _reader} ->
        handle_action_set_changes(packet, state)

      {:error, reason} ->
        Logger.warning("Failed to parse action set changes: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp handle_action_set_changes(packet, state) do
    character_id = state.session_data[:character_id]

    Logger.info(
      "ActionSetChanges: character_id=#{character_id} spec=#{packet.action_set_index} " <>
        "actions=#{inspect(packet.actions)} tiers=#{inspect(packet.action_tiers)} amps=#{inspect(packet.amps)}"
    )

    updated_shortcuts =
      ActionSets.apply_action_set_changes(
        character_id,
        packet.action_set_index,
        packet.actions,
        packet.action_tiers
      )

    Logger.info(
      "ActionSetChanges result: spec=#{packet.action_set_index} shortcuts=#{inspect(updated_shortcuts)}"
    )

    actions =
      updated_shortcuts
      |> ActionSets.group_by_spec()
      |> Abilities.build_action_set_from_shortcuts()
      |> Map.get(packet.action_set_index, [])

    action_set_packet = %ServerActionSet{
      spec_index: packet.action_set_index,
      unlocked: true,
      result: :ok,
      actions: actions
    }

    clear_cache_packet = %ServerActionSetClearCache{generate_chat_log_message: true}

    responses = [
      {:server_action_set_clear_cache,
       encode_packet(clear_cache_packet, ServerActionSetClearCache)},
      {:server_action_set, encode_packet(action_set_packet, ServerActionSet)}
    ]

    responses =
      if packet.action_tiers == [] do
        responses
      else
        ability_points = Abilities.max_tier_points()

        ability_points_packet = %ServerAbilityPoints{
          ability_points: ability_points,
          total_ability_points: ability_points
        }

        responses ++
          [{:server_ability_points, encode_packet(ability_points_packet, ServerAbilityPoints)}]
      end

    {:reply_multi_world_encrypted, responses, state}
  end

  defp encode_packet(packet, module) do
    writer = PacketWriter.new()
    {:ok, writer} = module.write(packet, writer)
    PacketWriter.to_binary(writer)
  end
end
