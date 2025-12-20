defmodule BezgelorWorld.Abilities do
  @moduledoc """
  Provides default abilities for each class.

  Each class has starter abilities that are placed on the action bar
  for new characters.
  """

  @max_tier_points 42

  # Class auto-attack Spell4BaseIds
  @class_attacks %{
    # Warrior - Sword Strike
    1 => 398,
    # Engineer - Heavy Shot
    2 => 24727,
    # Esper - Psyblade Strike
    3 => 960,
    # Medic - Shock Paddles
    4 => 26531,
    # Stalker - Claw Slash
    5 => 2656,
    # Spellslinger - Pistol Shot
    7 => 435
  }

  # Spellbook abilities for each class (spell_id = Spell4BaseId)
  @class_spellbook_abilities %{
    1 => [
      # Warrior: Relentless Strikes (SpellLevel)
      %{spell_id: 18309, slot: 0, tier: 1},
      # Warrior: Sword Strike (class attack)
      %{spell_id: 398, slot: 3, tier: 1}
    ],
    2 => [
      # Engineer: Bolt Caster (SpellLevel)
      %{spell_id: 20763, slot: 0, tier: 1},
      # Engineer: Heavy Shot (class attack)
      %{spell_id: 24727, slot: 3, tier: 1}
    ],
    3 => [
      # Esper: Telekinetic Strike (SpellLevel)
      %{spell_id: 19102, slot: 0, tier: 1},
      # Esper: Psyblade Strike (class attack)
      %{spell_id: 960, slot: 3, tier: 1}
    ],
    4 => [
      # Medic: Gamma Rays (SpellLevel)
      %{spell_id: 16322, slot: 0, tier: 1},
      # Medic: Shock Paddles (class attack)
      %{spell_id: 26531, slot: 3, tier: 1}
    ],
    5 => [
      # Stalker: Shred (SpellLevel)
      %{spell_id: 23148, slot: 0, tier: 1},
      # Stalker: Claw Slash (class attack)
      %{spell_id: 2656, slot: 3, tier: 1}
    ],
    7 => [
      # Spellslinger: Quick Draw (Spell4BaseId)
      %{spell_id: 27638, slot: 0, tier: 1},
      # Spellslinger: Charged Shot (Spell4BaseId)
      %{spell_id: 20684, slot: 1, tier: 1},
      # Spellslinger: Gate (Spell4BaseId)
      %{spell_id: 20325, slot: 2, tier: 1},
      # Spellslinger: Pistol Shot
      %{spell_id: 435, slot: 3, tier: 1}
    ]
  }

  # Action set abilities for each class (SpellLevel entries)
  @class_action_set_abilities %{
    1 => [
      # Warrior: Relentless Strikes
      %{spell_id: 18309, slot: 0, tier: 1}
    ],
    2 => [
      # Engineer: Bolt Caster
      %{spell_id: 20763, slot: 0, tier: 1}
    ],
    3 => [
      # Esper: Telekinetic Strike
      %{spell_id: 19102, slot: 0, tier: 1}
    ],
    4 => [
      # Medic: Gamma Rays
      %{spell_id: 16322, slot: 0, tier: 1}
    ],
    5 => [
      # Stalker: Shred
      %{spell_id: 23148, slot: 0, tier: 1}
    ],
    7 => [
      # Spellslinger: Quick Draw (Spell4BaseId)
      %{spell_id: 27638, slot: 0, tier: 1},
      # Spellslinger: Charged Shot (Spell4BaseId)
      %{spell_id: 20684, slot: 1, tier: 1},
      # Spellslinger: Gate (Spell4BaseId)
      %{spell_id: 20325, slot: 2, tier: 1}
    ]
  }

  @doc """
  Get the default spellbook abilities for a class.

  Returns a list of ability maps with spell_id, slot, and tier.
  Falls back to Warrior abilities if class is unknown.
  """
  @spec get_class_spellbook_abilities(non_neg_integer()) :: [map()]
  def get_class_spellbook_abilities(class_id) do
    Map.get(@class_spellbook_abilities, class_id, Map.get(@class_spellbook_abilities, 1, []))
  end

  @doc """
  Get the default action set abilities for a class.

  These should mirror NexusForever's level 1 SpellLevel entries.
  """
  @spec get_class_action_set_abilities(non_neg_integer()) :: [map()]
  def get_class_action_set_abilities(class_id) do
    Map.get(
      @class_action_set_abilities,
      class_id,
      get_class_spellbook_abilities(class_id)
    )
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
    Map.get(@class_attacks, class_id, 398)
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
  """
  @spec build_ability_book(non_neg_integer()) :: [map()]
  def build_ability_book(class_id) do
    abilities = get_class_spellbook_abilities(class_id)

    Enum.flat_map(abilities, fn ability ->
      for spec_index <- 0..3 do
        %{
          spell4_base_id: ability.spell_id,
          tier: ability.tier,
          spec_index: spec_index
        }
      end
    end)
  end

  @doc """
  Build ability book entries using action set shortcut tiers per spec.
  """
  @spec build_ability_book_for_specs([map()], map()) :: [map()]
  def build_ability_book_for_specs(abilities, shortcuts_by_spec) do
    Enum.flat_map(abilities, fn ability ->
      for spec_index <- 0..3 do
        shortcut = shortcuts_by_spec |> Map.get(spec_index, %{}) |> Map.get(ability.spell_id)
        tier = if shortcut, do: shortcut.tier, else: ability.tier

        %{
          spell4_base_id: ability.spell_id,
          tier: tier,
          spec_index: spec_index
        }
      end
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
end
