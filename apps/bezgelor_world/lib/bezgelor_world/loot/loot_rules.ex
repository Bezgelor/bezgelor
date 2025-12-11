defmodule BezgelorWorld.Loot.LootRules do
  @moduledoc """
  Loot distribution rules for instanced content.

  ## Loot Methods

  - `:personal` - Each player gets their own loot (most modern method)
  - `:group_loot` - Group roll on rare+ items
  - `:need_before_greed` - Need/Greed/Pass system
  - `:master_loot` - Group leader assigns all loot
  - `:round_robin` - Alternating loot assignment

  ## Roll Types

  - `:need` - Player can use item (100 priority)
  - `:greed` - Player wants for other purposes (50 priority)
  - `:pass` - Player doesn't want (0 priority)
  """

  require Logger

  @type loot_method :: :personal | :group_loot | :need_before_greed | :master_loot | :round_robin
  @type roll_type :: :need | :greed | :pass
  @type roll_result :: %{
          character_id: non_neg_integer(),
          roll_type: roll_type(),
          roll_value: non_neg_integer()
        }

  @doc """
  Gets the default loot method for content type and difficulty.
  """
  @spec default_method(atom(), atom()) :: loot_method()
  def default_method(instance_type, difficulty) do
    case {instance_type, difficulty} do
      {:raid, _} -> :personal           # Modern raids use personal loot
      {:dungeon, :mythic_plus} -> :personal
      {:expedition, _} -> :personal
      _ -> :need_before_greed
    end
  end

  @doc """
  Determines if an item requires a roll.
  """
  @spec requires_roll?(map(), loot_method()) :: boolean()
  def requires_roll?(item, method) do
    case method do
      :personal -> false
      :master_loot -> false
      :round_robin -> false
      :group_loot -> item.quality >= 3       # Rare or better
      :need_before_greed -> item.quality >= 2 # Uncommon or better
    end
  end

  @doc """
  Calculates the winning roll from a list of rolls.
  """
  @spec determine_winner([roll_result()]) :: roll_result() | nil
  def determine_winner([]), do: nil
  def determine_winner(rolls) do
    # Filter out passes
    valid_rolls = Enum.reject(rolls, fn r -> r.roll_type == :pass end)

    case valid_rolls do
      [] -> nil
      rolls ->
        # Sort by: 1) roll_type priority (need > greed), 2) roll value
        rolls
        |> Enum.sort_by(fn r ->
          priority = if r.roll_type == :need, do: 100, else: 50
          {-priority, -r.roll_value}
        end)
        |> hd()
    end
  end

  @doc """
  Generates a random roll value (1-100).
  """
  @spec roll() :: non_neg_integer()
  def roll do
    :rand.uniform(100)
  end

  @doc """
  Checks if a character can roll need on an item.
  Need is typically restricted to classes/specs that can use the item.
  """
  @spec can_need?(map(), map()) :: boolean()
  def can_need?(character, item) do
    # Check class restriction
    class_allowed =
      case item[:class_restriction] do
        nil -> true
        classes when is_list(classes) -> character.class_id in classes
        _ -> true
      end

    # Check armor type
    armor_allowed =
      case item[:armor_type] do
        nil -> true
        armor_type -> can_equip_armor?(character.class_id, armor_type)
      end

    # Check weapon type
    weapon_allowed =
      case item[:weapon_type] do
        nil -> true
        weapon_type -> can_equip_weapon?(character.class_id, weapon_type)
      end

    class_allowed and armor_allowed and weapon_allowed
  end

  # Simplified armor proficiency check
  defp can_equip_armor?(class_id, armor_type) do
    # All classes in WildStar wear specific armor types
    # Warriors/Stalkers: Medium
    # Engineers: Heavy
    # Espers/Spellslingers/Medics: Light
    case {class_id, armor_type} do
      {1, :heavy} -> true    # Warrior
      {2, :light} -> true    # Esper
      {3, :light} -> true    # Spellslinger
      {4, :light} -> true    # Medic
      {5, :medium} -> true   # Stalker
      {6, :heavy} -> true    # Engineer
      _ -> false
    end
  end

  # Simplified weapon proficiency check
  defp can_equip_weapon?(_class_id, _weapon_type) do
    # Simplified - all classes can use all weapons in WildStar
    true
  end

  @doc """
  Applies loot luck bonus (for personal loot).
  Higher luck increases chance of better drops.
  """
  @spec apply_luck_bonus(non_neg_integer(), non_neg_integer()) :: non_neg_integer()
  def apply_luck_bonus(base_chance, luck) do
    bonus = div(luck, 10)  # 10% bonus per 100 luck
    min(base_chance + bonus, 100)
  end

  @doc """
  Calculates personal loot eligibility.
  Returns a list of eligible items for the character.
  """
  @spec calculate_personal_loot(map(), [map()], keyword()) :: [map()]
  def calculate_personal_loot(character, loot_table, opts \\ []) do
    luck = Keyword.get(opts, :luck, 0)

    loot_table
    |> Enum.filter(fn item ->
      # Check eligibility
      can_need?(character, item) or item[:bind_on_pickup] == false
    end)
    |> Enum.filter(fn item ->
      # Roll against drop chance
      chance = apply_luck_bonus(item.drop_chance || 100, luck)
      :rand.uniform(100) <= chance
    end)
  end
end
