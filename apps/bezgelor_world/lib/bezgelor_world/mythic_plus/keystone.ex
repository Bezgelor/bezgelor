defmodule BezgelorWorld.MythicPlus.Keystone do
  @moduledoc """
  Represents a Mythic+ keystone.

  Keystones are obtained after completing a Mythic dungeon and allow
  entry to Mythic+ dungeons. The keystone level determines difficulty
  and which affixes are active.

  ## Keystone Properties

  - `dungeon_id` - Which dungeon this key is for
  - `level` - Keystone level (2-30+)
  - `affix_ids` - Active affixes based on level

  ## Level Affix Unlocks

  - Level 2-3: 1 affix (tier 1)
  - Level 4-6: 2 affixes (tier 1 + tier 2)
  - Level 7-9: 3 affixes (tier 1 + tier 2 + tier 3)
  - Level 10+: 4 affixes (tier 1-3 + seasonal)
  """

  alias BezgelorData.Store

  defstruct [
    :character_id,
    :dungeon_id,
    :level,
    :affix_ids,
    :created_at,
    :expires_at,
    depleted: false
  ]

  @type t :: %__MODULE__{
          character_id: non_neg_integer(),
          dungeon_id: non_neg_integer(),
          level: non_neg_integer(),
          affix_ids: [non_neg_integer()],
          created_at: DateTime.t(),
          expires_at: DateTime.t(),
          depleted: boolean()
        }

  @doc """
  Creates a new keystone.
  """
  @spec new(non_neg_integer(), non_neg_integer(), non_neg_integer()) :: t()
  def new(character_id, dungeon_id, level) do
    %__MODULE__{
      character_id: character_id,
      dungeon_id: dungeon_id,
      level: level,
      affix_ids: get_affixes_for_level(level),
      created_at: DateTime.utc_now(),
      expires_at: weekly_reset_time()
    }
  end

  @doc """
  Upgrades a keystone based on completion time.
  """
  @spec upgrade(t(), non_neg_integer()) :: t()
  def upgrade(%__MODULE__{} = keystone, time_bonus) do
    new_level = keystone.level + time_bonus
    new_dungeon_id = random_dungeon_id()

    %{keystone |
      dungeon_id: new_dungeon_id,
      level: new_level,
      affix_ids: get_affixes_for_level(new_level),
      depleted: false
    }
  end

  @doc """
  Depletes a keystone after a failed run.
  """
  @spec deplete(t()) :: t()
  def deplete(%__MODULE__{} = keystone) do
    %{keystone |
      level: max(2, keystone.level - 1),
      depleted: true
    }
  end

  @doc """
  Checks if keystone is still valid.
  """
  @spec valid?(t()) :: boolean()
  def valid?(%__MODULE__{} = keystone) do
    DateTime.compare(DateTime.utc_now(), keystone.expires_at) == :lt
  end

  @doc """
  Gets affixes for a keystone level.
  """
  @spec get_affixes_for_level(non_neg_integer()) :: [non_neg_integer()]
  def get_affixes_for_level(level) when level < 2, do: []
  def get_affixes_for_level(level) do
    try do
      case Store.get_affixes_for_level(level) do
        affixes when is_list(affixes) and length(affixes) > 0 ->
          Enum.map(affixes, fn a ->
            cond do
              is_map(a) and Map.has_key?(a, "id") -> a["id"]
              is_map(a) and Map.has_key?(a, :id) -> a[:id]
              true -> nil
            end
          end)
          |> Enum.reject(&is_nil/1)

        _ ->
          default_affixes_for_level(level)
      end
    rescue
      _ -> default_affixes_for_level(level)
    end
  end

  @doc """
  Calculates the time bonus (keystone levels to add) based on completion time.
  """
  @spec calculate_time_bonus(non_neg_integer(), non_neg_integer()) :: non_neg_integer()
  def calculate_time_bonus(time_limit_ms, completion_time_ms) do
    cond do
      completion_time_ms <= time_limit_ms * 0.6 -> 3  # Under 60%: +3 levels
      completion_time_ms <= time_limit_ms * 0.8 -> 2  # Under 80%: +2 levels
      completion_time_ms <= time_limit_ms -> 1        # Under limit: +1 level
      true -> 0                                       # Over limit: depleted
    end
  end

  @doc """
  Gets the time limit for a dungeon at a given keystone level.
  """
  @spec get_time_limit(non_neg_integer(), non_neg_integer()) :: non_neg_integer()
  def get_time_limit(dungeon_id, level) do
    # Base time for the dungeon (could come from data)
    base_time = get_dungeon_base_time(dungeon_id)

    # Higher levels don't change time, but add affixes that slow you down
    base_time
  end

  # Private Functions

  defp default_affixes_for_level(level) do
    # Tier 1 affixes (level 2+)
    tier1 = [1, 2, 3]  # Example: Fortified, Tyrannical, Bolstering
    # Tier 2 affixes (level 4+)
    tier2 = [4, 5, 6]  # Example: Raging, Sanguine, Inspiring
    # Tier 3 affixes (level 7+)
    tier3 = [7, 8, 9]  # Example: Explosive, Quaking, Grievous
    # Seasonal affix (level 10+)
    seasonal = [10]

    week = current_week()

    affixes = []

    affixes = if level >= 2, do: [Enum.at(tier1, rem(week, 3)) | affixes], else: affixes
    affixes = if level >= 4, do: [Enum.at(tier2, rem(week, 3)) | affixes], else: affixes
    affixes = if level >= 7, do: [Enum.at(tier3, rem(week, 3)) | affixes], else: affixes
    affixes = if level >= 10, do: [hd(seasonal) | affixes], else: affixes

    Enum.reverse(affixes)
  end

  defp weekly_reset_time do
    # Calculate next Tuesday 9:00 AM UTC (typical reset time)
    now = DateTime.utc_now()
    days_until_tuesday = rem(9 - Date.day_of_week(now), 7)
    days_until_tuesday = if days_until_tuesday == 0, do: 7, else: days_until_tuesday

    now
    |> DateTime.add(days_until_tuesday * 24 * 60 * 60, :second)
    |> DateTime.truncate(:second)
    |> Map.put(:hour, 9)
    |> Map.put(:minute, 0)
    |> Map.put(:second, 0)
  end

  defp current_week do
    # Week number since some epoch
    div(System.system_time(:second), 7 * 24 * 60 * 60)
  end

  defp random_dungeon_id do
    # In production, get list of M+ eligible dungeons from data
    dungeons = [100, 101, 102, 103, 104, 105, 106, 107]
    Enum.random(dungeons)
  end

  defp get_dungeon_base_time(dungeon_id) do
    # Base time in milliseconds (30-45 minutes typically)
    case Store.get_instance(dungeon_id) do
      {:ok, instance} ->
        instance["mythic_time_limit"] || 30 * 60 * 1000

      _ ->
        30 * 60 * 1000  # Default 30 minutes
    end
  end
end
