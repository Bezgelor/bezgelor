defmodule BezgelorWorld.Quest.RewardHandler do
  @moduledoc """
  Handles quest reward distribution.

  ## Reward Types (from quest2RewardTypeId)

  | Type | Description |
  |------|-------------|
  | 1    | Item reward |
  | 2    | Currency (gold) |
  | 3    | Reputation |
  | 4    | Path XP |
  | 5    | Choice reward (pick one) |

  ## Reward Sources

  Rewards come from two sources:
  1. Quest definition fields (reward_xpOverride, reward_cashOverride, pushed_item*)
  2. Quest rewards table (quest_rewards.json)

  ## Usage

      RewardHandler.grant_quest_rewards(connection_pid, character_id, quest_id)
  """

  alias BezgelorData.Store
  alias BezgelorDb.{Characters, Inventory, Repo}
  alias BezgelorDb.Schema.CharacterCurrency
  alias BezgelorWorld.CombatBroadcaster
  alias BezgelorWorld.Handler.ReputationHandler

  require Logger

  # Reward type constants
  @reward_type_item 1
  @reward_type_currency 2
  @reward_type_reputation 3
  @reward_type_path_xp 4
  @reward_type_choice 5

  @doc """
  Grant all rewards for completing a quest.

  Returns a summary of granted rewards for logging/notification.
  """
  @spec grant_quest_rewards(pid(), non_neg_integer(), non_neg_integer()) :: {:ok, map()} | {:error, atom()}
  def grant_quest_rewards(connection_pid, character_id, quest_id) do
    with {:ok, quest} <- Store.get_quest(quest_id) do
      rewards_summary = %{
        xp: 0,
        gold: 0,
        items: [],
        reputation: [],
        path_xp: 0
      }

      # Get rewards from quest definition
      rewards_summary = grant_quest_definition_rewards(connection_pid, character_id, quest, rewards_summary)

      # Get rewards from quest_rewards table
      table_rewards = Store.get_quest_rewards(quest_id)
      rewards_summary = grant_table_rewards(connection_pid, character_id, table_rewards, rewards_summary)

      Logger.info(
        "Quest #{quest_id} rewards granted to #{character_id}: " <>
          "XP=#{rewards_summary.xp}, Gold=#{rewards_summary.gold}, " <>
          "Items=#{length(rewards_summary.items)}, Rep=#{length(rewards_summary.reputation)}"
      )

      {:ok, rewards_summary}
    end
  end

  # Grant rewards from quest definition fields
  defp grant_quest_definition_rewards(connection_pid, character_id, quest, summary) do
    summary =
      summary
      |> grant_xp_reward(connection_pid, character_id, quest)
      |> grant_cash_reward(connection_pid, character_id, quest)
      |> grant_pushed_items(connection_pid, character_id, quest)

    summary
  end

  # Grant XP from quest definition
  defp grant_xp_reward(summary, _connection_pid, character_id, quest) do
    xp = Map.get(quest, :reward_xpOverride, 0)

    if xp > 0 do
      # Calculate actual XP based on character level and quest level
      actual_xp = calculate_xp_reward(character_id, quest, xp)

      # Grant XP via CombatBroadcaster (uses existing XP system)
      if actual_xp > 0 do
        CombatBroadcaster.send_xp_gain(
          get_player_guid(character_id),
          actual_xp,
          :quest,
          0
        )
      end

      %{summary | xp: summary.xp + actual_xp}
    else
      summary
    end
  end

  # Calculate XP reward considering level differences
  defp calculate_xp_reward(character_id, quest, base_xp) do
    case Characters.get_character(character_id) do
      nil ->
        base_xp

      character ->
        quest_level = Map.get(quest, :conLevel, character.level)
        level_diff = character.level - quest_level

        cond do
          # Quest too low level - reduced XP
          level_diff > 5 -> div(base_xp, 2)
          level_diff > 3 -> div(base_xp * 3, 4)
          # Normal range
          level_diff >= -2 -> base_xp
          # Quest higher level - bonus XP
          level_diff < -2 -> div(base_xp * 5, 4)
        end
    end
  end

  # Grant gold/cash reward
  defp grant_cash_reward(summary, _connection_pid, character_id, quest) do
    gold = Map.get(quest, :reward_cashOverride, 0)

    if gold > 0 do
      case add_currency(character_id, :gold, gold) do
        {:ok, _} ->
          Logger.debug("Granted #{gold} gold to character #{character_id}")
          %{summary | gold: summary.gold + gold}

        {:error, reason} ->
          Logger.warning("Failed to grant gold: #{inspect(reason)}")
          summary
      end
    else
      summary
    end
  end

  # Grant pushed items from quest definition
  defp grant_pushed_items(summary, _connection_pid, character_id, quest) do
    # Get all pushed_itemId* and pushed_itemCount* fields
    items =
      0..5
      |> Enum.map(fn i ->
        suffix = if i == 0, do: "0", else: String.pad_leading("#{i}", 2, "0")
        item_key = String.to_atom("pushed_itemId#{suffix}")
        count_key = String.to_atom("pushed_itemCount#{suffix}")

        item_id = Map.get(quest, item_key, 0)
        count = Map.get(quest, count_key, 0)

        {item_id, count}
      end)
      |> Enum.reject(fn {item_id, count} -> item_id == 0 or count == 0 end)

    granted_items =
      Enum.reduce(items, [], fn {item_id, count}, acc ->
        case grant_item(character_id, item_id, count) do
          :ok ->
            [{item_id, count} | acc]

          {:error, reason} ->
            Logger.warning("Failed to grant item #{item_id}: #{inspect(reason)}")
            acc
        end
      end)

    %{summary | items: summary.items ++ granted_items}
  end

  # Grant rewards from quest_rewards table
  defp grant_table_rewards(connection_pid, character_id, rewards, summary) do
    Enum.reduce(rewards, summary, fn reward, acc ->
      grant_single_reward(connection_pid, character_id, reward, acc)
    end)
  end

  # Grant a single reward entry
  defp grant_single_reward(connection_pid, character_id, reward, summary) do
    type = Map.get(reward, :quest2RewardTypeId, 0)
    object_id = Map.get(reward, :objectId, 0)
    amount = Map.get(reward, :objectAmount, 1)

    case type do
      @reward_type_item ->
        case grant_item(character_id, object_id, amount) do
          :ok ->
            %{summary | items: [{object_id, amount} | summary.items]}

          {:error, _} ->
            summary
        end

      @reward_type_currency ->
        # object_id indicates currency type (1 = gold, others = various currencies)
        case grant_currency(character_id, object_id, amount) do
          :ok ->
            %{summary | gold: summary.gold + amount}

          {:error, _} ->
            summary
        end

      @reward_type_reputation ->
        # object_id is faction_id, amount is reputation gain
        ReputationHandler.modify_reputation(connection_pid, character_id, object_id, amount)
        %{summary | reputation: [{object_id, amount} | summary.reputation]}

      @reward_type_path_xp ->
        # Path XP for settler/scientist/explorer/soldier
        grant_path_xp(character_id, object_id, amount)
        %{summary | path_xp: summary.path_xp + amount}

      @reward_type_choice ->
        # Choice rewards handled separately (player picks from options)
        Logger.debug("Quest has choice reward - not auto-granted")
        summary

      _ ->
        Logger.warning("Unknown reward type: #{type}")
        summary
    end
  end

  # Grant an item to character's inventory
  defp grant_item(character_id, item_id, count) do
    case Inventory.add_item(character_id, item_id, count) do
      {:ok, _} ->
        Logger.debug("Granted item #{item_id} x#{count} to character #{character_id}")
        :ok

      {:error, :inventory_full} ->
        # TODO: Send to mail or overflow storage
        Logger.warning("Inventory full for character #{character_id}, item #{item_id} not granted")
        {:error, :inventory_full}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Grant currency to character
  defp grant_currency(character_id, currency_type, amount) do
    currency = case currency_type do
      1 -> :gold
      2 -> :renown
      3 -> :prestige
      4 -> :elder_gems
      5 -> :glory
      6 -> :crafting_vouchers
      _ -> :gold
    end

    case add_currency(character_id, currency, amount) do
      {:ok, _} ->
        Logger.debug("Granted #{amount} #{currency} to character #{character_id}")
        :ok

      {:error, reason} ->
        Logger.warning("Failed to grant currency: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Add currency to a character's currency record
  defp add_currency(character_id, currency_type, amount) when is_atom(currency_type) and amount > 0 do
    case get_or_create_currency_record(character_id) do
      {:ok, record} ->
        case CharacterCurrency.modify_changeset(record, currency_type, amount) do
          {:ok, changeset} ->
            Repo.update(changeset)

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp add_currency(_character_id, _currency_type, _amount), do: {:ok, nil}

  # Get or create a currency record for a character
  defp get_or_create_currency_record(character_id) do
    case Repo.get_by(CharacterCurrency, character_id: character_id) do
      nil ->
        %CharacterCurrency{}
        |> CharacterCurrency.changeset(%{character_id: character_id})
        |> Repo.insert()

      record ->
        {:ok, record}
    end
  end

  # Grant path XP
  defp grant_path_xp(character_id, _path_type, amount) do
    # TODO: Implement path XP system
    Logger.debug("Would grant #{amount} path XP to character #{character_id}")
    :ok
  end

  # Get player's entity GUID from character_id
  defp get_player_guid(character_id) do
    case BezgelorWorld.WorldManager.get_session_by_character(character_id) do
      nil -> 0
      session -> session.entity_guid || 0
    end
  end

  @doc """
  Get quest choice rewards for a quest.

  Returns a list of choice reward options the player can pick from.
  """
  @spec get_choice_rewards(non_neg_integer()) :: [map()]
  def get_choice_rewards(quest_id) do
    quest_id
    |> Store.get_quest_rewards()
    |> Enum.filter(fn reward ->
      Map.get(reward, :quest2RewardTypeId) == @reward_type_choice
    end)
    |> Enum.map(fn reward ->
      %{
        item_id: Map.get(reward, :objectId),
        count: Map.get(reward, :objectAmount, 1)
      }
    end)
  end

  @doc """
  Grant a choice reward that the player selected.
  """
  @spec grant_choice_reward(non_neg_integer(), non_neg_integer()) :: :ok | {:error, atom()}
  def grant_choice_reward(character_id, item_id) do
    grant_item(character_id, item_id, 1)
  end
end
