defmodule BezgelorCore.CreatureTemplate do
  @moduledoc """
  Static data defining creature types.

  Creature templates define the base properties for each creature type
  in the game. When a creature is spawned, it uses the template to
  determine its stats, behavior, and rewards.

  ## AI Types

  - `:passive` - Does not attack unless provoked
  - `:aggressive` - Attacks players on sight within aggro range
  - `:defensive` - Attacks if nearby friendly creatures are attacked

  ## Factions

  - `:hostile` - Always hostile to players
  - `:neutral` - Neutral, can become hostile if attacked
  - `:friendly` - Friendly to players, cannot be attacked
  """

  @type ai_type :: :passive | :aggressive | :defensive
  @type faction :: :hostile | :neutral | :friendly

  @type reputation_reward :: {faction_id :: non_neg_integer(), amount :: integer()}

  # Default social aggro range in meters
  @social_aggro_range 10.0

  @type t :: %__MODULE__{
          id: non_neg_integer(),
          name: String.t(),
          level: non_neg_integer(),
          max_health: non_neg_integer(),
          faction: faction(),
          display_info: non_neg_integer(),
          ai_type: ai_type(),
          aggro_range: float(),
          leash_range: float(),
          social_aggro_range: float() | nil,
          respawn_time: non_neg_integer(),
          xp_reward: non_neg_integer(),
          loot_table_id: non_neg_integer() | nil,
          damage_min: non_neg_integer(),
          damage_max: non_neg_integer(),
          attack_speed: non_neg_integer(),
          reputation_rewards: [reputation_reward()]
        }

  defstruct [
    :id,
    :name,
    level: 1,
    max_health: 100,
    faction: :hostile,
    display_info: 0,
    ai_type: :passive,
    aggro_range: 10.0,
    leash_range: 40.0,
    social_aggro_range: nil,
    respawn_time: 30_000,
    xp_reward: 50,
    loot_table_id: nil,
    damage_min: 5,
    damage_max: 10,
    attack_speed: 2000,
    reputation_rewards: []
  ]

  @doc """
  Get a creature template by ID.

  Returns the template struct or nil if not found.
  """
  @spec get(non_neg_integer()) :: t() | nil
  def get(id), do: Map.get(templates(), id)

  @doc """
  Check if a creature template exists.
  """
  @spec exists?(non_neg_integer()) :: boolean()
  def exists?(id), do: Map.has_key?(templates(), id)

  @doc """
  Get all template IDs.
  """
  @spec all_ids() :: [non_neg_integer()]
  def all_ids, do: Map.keys(templates())

  @doc """
  Get all templates.
  """
  @spec all() :: [t()]
  def all, do: Map.values(templates())

  @doc """
  Check if this creature is aggressive.
  """
  @spec aggressive?(t()) :: boolean()
  def aggressive?(%__MODULE__{ai_type: :aggressive}), do: true
  def aggressive?(_), do: false

  @doc """
  Check if creature will attack players on sight.
  """
  @spec hostile?(t()) :: boolean()
  def hostile?(%__MODULE__{faction: :hostile}), do: true
  def hostile?(_), do: false

  @doc """
  Get social aggro range, with default fallback.

  Social aggro is the range within which nearby creatures of the same
  faction will join combat when one is attacked.
  """
  @spec social_aggro_range(t()) :: float()
  def social_aggro_range(%__MODULE__{social_aggro_range: range}) when is_number(range), do: range
  def social_aggro_range(_), do: @social_aggro_range

  @doc """
  Calculate damage for an attack.
  Returns a random value between damage_min and damage_max.
  """
  @spec roll_damage(t()) :: non_neg_integer()
  def roll_damage(%__MODULE__{damage_min: min_dmg, damage_max: max_dmg}) do
    Enum.random(min_dmg..max_dmg)
  end

  # Test creature templates
  defp templates do
    %{
      1 => %__MODULE__{
        id: 1,
        name: "Training Dummy",
        level: 1,
        max_health: 100,
        faction: :hostile,
        display_info: 1001,
        ai_type: :passive,
        aggro_range: 0.0,
        leash_range: 0.0,
        respawn_time: 10_000,
        xp_reward: 10,
        loot_table_id: nil,
        damage_min: 0,
        damage_max: 0,
        attack_speed: 0
      },
      2 => %__MODULE__{
        id: 2,
        name: "Forest Wolf",
        level: 3,
        max_health: 150,
        faction: :hostile,
        display_info: 1002,
        ai_type: :aggressive,
        aggro_range: 15.0,
        leash_range: 40.0,
        respawn_time: 30_000,
        xp_reward: 75,
        loot_table_id: 1,
        damage_min: 8,
        damage_max: 15,
        attack_speed: 2000,
        # Grants 10 reputation with Exiles (faction 166)
        reputation_rewards: [{166, 10}]
      },
      3 => %__MODULE__{
        id: 3,
        name: "Cave Spider",
        level: 5,
        max_health: 200,
        faction: :hostile,
        display_info: 1003,
        ai_type: :aggressive,
        aggro_range: 12.0,
        leash_range: 35.0,
        respawn_time: 45_000,
        xp_reward: 120,
        loot_table_id: 2,
        damage_min: 12,
        damage_max: 22,
        attack_speed: 1800
      },
      4 => %__MODULE__{
        id: 4,
        name: "Village Guard",
        level: 10,
        max_health: 500,
        faction: :friendly,
        display_info: 1004,
        ai_type: :defensive,
        aggro_range: 20.0,
        leash_range: 50.0,
        respawn_time: 120_000,
        xp_reward: 0,
        loot_table_id: nil,
        damage_min: 25,
        damage_max: 40,
        attack_speed: 2500
      },
      5 => %__MODULE__{
        id: 5,
        name: "Wandering Merchant",
        level: 1,
        max_health: 100,
        faction: :neutral,
        display_info: 1005,
        ai_type: :passive,
        aggro_range: 0.0,
        leash_range: 0.0,
        respawn_time: 60_000,
        xp_reward: 0,
        loot_table_id: nil,
        damage_min: 0,
        damage_max: 0,
        attack_speed: 0
      }
    }
  end
end
