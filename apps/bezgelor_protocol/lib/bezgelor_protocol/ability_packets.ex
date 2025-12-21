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

  @spec build(map()) :: {[{atom(), binary()}], list()}
  def build(character) do
    class_id = character.class || 1
    active_spec = character.active_spec || 0
    ability_points = Abilities.max_tier_points()

    spellbook_abilities = Abilities.get_class_spellbook_abilities(class_id)
    action_set_abilities = Abilities.get_class_action_set_abilities(class_id)

    # Resolve action set abilities to have both Spell4 ID (for casting) and Spell4Base ID (for icons)
    # object_id = Spell4Base ID (for ServerActionSet, matches ability items for icon lookup)
    # spell_id = Spell4 ID (for casting, telegraph lookup)
    resolved_action_set_abilities =
      Enum.map(action_set_abilities, fn ability ->
        base_id = Abilities.resolve_spell4_base_id(ability.spell_id, class_id)
        Map.put(ability, :object_id, base_id)
      end)

    ActionSets.ensure_default_shortcuts(character.id, resolved_action_set_abilities, active_spec,
      force: character.level == 1
    )

    shortcuts = ActionSets.list_shortcuts(character.id)
    shortcuts_by_spec = ActionSets.group_by_spec(shortcuts)
    spell_shortcuts_by_spec = ActionSets.spell_index_by_spec(shortcuts)

    # Resolve Spell4 IDs to Spell4Base IDs for ability items.
    # Ability items need Spell4Base IDs (with icons) for UI display,
    # same as the ability book uses.
    resolved_abilities =
      Enum.map(spellbook_abilities, fn ability ->
        base_id = Abilities.resolve_spell4_base_id(ability.spell_id, class_id)
        %{ability | spell_id: base_id}
      end)

    ability_items =
      Inventory.ensure_ability_items(character.id, resolved_abilities)
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
      Logger.debug("#{class_label} ability debug: level=#{character.level} spec=#{active_spec}")

      # Show original Spell4 IDs (for casting/telegraphs)
      original_ids = Enum.map(spellbook_abilities, & &1.spell_id)
      Logger.debug("  spellbook Spell4 IDs (casting): #{inspect(original_ids)}")

      # Show resolved Spell4Base IDs (for icons/display)
      resolved_ids = Enum.map(resolved_abilities, & &1.spell_id)
      Logger.debug("  resolved Spell4Base IDs (icons): #{inspect(resolved_ids)}")

      # Show ability item IDs being sent
      item_ids = Enum.map(ability_items, & &1.item_id)
      Logger.debug("  ability item IDs sent: #{inspect(item_ids)}")
    end

    ability_book_spells =
      Abilities.build_ability_book_for_specs(spellbook_abilities, spell_shortcuts_by_spec, class_id)

    if class_id in [5, 7] do
      Logger.debug("  ability_book_spells=#{inspect(ability_book_spells)}")
    end

    ability_book_data =
      encode_packet(
        %ServerAbilityBook{spells: ability_book_spells},
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

    if class_id in [5, 7] do
      spec0_actions = Map.get(action_set_actions, 0, [])
      object_ids = Enum.map(spec0_actions, & &1.object_id)
      Logger.debug("  action_set object_ids: #{inspect(object_ids)}")
    end

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

      Logger.debug(
        "Ability packet sizes: class=#{class_id} ability_book=#{byte_size(ability_book_data)} " <>
          "action_sets=#{inspect(action_sizes)}"
      )
    end

    packets =
      ability_item_packets ++
        [{:server_ability_book, ability_book_data}, {:server_ability_points, ability_points_data}] ++
        [{:server_action_set_clear_cache, clear_cache_data}] ++
        action_set_packets ++
        amp_list_packets ++
        [{:server_cooldown_list, cooldown_list_data}]

    {packets, shortcuts}
  end

  defp encode_packet(packet, module) do
    writer = PacketWriter.new()
    {:ok, writer} = module.write(packet, writer)
    PacketWriter.to_binary(writer)
  end
end
