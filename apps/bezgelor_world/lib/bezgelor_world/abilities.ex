defmodule BezgelorWorld.Abilities do
  @moduledoc """
  Provides default abilities for each class.

  Each class has starter abilities that are placed on the action bar
  for new characters.
  """

  @max_tier_points 42

  alias BezgelorData

  # Class auto-attack Spell4BaseIds
  @class_attacks %{
    # Warrior - Sword Strike
    1 => 55543,
    # Engineer - Heavy Shot
    2 => 40510,
    # Esper - Psyblade Strike
    3 => 960,
    # Medic - Shock Paddles
    4 => 55533,
    # Stalker - Right Click Attack
    5 => 55198,
    # Spellslinger - Pistol Shot
    7 => 55665
  }

  # Spellbook abilities for each class (spell_id = Spell4 ID for telegraph lookup)
  @class_spellbook_abilities %{
    1 => [
      # Warrior: Relentless Strikes (SpellLevel)
      %{spell_id: 32078, slot: 0, tier: 1},
      # Warrior: Rampage (SpellLevel)
      %{spell_id: 58524, slot: 1, tier: 1},
      # Warrior: Kick (SpellLevel)
      %{spell_id: 58591, slot: 2, tier: 1},
      # Warrior: Sword Strike (class attack)
      %{spell_id: 55543, slot: 3, tier: 1}
    ],
    2 => [
      # Engineer: Pulse Blast (SpellLevel)
      %{spell_id: 42276, slot: 0, tier: 1},
      # Engineer: Electrocute (SpellLevel)
      %{spell_id: 41276, slot: 1, tier: 1},
      # Engineer: Zap (SpellLevel)
      %{spell_id: 41438, slot: 2, tier: 1},
      # Engineer: Heavy Shot (class attack)
      %{spell_id: 40510, slot: 3, tier: 1}
    ],
    3 => [
      # Esper: Telekinetic Strike (SpellLevel)
      %{spell_id: 32893, slot: 0, tier: 1},
      # Esper: Mind Burst (SpellLevel)
      %{spell_id: 32809, slot: 1, tier: 1},
      # Esper: Crush (SpellLevel)
      %{spell_id: 32812, slot: 2, tier: 1},
      # Esper: Psyblade Strike (class attack)
      %{spell_id: 960, slot: 3, tier: 1}
    ],
    4 => [
      # Medic: Discharge (SpellLevel)
      %{spell_id: 58832, slot: 0, tier: 1},
      # Medic: Gamma Rays (SpellLevel)
      %{spell_id: 29874, slot: 1, tier: 1},
      # Medic: Paralytic Surge (SpellLevel)
      %{spell_id: 42352, slot: 2, tier: 1},
      # Medic: Shock Paddles (class attack)
      %{spell_id: 55533, slot: 3, tier: 1}
    ],
    5 => [
      # Stalker: Shred (SpellLevel)
      %{spell_id: 38765, slot: 0, tier: 1},
      # Stalker: Impale (SpellLevel)
      %{spell_id: 38779, slot: 1, tier: 1},
      # Stalker: Stagger (SpellLevel)
      %{spell_id: 38791, slot: 2, tier: 1},
      # Stalker: Right Click Attack (class attack)
      %{spell_id: 55198, slot: 3, tier: 1}
    ],
    7 => [
      # Spellslinger: Quick Draw (Spell4 ID - telegraph lookup uses this)
      %{spell_id: 43468, slot: 0, tier: 1},
      # Spellslinger: Charged Shot (Spell4 ID)
      %{spell_id: 34718, slot: 1, tier: 1},
      # Spellslinger: Gate (Spell4 ID - must be 34355, not 20325, for telegraph 142)
      %{spell_id: 34355, slot: 2, tier: 1},
      # Spellslinger: Pistol Shot
      %{spell_id: 55665, slot: 3, tier: 1}
    ]
  }

  # Action set abilities for each class (SpellLevel entries)
  @class_action_set_abilities %{
    1 => [
      # Warrior: Relentless Strikes
      %{spell_id: 32078, slot: 0, tier: 1},
      # Warrior: Rampage
      %{spell_id: 58524, slot: 1, tier: 1},
      # Warrior: Kick
      %{spell_id: 58591, slot: 2, tier: 1}
    ],
    2 => [
      # Engineer: Pulse Blast
      %{spell_id: 42276, slot: 0, tier: 1},
      # Engineer: Electrocute
      %{spell_id: 41276, slot: 1, tier: 1},
      # Engineer: Zap
      %{spell_id: 41438, slot: 2, tier: 1}
    ],
    3 => [
      # Esper: Telekinetic Strike
      %{spell_id: 32893, slot: 0, tier: 1},
      # Esper: Mind Burst
      %{spell_id: 32809, slot: 1, tier: 1},
      # Esper: Crush
      %{spell_id: 32812, slot: 2, tier: 1}
    ],
    4 => [
      # Medic: Discharge
      %{spell_id: 58832, slot: 0, tier: 1},
      # Medic: Gamma Rays
      %{spell_id: 29874, slot: 1, tier: 1},
      # Medic: Paralytic Surge
      %{spell_id: 42352, slot: 2, tier: 1}
    ],
    5 => [
      # Stalker: Shred
      %{spell_id: 38765, slot: 0, tier: 1},
      # Stalker: Impale
      %{spell_id: 38779, slot: 1, tier: 1},
      # Stalker: Stagger
      %{spell_id: 38791, slot: 2, tier: 1}
    ],
    7 => [
      # Spellslinger: Quick Draw (Spell4 ID)
      %{spell_id: 43468, slot: 0, tier: 1},
      # Spellslinger: Charged Shot (Spell4 ID)
      %{spell_id: 34718, slot: 1, tier: 1},
      # Spellslinger: Gate (Spell4 ID)
      %{spell_id: 34355, slot: 2, tier: 1}
    ]
  }

  @doc """
  Get the default spellbook abilities for a class.

  Returns a list of ability maps with spell_id, slot, and tier.
  Falls back to Warrior abilities if class is unknown.
  """
  @spec get_class_spellbook_abilities(non_neg_integer()) :: [map()]
  def get_class_spellbook_abilities(class_id) do
    class_id
    |> build_spellbook_from_data()
    |> fallback_to_class(@class_spellbook_abilities, class_id)
  end

  @doc """
  Get the default action set abilities for a class.

  These should mirror NexusForever's level 1 SpellLevel entries.
  """
  @spec get_class_action_set_abilities(non_neg_integer()) :: [map()]
  def get_class_action_set_abilities(class_id) do
    class_id
    |> build_action_set_from_data()
    |> fallback_to_class(@class_action_set_abilities, class_id)
  end

  @doc """
  Get the default abilities for a class.
  """
  @spec get_class_abilities(non_neg_integer()) :: [map()]
  def get_class_abilities(class_id) do
    get_class_spellbook_abilities(class_id)
  end

  @doc """
  Get the primary attack spell ID for a class.
  """
  @spec get_primary_attack(non_neg_integer()) :: non_neg_integer()
  def get_primary_attack(class_id) do
    # Default to Warrior attack
    Map.get(@class_attacks, class_id, 55543)
  end

  @doc """
  Get max tier points for a player.
  """
  @spec max_tier_points() :: non_neg_integer()
  def max_tier_points, do: @max_tier_points

  @doc """
  Build ability book entries for ServerAbilityBook packet.

  Returns a list of spell entries suitable for the packet.
  Class abilities need an entry for each spec (0-3).
  Uses resolve_spell4_base_id to get Spell4Base IDs with icons for display.
  """
  @spec build_ability_book(non_neg_integer()) :: [map()]
  def build_ability_book(class_id) do
    abilities = get_class_spellbook_abilities(class_id)

    Enum.flat_map(abilities, fn ability ->
      # Resolve to Spell4Base ID with icon for display
      base_id = resolve_spell4_base_id(ability.spell_id, class_id)

      ability
      |> ability_spec_indices()
      |> Enum.map(fn spec_index ->
        %{
          spell4_base_id: base_id,
          tier: ability.tier,
          spec_index: spec_index
        }
      end)
    end)
  end

  @doc """
  Build ability book entries using action set shortcut tiers per spec.

  Uses resolve_spell4_base_id to find Spell4Base entries with proper icons
  for UI display. The ability.spell_id is the Spell4 ID (for casting/telegraphs),
  but the ability book needs Spell4Base IDs that have icons.
  """
  @spec build_ability_book_for_specs([map()], map(), non_neg_integer()) :: [map()]
  def build_ability_book_for_specs(abilities, shortcuts_by_spec, class_id \\ 0) do
    Enum.flat_map(abilities, fn ability ->
      # Resolve to Spell4Base ID with icon for ability book display
      base_id = resolve_spell4_base_id(ability.spell_id, class_id)

      ability
      |> ability_spec_indices()
      |> Enum.map(fn spec_index ->
        shortcut = shortcuts_by_spec |> Map.get(spec_index, %{}) |> Map.get(ability.spell_id)
        tier = if shortcut, do: shortcut.tier, else: ability.tier

        %{
          spell4_base_id: base_id,
          tier: tier,
          spec_index: spec_index
        }
      end)
    end)
  end

  @doc """
  Build action set entries for ServerActionSet packet.
  """
  @spec build_action_set(non_neg_integer()) :: [map()]
  def build_action_set(class_id) do
    abilities = get_class_action_set_abilities(class_id)

    abilities
    |> Enum.with_index()
    |> Enum.map(fn {ability, index} ->
      %{
        type: :spell,
        object_id: ability.spell_id,
        slot: ability.slot,
        inventory_index: index,
        ui_location: ability.slot
      }
    end)
  end

  @doc """
  Build action set entries from persisted shortcuts, grouped by spec index.
  """
  @spec build_action_set_from_shortcuts(map()) :: map()
  def build_action_set_from_shortcuts(shortcuts_by_spec) do
    Enum.reduce(shortcuts_by_spec, %{}, fn {spec_index, shortcuts}, acc ->
      actions =
        shortcuts
        |> Enum.sort_by(& &1.slot)
        |> Enum.with_index()
        |> Enum.map(fn {shortcut, index} ->
          %{
            type: shortcut_type_to_atom(shortcut.shortcut_type),
            object_id: shortcut.object_id,
            slot: shortcut.slot,
            inventory_index: index,
            ui_location: shortcut.slot
          }
        end)

      Map.put(acc, spec_index, actions)
    end)
  end

  defp shortcut_type_to_atom(0), do: :none
  defp shortcut_type_to_atom(1), do: :bag_item
  defp shortcut_type_to_atom(2), do: :macro
  defp shortcut_type_to_atom(3), do: :game_command
  defp shortcut_type_to_atom(4), do: :spell
  defp shortcut_type_to_atom(_), do: :none

  defp build_action_set_from_data(class_id) do
    case build_level_one_spells(class_id) do
      [] -> []
      spells -> spells
    end
  end

  defp build_spellbook_from_data(class_id) do
    spells = build_level_one_spells(class_id)
    attack_id = get_class_attack_id(class_id)

    if spells == [] and attack_id == nil do
      []
    else
      spellbook =
        spells
        |> Enum.map(fn ability -> %{ability | slot: ability.slot} end)

      if attack_id do
        spellbook ++ [%{spell_id: attack_id, slot: 3, tier: 1, class_ability: true}]
      else
        spellbook
      end
    end
  end

  defp build_level_one_spells(class_id) do
    class_id
    |> BezgelorData.spell_levels_for_class_level(1)
    |> Enum.sort_by(& &1.id)
    |> Enum.reduce({[], 0}, fn entry, {acc, index} ->
      spell_id = resolve_spell_id(Map.get(entry, :spell4Id), class_id)

      if spell_id do
        {[%{spell_id: spell_id, slot: index, tier: 1, class_ability: true} | acc], index + 1}
      else
        {acc, index}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp get_class_attack_id(class_id) do
    with {:ok, class_entry} <- BezgelorData.get_class_entry(class_id) do
      primary =
        cond do
          Map.get(class_entry, :spell4IdAttackPrimary01, 0) > 0 ->
            Map.get(class_entry, :spell4IdAttackPrimary01)

          Map.get(class_entry, :spell4IdAttackPrimary00, 0) > 0 ->
            Map.get(class_entry, :spell4IdAttackPrimary00)

          true ->
            nil
        end

      if primary, do: resolve_spell_id(primary, class_id), else: Map.get(@class_attacks, class_id)
    else
      :error -> Map.get(@class_attacks, class_id)
    end
  end

  defp resolve_spell_id(nil, _class_id), do: nil

  defp resolve_spell_id(spell4_id, _class_id) when is_integer(spell4_id) do
    # Return the Spell4 ID as-is. This is used for ability items and spell packets,
    # which need the Spell4 ID for telegraph lookup.
    # For ability book display, use resolve_spell4_base_id/2 to get the ID with icons.
    spell4_id
  end

  @doc """
  Resolve a Spell4 ID to its Spell4Base ID for ability book display.

  The ability book needs Spell4Base IDs that have proper icons. Some Spell4 IDs
  exist as Spell4Base entries but with empty icons. This function finds the
  correct Spell4Base entry by:
  1. Checking spell4BaseIdBaseSpell link
  2. Falling back to name-matching if no link exists

  For casting/telegraphs, use the Spell4 ID directly instead.
  """
  @spec resolve_spell4_base_id(non_neg_integer(), non_neg_integer()) :: non_neg_integer()
  def resolve_spell4_base_id(spell4_id, class_id) when is_integer(spell4_id) do
    case BezgelorData.get_spell4_entry(spell4_id) do
      {:ok, entry} ->
        base_id = Map.get(entry, :spell4BaseIdBaseSpell, 0)

        if base_id > 0 do
          base_id
        else
          # No direct link - find by name matching for proper icon
          resolve_spell4_base_from_description(entry, class_id) || spell4_id
        end

      :error ->
        spell4_id
    end
  end

  def resolve_spell4_base_id(nil, _class_id), do: nil

  # Name-matching resolution for finding Spell4Base entries with icons
  defp resolve_spell4_base_from_description(entry, class_id) do
    case extract_spell_name(Map.get(entry, :description, "")) do
      nil -> nil
      name -> pick_spell4_base_id(name, class_id)
    end
  end

  defp extract_spell_name(description) when is_binary(description) do
    description
    |> String.split(" - ")
    |> Enum.drop(1)
    |> List.first()
    |> case do
      nil -> nil
      name -> String.trim(name)
    end
  end

  defp extract_spell_name(_), do: nil

  defp pick_spell4_base_id(name, class_id) do
    candidates =
      name
      |> spell4_base_candidates()
      |> filter_spell_type()
      |> filter_with_icon()

    result =
      candidates
      |> Enum.map(fn entry -> {score_spell4_base(entry, class_id), entry} end)
      |> Enum.max_by(
        fn {score, entry} ->
          {score, Map.get(entry, :weaponSlot, 0), Map.get(entry, :castBarType, 0),
           -Map.get(entry, :id, 0)}
        end,
        fn -> nil end
      )

    case result do
      nil -> nil
      {_score, entry} -> Map.get(entry, :id)
    end
  end

  defp spell4_base_candidates(name) do
    key = String.downcase(name)
    Map.get(spell4_base_name_index(), key, [])
  end

  defp filter_spell_type([]), do: []

  defp filter_spell_type(candidates) do
    class_spells =
      Enum.filter(candidates, fn entry -> Map.get(entry, :spell4SpellTypesIdSpellType) == 5 end)

    if class_spells == [], do: candidates, else: class_spells
  end

  # Only keep entries that have an icon (for proper UI display)
  defp filter_with_icon(candidates) do
    with_icon = Enum.filter(candidates, fn entry ->
      icon = Map.get(entry, :icon, "")
      icon != "" and icon != nil
    end)

    if with_icon == [], do: candidates, else: with_icon
  end

  defp spell4_base_name_index do
    case :persistent_term.get({__MODULE__, :spell4_base_name_index}, nil) do
      nil ->
        index =
          BezgelorData.list_spell4_base_entries()
          |> Enum.reduce(%{}, fn entry, acc ->
            case BezgelorData.text_or_nil(Map.get(entry, :localizedTextIdName)) do
              nil ->
                acc

              name ->
                key = String.downcase(name)
                Map.update(acc, key, [entry], &[entry | &1])
            end
          end)

        :persistent_term.put({__MODULE__, :spell4_base_name_index}, index)
        index

      index ->
        index
    end
  end

  @class_icon_hints %{
    1 => ["warrior"],
    2 => ["engineer"],
    3 => ["esper"],
    4 => ["medic"],
    5 => ["stalker", "stlkr", "shadow"],
    7 => ["spellslinger"]
  }

  defp score_spell4_base(entry, class_id) do
    hints = Map.get(@class_icon_hints, class_id, [])
    icon = Map.get(entry, :icon, "")
    entry_class = Map.get(entry, :classIdPlayer, 0)
    spell_class = Map.get(entry, :spellClass, 0)
    cast_bar_type = Map.get(entry, :castBarType, 0)
    icon_match = icon_matches?(icon, hints)

    score = 0

    # Icon match is the strongest signal - if icon contains class name, it's likely correct
    # This overrides most other considerations
    score = if icon_match, do: score + 20, else: score

    # Class scoring:
    # - Matching class gets big bonus
    # - Wrong-class entries are penalized unless icon matches
    score =
      cond do
        entry_class == class_id -> score + 15
        icon_match -> score + 5
        entry_class > 0 and spell_class > 0 -> score + 2
        entry_class > 0 -> score + 0
        entry_class == 0 -> score - 5
        true -> score - 10
      end

    # Data quality bonuses (smaller weight than icon match)
    score = if spell_class > 0, do: score + 3, else: score
    score = if cast_bar_type > 0, do: score + 2, else: score

    # Basic bonuses
    score = if icon != "", do: score + 1, else: score
    score = if Map.get(entry, :weaponSlot, 0) > 0, do: score + 1, else: score
    score
  end

  defp icon_matches?(_icon, []), do: false

  defp icon_matches?(icon, hints) do
    icon = String.downcase(icon)
    Enum.any?(hints, fn hint -> String.contains?(icon, hint) end)
  end

  defp ability_spec_indices(%{spell_id: spell_id} = ability) do
    if Map.get(ability, :class_ability, false) do
      0..3
    else
      case spell_type(spell_id) do
        5 -> 0..3
        _ -> [0]
      end
    end
  end

  defp spell_type(spell_id) do
    case BezgelorData.get_spell4_base_entry(spell_id) do
      {:ok, entry} -> Map.get(entry, :spell4SpellTypesIdSpellType)
      :error -> nil
    end
  end

  defp fallback_to_class([], fallback_map, class_id) do
    fallback_map
    |> Map.get(class_id, Map.get(fallback_map, 1, []))
    |> Enum.map(fn ability ->
      Map.put_new(ability, :class_ability, true)
    end)
  end

  defp fallback_to_class(list, _fallback_map, _class_id), do: list
end
