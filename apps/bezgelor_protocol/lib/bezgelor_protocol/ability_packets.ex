defmodule BezgelorProtocol.AbilityPackets do
  @moduledoc """
  Builds ability-related packets for initial character load.
  """

  @compile {:no_warn_undefined, [BezgelorWorld.Abilities]}

  alias BezgelorDb.{ActionSets, Inventory}
  alias BezgelorProtocol.PacketWriter

  alias BezgelorProtocol.Packets.World.{
    ServerAbilityBook,
    ServerAbilityPoints,
    ServerActionSet,
    ServerActionSetClearCache,
    ServerAmpList,
    ServerCooldownList,
    ServerItemAdd
  }

  alias BezgelorWorld.Abilities

  require Logger

  @spec build(map()) :: [{atom(), binary()}]
  def build(character) do
    class_id = character.class || 1
    active_spec = character.active_spec || 0
    ability_points = Abilities.max_tier_points()

    spellbook_abilities = Abilities.get_class_spellbook_abilities(class_id)
    action_set_abilities = Abilities.get_class_action_set_abilities(class_id)

    ActionSets.ensure_default_shortcuts(character.id, action_set_abilities, active_spec,
      force: character.level == 1
    )

    shortcuts = ActionSets.list_shortcuts(character.id)
    shortcuts_by_spec = ActionSets.group_by_spec(shortcuts)
    spell_shortcuts_by_spec = ActionSets.spell_index_by_spec(shortcuts)

    ability_items =
      Inventory.ensure_ability_items(character.id, spellbook_abilities)
      |> Enum.map(fn item ->
        %ServerItemAdd{
          guid: item.id,
          item_id: item.item_id,
          location: :ability,
          bag_index: item.bag_index,
          stack_count: item.quantity,
          durability: item.durability
        }
      end)

    if class_id in [5, 7] do
      class_label = if class_id == 5, do: "Stalker", else: "Spellslinger"
      Logger.info("#{class_label} ability debug: level=#{character.level} spec=#{active_spec}")
      Logger.info("  action_set_abilities=#{inspect(action_set_abilities)}")
      Logger.info("  spellbook_abilities=#{inspect(spellbook_abilities)}")
      Logger.info("  shortcuts_spec0=#{inspect(Map.get(shortcuts_by_spec, 0, []))}")
      Logger.info("  ability_items=#{inspect(ability_items)}")
    end

    ability_book_data =
      encode_packet(
        %ServerAbilityBook{
          spells:
            Abilities.build_ability_book_for_specs(spellbook_abilities, spell_shortcuts_by_spec)
        },
        ServerAbilityBook
      )

    ability_points_data =
      encode_packet(
        %ServerAbilityPoints{
          ability_points: ability_points,
          total_ability_points: ability_points
        },
        ServerAbilityPoints
      )

    action_set_actions = Abilities.build_action_set_from_shortcuts(shortcuts_by_spec)

    action_set_sizes =
      for spec_index <- 0..3 do
        actions = Map.get(action_set_actions, spec_index, [])

        action_set_data =
          encode_packet(
            %ServerActionSet{
              spec_index: spec_index,
              unlocked: true,
              result: :ok,
              actions: actions
            },
            ServerActionSet
          )

        {spec_index, byte_size(action_set_data), length(actions), action_set_data}
      end

    clear_cache_data =
      encode_packet(
        %ServerActionSetClearCache{generate_chat_log_message: false},
        ServerActionSetClearCache
      )

    action_set_packets =
      Enum.map(action_set_sizes, fn {_spec_index, _size, _count, data} ->
        {:server_action_set, data}
      end)

    amp_list_packets =
      for spec_index <- 0..3 do
        amp_list_data =
          encode_packet(
            %ServerAmpList{
              spec_index: spec_index,
              amps: []
            },
            ServerAmpList
          )

        {:server_amp_list, amp_list_data}
      end

    ability_item_packets =
      Enum.map(ability_items, &{:server_item_add, encode_packet(&1, ServerItemAdd)})

    cooldown_list_data =
      encode_packet(
        %ServerCooldownList{cooldowns: []},
        ServerCooldownList
      )

    if class_id in [5, 7] do
      action_sizes =
        Enum.map(action_set_sizes, fn {spec_index, size, count, _} ->
          %{spec: spec_index, size: size, actions: count}
        end)

      Logger.info(
        "Ability packet sizes: class=#{class_id} ability_book=#{byte_size(ability_book_data)} " <>
          "action_sets=#{inspect(action_sizes)}"
      )
    end

    ability_item_packets ++
      [{:server_ability_book, ability_book_data}, {:server_ability_points, ability_points_data}] ++
      [{:server_action_set_clear_cache, clear_cache_data}] ++
      action_set_packets ++
      amp_list_packets ++
      [{:server_cooldown_list, cooldown_list_data}]
  end

  defp encode_packet(packet, module) do
    writer = PacketWriter.new()
    {:ok, writer} = module.write(packet, writer)
    PacketWriter.to_binary(writer)
  end
end
