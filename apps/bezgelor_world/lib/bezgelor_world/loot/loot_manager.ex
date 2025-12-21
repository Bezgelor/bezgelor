defmodule BezgelorWorld.Loot.LootManager do
  @moduledoc """
  Manages loot distribution for an instance.

  Handles:
  - Personal loot assignment
  - Group loot rolls (need/greed/pass)
  - Master loot distribution
  - Roll timeouts
  - Loot history tracking
  """

  use GenServer

  require Logger

  alias BezgelorWorld.Loot.LootRules

  # 30 seconds to roll
  @roll_timeout 30_000

  defstruct [
    :instance_guid,
    :group_id,
    :loot_method,
    :master_looter_id,
    # loot_id => pending_roll
    pending_rolls: %{},
    # awarded loot
    loot_history: [],
    # for round robin
    round_robin_index: 0,
    member_ids: []
  ]

  @type t :: %__MODULE__{
          instance_guid: non_neg_integer(),
          group_id: non_neg_integer(),
          loot_method: LootRules.loot_method(),
          master_looter_id: non_neg_integer() | nil,
          pending_rolls: map(),
          loot_history: list(),
          round_robin_index: non_neg_integer(),
          member_ids: [non_neg_integer()]
        }

  # Client API

  def start_link(opts) do
    instance_guid = Keyword.fetch!(opts, :instance_guid)
    GenServer.start_link(__MODULE__, opts, name: via(instance_guid))
  end

  defp via(instance_guid) do
    {:via, Registry, {BezgelorWorld.Instance.Registry, {:loot_manager, instance_guid}}}
  end

  @doc """
  Distributes loot from a killed enemy.
  """
  @spec distribute_loot(non_neg_integer(), non_neg_integer(), [map()], [map()]) ::
          {:ok, [map()]} | {:error, term()}
  def distribute_loot(instance_guid, source_id, loot_table, eligible_players) do
    GenServer.call(
      via(instance_guid),
      {:distribute_loot, source_id, loot_table, eligible_players}
    )
  end

  @doc """
  Player submits a roll (need/greed/pass) for pending loot.
  """
  @spec submit_roll(
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          LootRules.roll_type()
        ) ::
          :ok | {:error, term()}
  def submit_roll(instance_guid, loot_id, character_id, roll_type) do
    GenServer.call(via(instance_guid), {:submit_roll, loot_id, character_id, roll_type})
  end

  @doc """
  Master looter assigns loot to a player.
  """
  @spec master_assign(non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()) ::
          :ok | {:error, term()}
  def master_assign(instance_guid, loot_id, assigner_id, recipient_id) do
    GenServer.call(via(instance_guid), {:master_assign, loot_id, assigner_id, recipient_id})
  end

  @doc """
  Gets loot history for the instance.
  """
  @spec get_history(non_neg_integer()) :: [map()]
  def get_history(instance_guid) do
    GenServer.call(via(instance_guid), :get_history)
  end

  @doc """
  Changes loot method (requires group leader).
  """
  @spec set_loot_method(non_neg_integer(), non_neg_integer(), LootRules.loot_method()) ::
          :ok | {:error, term()}
  def set_loot_method(instance_guid, leader_id, method) do
    GenServer.call(via(instance_guid), {:set_loot_method, leader_id, method})
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    state = %__MODULE__{
      instance_guid: Keyword.fetch!(opts, :instance_guid),
      group_id: Keyword.get(opts, :group_id),
      loot_method: Keyword.get(opts, :loot_method, :personal),
      master_looter_id: Keyword.get(opts, :master_looter_id),
      member_ids: Keyword.get(opts, :member_ids, [])
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:distribute_loot, source_id, loot_table, eligible_players}, _from, state) do
    {awarded, new_state} = do_distribute_loot(state, source_id, loot_table, eligible_players)
    {:reply, {:ok, awarded}, new_state}
  end

  def handle_call({:submit_roll, loot_id, character_id, roll_type}, _from, state) do
    case Map.get(state.pending_rolls, loot_id) do
      nil ->
        {:reply, {:error, :no_pending_roll}, state}

      pending ->
        if character_id in pending.eligible_ids do
          roll_value = if roll_type == :pass, do: 0, else: LootRules.roll()

          roll_result = %{
            character_id: character_id,
            roll_type: roll_type,
            roll_value: roll_value
          }

          pending = %{pending | rolls: [roll_result | pending.rolls]}
          state = %{state | pending_rolls: Map.put(state.pending_rolls, loot_id, pending)}

          # Check if all players have rolled
          state = maybe_resolve_roll(state, loot_id)

          {:reply, :ok, state}
        else
          {:reply, {:error, :not_eligible}, state}
        end
    end
  end

  def handle_call({:master_assign, loot_id, assigner_id, recipient_id}, _from, state) do
    cond do
      state.loot_method != :master_loot ->
        {:reply, {:error, :not_master_loot}, state}

      state.master_looter_id != assigner_id ->
        {:reply, {:error, :not_master_looter}, state}

      true ->
        case Map.get(state.pending_rolls, loot_id) do
          nil ->
            {:reply, {:error, :no_pending_loot}, state}

          pending ->
            award = %{
              loot_id: loot_id,
              item: pending.item,
              winner_id: recipient_id,
              award_reason: :master_loot,
              awarded_at: DateTime.utc_now()
            }

            state = %{
              state
              | pending_rolls: Map.delete(state.pending_rolls, loot_id),
                loot_history: [award | state.loot_history]
            }

            broadcast_loot_awarded(state, award)
            {:reply, :ok, state}
        end
    end
  end

  def handle_call(:get_history, _from, state) do
    {:reply, state.loot_history, state}
  end

  def handle_call({:set_loot_method, _leader_id, method}, _from, state) do
    # In production, verify leader_id is actually the group leader
    state = %{state | loot_method: method}
    {:reply, :ok, state}
  end

  @impl true
  def handle_info({:roll_timeout, loot_id}, state) do
    state = resolve_roll(state, loot_id)
    {:noreply, state}
  end

  # Private Functions

  defp do_distribute_loot(state, source_id, loot_table, eligible_players) do
    case state.loot_method do
      :personal ->
        distribute_personal_loot(state, source_id, loot_table, eligible_players)

      :round_robin ->
        distribute_round_robin(state, source_id, loot_table, eligible_players)

      method when method in [:group_loot, :need_before_greed, :master_loot] ->
        distribute_group_loot(state, source_id, loot_table, eligible_players)
    end
  end

  defp distribute_personal_loot(state, _source_id, loot_table, eligible_players) do
    # Each player gets independent loot rolls
    awarded =
      Enum.flat_map(eligible_players, fn player ->
        items = LootRules.calculate_personal_loot(player, loot_table)

        Enum.map(items, fn item ->
          loot_id = generate_loot_id()

          award = %{
            loot_id: loot_id,
            item: item,
            winner_id: player.character_id,
            award_reason: :personal,
            awarded_at: DateTime.utc_now()
          }

          # Notify player of their loot
          send_personal_loot(player.character_id, award)

          award
        end)
      end)

    state = %{state | loot_history: awarded ++ state.loot_history}
    {awarded, state}
  end

  defp distribute_round_robin(state, _source_id, loot_table, eligible_players) do
    {awarded, new_index} =
      Enum.reduce(loot_table, {[], state.round_robin_index}, fn item, {acc, idx} ->
        # Rotate through eligible players
        winner_idx = rem(idx, length(eligible_players))
        winner = Enum.at(eligible_players, winner_idx)

        loot_id = generate_loot_id()

        award = %{
          loot_id: loot_id,
          item: item,
          winner_id: winner.character_id,
          award_reason: :round_robin,
          awarded_at: DateTime.utc_now()
        }

        broadcast_loot_awarded(state, award)

        {[award | acc], idx + 1}
      end)

    state = %{state | loot_history: awarded ++ state.loot_history, round_robin_index: new_index}

    {awarded, state}
  end

  defp distribute_group_loot(state, _source_id, loot_table, eligible_players) do
    eligible_ids = Enum.map(eligible_players, & &1.character_id)

    # Sort items into immediate distribution and pending rolls
    {immediate, pending} =
      Enum.split_with(loot_table, fn item ->
        not LootRules.requires_roll?(item, state.loot_method)
      end)

    # Distribute common items immediately (round robin style)
    {immediate_awards, state} =
      distribute_round_robin(state, nil, immediate, eligible_players)

    # Create pending rolls for rare+ items
    state =
      Enum.reduce(pending, state, fn item, acc ->
        loot_id = generate_loot_id()

        pending_roll = %{
          loot_id: loot_id,
          item: item,
          eligible_ids: eligible_ids,
          rolls: [],
          started_at: DateTime.utc_now()
        }

        # Broadcast roll request
        broadcast_roll_request(acc, pending_roll, eligible_players)

        # Set timeout
        Process.send_after(self(), {:roll_timeout, loot_id}, @roll_timeout)

        %{acc | pending_rolls: Map.put(acc.pending_rolls, loot_id, pending_roll)}
      end)

    {immediate_awards, state}
  end

  defp maybe_resolve_roll(state, loot_id) do
    case Map.get(state.pending_rolls, loot_id) do
      nil ->
        state

      pending ->
        # Check if all eligible players have rolled
        rolled_ids = MapSet.new(pending.rolls, & &1.character_id)
        eligible_ids = MapSet.new(pending.eligible_ids)

        if MapSet.equal?(rolled_ids, eligible_ids) do
          resolve_roll(state, loot_id)
        else
          state
        end
    end
  end

  defp resolve_roll(state, loot_id) do
    case Map.get(state.pending_rolls, loot_id) do
      nil ->
        state

      pending ->
        # Add auto-pass for missing rolls
        rolled_ids = MapSet.new(pending.rolls, & &1.character_id)

        auto_passes =
          pending.eligible_ids
          |> Enum.reject(&MapSet.member?(rolled_ids, &1))
          |> Enum.map(fn id ->
            %{character_id: id, roll_type: :pass, roll_value: 0}
          end)

        all_rolls = pending.rolls ++ auto_passes

        # Determine winner
        case LootRules.determine_winner(all_rolls) do
          nil ->
            # No one wanted it - could vendor or disenchant
            Logger.debug("No winner for loot #{loot_id} - all passed")
            %{state | pending_rolls: Map.delete(state.pending_rolls, loot_id)}

          winner ->
            award = %{
              loot_id: loot_id,
              item: pending.item,
              winner_id: winner.character_id,
              roll_type: winner.roll_type,
              roll_value: winner.roll_value,
              award_reason: :won_roll,
              awarded_at: DateTime.utc_now()
            }

            broadcast_loot_awarded(state, award)

            %{
              state
              | pending_rolls: Map.delete(state.pending_rolls, loot_id),
                loot_history: [award | state.loot_history]
            }
        end
    end
  end

  defp generate_loot_id do
    System.unique_integer([:positive, :monotonic])
  end

  defp broadcast_loot_awarded(_state, award) do
    Logger.info(
      "Loot awarded: item #{award.item[:id] || "unknown"} to player #{award.winner_id} (#{award.award_reason})"
    )

    # In production: send ServerLootAwarded packet to all group members
    :ok
  end

  defp broadcast_roll_request(_state, pending, _eligible_players) do
    Logger.info("Roll requested for item #{pending.item[:id] || "unknown"}")
    # In production: send ServerLootRoll packet to all eligible players
    :ok
  end

  defp send_personal_loot(character_id, award) do
    Logger.info("Personal loot for player #{character_id}: item #{award.item[:id] || "unknown"}")
    # In production: send ServerLootAwarded packet to the character
    :ok
  end
end
