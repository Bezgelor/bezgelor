defmodule BezgelorWorld.Event.Rewards do
  @moduledoc """
  Reward calculation and distribution logic for public events and world bosses.

  This module contains pure functions for:
  - Calculating reward tiers based on contribution
  - Scaling rewards by tier multipliers
  - Distributing rewards to participants

  ## Reward Tiers

  Participants are assigned tiers based on their contribution percentage:
  - Gold: >= 80% contribution or top contributor
  - Silver: >= 50% contribution
  - Bronze: >= 20% contribution
  - Participation: < 20% contribution

  Each tier has a multiplier applied to base rewards:
  - Gold: 100%
  - Silver: 75%
  - Bronze: 50%
  - Participation: 25%
  """

  alias BezgelorDb.PublicEvents

  require Logger

  # Contribution thresholds for reward tiers (percentage)
  @gold_tier_threshold 80
  @silver_tier_threshold 50
  @bronze_tier_threshold 20

  # Reward multipliers by tier
  @gold_multiplier 1.0
  @silver_multiplier 0.75
  @bronze_multiplier 0.5
  @participation_multiplier 0.25

  @doc """
  Calculate the reward tier based on contribution relative to group.

  ## Parameters

  - `contribution` - The participant's contribution amount
  - `total_contribution` - Sum of all participants' contributions
  - `max_contribution` - Highest individual contribution

  ## Returns

  One of: `:gold`, `:silver`, `:bronze`, `:participation`
  """
  @spec calculate_reward_tier(non_neg_integer(), non_neg_integer(), non_neg_integer()) :: atom()
  def calculate_reward_tier(contribution, total_contribution, max_contribution) do
    cond do
      total_contribution == 0 ->
        :participation

      contribution == max_contribution and contribution > 0 ->
        :gold

      true ->
        percent =
          if total_contribution > 0, do: div(contribution * 100, total_contribution), else: 0

        cond do
          percent >= @gold_tier_threshold -> :gold
          percent >= @silver_tier_threshold -> :silver
          percent >= @bronze_tier_threshold -> :bronze
          true -> :participation
        end
    end
  end

  @doc """
  Get the reward multiplier for a tier.
  """
  @spec tier_multiplier(atom()) :: float()
  def tier_multiplier(:gold), do: @gold_multiplier
  def tier_multiplier(:silver), do: @silver_multiplier
  def tier_multiplier(:bronze), do: @bronze_multiplier
  def tier_multiplier(:participation), do: @participation_multiplier

  @doc """
  Convert a tier atom to its string representation.
  """
  @spec tier_to_string(atom()) :: String.t()
  def tier_to_string(:gold), do: "gold"
  def tier_to_string(:silver), do: "silver"
  def tier_to_string(:bronze), do: "bronze"
  def tier_to_string(:participation), do: "participation"

  @doc """
  Calculate scaled rewards for a participant based on tier multiplier.

  ## Parameters

  - `rewards_def` - Base reward definition map from event data
  - `multiplier` - Tier-based multiplier (0.0 - 1.0)

  ## Returns

  A map containing scaled reward values.
  """
  @spec calculate_participant_rewards(map(), float()) :: map()
  def calculate_participant_rewards(rewards_def, multiplier) do
    %{
      xp: round((rewards_def["xp"] || 0) * multiplier),
      gold: round((rewards_def["gold"] || 0) * multiplier),
      currency: scale_currency_rewards(rewards_def["currency"], multiplier),
      reputation: scale_reputation_reward(rewards_def["reputation"], multiplier),
      loot_table_id: rewards_def["loot_table_id"],
      achievement_id: rewards_def["achievement_id"]
    }
  end

  @doc """
  Scale a currency rewards map by the given multiplier.
  """
  @spec scale_currency_rewards(map() | nil, float()) :: map()
  def scale_currency_rewards(nil, _multiplier), do: %{}

  def scale_currency_rewards(currency_map, multiplier) when is_map(currency_map) do
    Map.new(currency_map, fn {currency, amount} ->
      {currency, round(amount * multiplier)}
    end)
  end

  @doc """
  Scale a reputation reward by the given multiplier.
  """
  @spec scale_reputation_reward(map() | nil, float()) :: map() | nil
  def scale_reputation_reward(nil, _multiplier), do: nil

  def scale_reputation_reward(%{"faction_id" => faction_id, "amount" => amount}, multiplier) do
    %{faction_id: faction_id, amount: round(amount * multiplier)}
  end

  def scale_reputation_reward(_other, _multiplier), do: nil

  @doc """
  Distribute rewards to all event participants.

  Calculates contribution-based tiers and records completion in the database.

  ## Parameters

  - `event_state` - The event state containing event_id, started_at, participants
  - `participants` - Map of character_id => participant_state with contribution data
  """
  @spec distribute_event_rewards(map(), map()) :: :ok
  def distribute_event_rewards(event_state, participants) do
    rewards_def = event_state.event_def["rewards"] || %{}
    participant_ids = MapSet.to_list(event_state.participants)

    # Calculate duration
    duration_ms = DateTime.diff(DateTime.utc_now(), event_state.started_at, :millisecond)

    # Calculate total contribution for tier assignment
    contributions =
      Enum.map(participant_ids, fn char_id ->
        participant = Map.get(participants, char_id)
        {char_id, (participant && participant.contribution) || 0}
      end)

    total_contribution = Enum.reduce(contributions, 0, fn {_, c}, acc -> acc + c end)
    max_contribution = Enum.max_by(contributions, fn {_, c} -> c end, fn -> {0, 0} end) |> elem(1)

    # Assign reward tiers and distribute
    Enum.each(contributions, fn {character_id, contribution} ->
      tier = calculate_reward_tier(contribution, total_contribution, max_contribution)
      multiplier = tier_multiplier(tier)

      reward_data = calculate_participant_rewards(rewards_def, multiplier)

      # Log the reward (actual distribution would call game systems)
      Logger.debug(
        "Event reward for #{character_id}: tier=#{tier}, rewards=#{inspect(reward_data)}"
      )

      # Record completion in DB (character_id, event_id, tier, contribution, duration_ms)
      PublicEvents.record_completion(
        character_id,
        event_state.event_id,
        tier_to_string(tier),
        contribution,
        duration_ms
      )

      # TODO: Actually grant rewards via Inventory/Currency/XP systems
      # BezgelorWorld.Rewards.grant_event_rewards(character_id, reward_data)
    end)

    :ok
  end

  @doc """
  Distribute rewards to world boss participants based on damage dealt.

  Top contributors are assigned tiers based on damage percentage:
  - >= 10% damage: Gold
  - >= 5% damage: Silver
  - >= 1% damage: Bronze
  - < 1% damage: Participation
  """
  @spec distribute_boss_rewards(map()) :: :ok
  def distribute_boss_rewards(boss_state) do
    boss_def = boss_state.boss_def
    rewards_def = boss_def["rewards"] || %{}
    total_damage = boss_state.health_max

    # Sort contributors by damage
    sorted_contributors =
      boss_state.contributions
      |> Enum.sort_by(fn {_id, damage} -> damage end, :desc)

    # Top contributor gets gold tier, rest scaled by damage percentage
    Enum.each(sorted_contributors, fn {character_id, damage} ->
      damage_percent = if total_damage > 0, do: div(damage * 100, total_damage), else: 0

      tier =
        cond do
          damage_percent >= 10 -> :gold
          damage_percent >= 5 -> :silver
          damage_percent >= 1 -> :bronze
          true -> :participation
        end

      multiplier = tier_multiplier(tier)
      reward_data = calculate_participant_rewards(rewards_def, multiplier)

      Logger.debug(
        "Boss reward for #{character_id}: tier=#{tier}, damage=#{damage} (#{damage_percent}%), rewards=#{inspect(reward_data)}"
      )

      # TODO: Record in DB when boss kill tracking is added
      # TODO: Actually grant rewards via BezgelorWorld.Rewards
      _ = {boss_state.boss_id, reward_data}
    end)

    :ok
  end
end
