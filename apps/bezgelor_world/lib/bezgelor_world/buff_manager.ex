defmodule BezgelorWorld.BuffManager do
  @moduledoc """
  Manages active buffs and debuffs for all entities.

  ## Overview

  The BuffManager tracks:
  - Active buffs/debuffs per entity
  - Expiration timers for automatic removal
  - Stat modifiers from buff effects
  - Absorb shield values

  This is similar to SpellManager but tracks ongoing effects rather than
  cast state.

  ## State Structure

      %{
        entities: %{
          entity_guid => %{
            effects: ActiveEffect.state(),
            timers: %{buff_id => timer_ref}
          }
        }
      }
  """

  use GenServer

  alias BezgelorCore.{BuffDebuff, ActiveEffect}
  alias BezgelorWorld.CombatBroadcaster

  require Logger

  @type entity_state :: %{
          effects: ActiveEffect.state(),
          timers: %{non_neg_integer() => reference()}
        }

  @type state :: %{
          entities: %{non_neg_integer() => entity_state()}
        }

  ## Client API

  @doc "Start the BuffManager."
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Apply a buff/debuff to an entity.

  Returns `{:ok, timer_ref}` with the expiration timer reference.
  """
  @spec apply_buff(non_neg_integer(), BuffDebuff.t(), non_neg_integer()) ::
          {:ok, reference()}
  def apply_buff(entity_guid, %BuffDebuff{} = buff, caster_guid) do
    GenServer.call(__MODULE__, {:apply_buff, entity_guid, buff, caster_guid})
  end

  @doc """
  Remove a buff/debuff from an entity.
  """
  @spec remove_buff(non_neg_integer(), non_neg_integer()) :: :ok | {:error, :not_found}
  def remove_buff(entity_guid, buff_id) do
    GenServer.call(__MODULE__, {:remove_buff, entity_guid, buff_id})
  end

  @doc """
  Check if an entity has a specific buff.
  """
  @spec has_buff?(non_neg_integer(), non_neg_integer()) :: boolean()
  def has_buff?(entity_guid, buff_id) do
    GenServer.call(__MODULE__, {:has_buff?, entity_guid, buff_id})
  end

  @doc """
  Get all active buffs for an entity.
  """
  @spec get_entity_buffs(non_neg_integer()) :: [map()]
  def get_entity_buffs(entity_guid) do
    GenServer.call(__MODULE__, {:get_entity_buffs, entity_guid})
  end

  @doc """
  Get total stat modifier for an entity.
  """
  @spec get_stat_modifier(non_neg_integer(), BuffDebuff.stat()) :: integer()
  def get_stat_modifier(entity_guid, stat) do
    GenServer.call(__MODULE__, {:get_stat_modifier, entity_guid, stat})
  end

  @doc """
  Consume absorb shields for incoming damage.

  Returns `{absorbed_amount, remaining_damage}`.
  """
  @spec consume_absorb(non_neg_integer(), non_neg_integer()) ::
          {non_neg_integer(), non_neg_integer()}
  def consume_absorb(entity_guid, damage) do
    GenServer.call(__MODULE__, {:consume_absorb, entity_guid, damage})
  end

  @doc """
  Clear all buffs from an entity (on death/logout).
  """
  @spec clear_entity(non_neg_integer()) :: :ok
  def clear_entity(entity_guid) do
    GenServer.call(__MODULE__, {:clear_entity, entity_guid})
  end

  ## Server Callbacks

  @impl true
  def init(_opts) do
    state = %{entities: %{}}
    Logger.info("BuffManager started")
    {:ok, state}
  end

  @impl true
  def handle_call({:apply_buff, entity_guid, buff, caster_guid}, _from, state) do
    now = System.monotonic_time(:millisecond)
    entity = get_entity_state(state, entity_guid)

    # Cancel existing timer for this buff if present
    if timer_ref = Map.get(entity.timers, buff.id) do
      Process.cancel_timer(timer_ref)
    end

    # Apply the buff
    effects = ActiveEffect.apply(entity.effects, buff, caster_guid, now)

    # Schedule expiration
    timer_ref = Process.send_after(self(), {:buff_expired, entity_guid, buff.id}, buff.duration)

    # Update state
    timers = Map.put(entity.timers, buff.id, timer_ref)
    entity = %{entity | effects: effects, timers: timers}
    state = put_entity_state(state, entity_guid, entity)

    Logger.debug("Applied buff #{buff.id} to entity #{entity_guid}")
    {:reply, {:ok, timer_ref}, state}
  end

  @impl true
  def handle_call({:remove_buff, entity_guid, buff_id}, _from, state) do
    entity = get_entity_state(state, entity_guid)

    if Map.has_key?(entity.effects, buff_id) do
      # Cancel timer
      if timer_ref = Map.get(entity.timers, buff_id) do
        Process.cancel_timer(timer_ref)
      end

      # Remove buff
      effects = ActiveEffect.remove(entity.effects, buff_id)
      timers = Map.delete(entity.timers, buff_id)
      entity = %{entity | effects: effects, timers: timers}
      state = put_entity_state(state, entity_guid, entity)

      Logger.debug("Removed buff #{buff_id} from entity #{entity_guid}")
      # Broadcast buff removal to the target (dispel = manual removal)
      CombatBroadcaster.send_buff_remove(entity_guid, buff_id, :dispel)
      {:reply, :ok, state}
    else
      {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:has_buff?, entity_guid, buff_id}, _from, state) do
    now = System.monotonic_time(:millisecond)
    entity = get_entity_state(state, entity_guid)
    result = ActiveEffect.active?(entity.effects, buff_id, now)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:get_entity_buffs, entity_guid}, _from, state) do
    now = System.monotonic_time(:millisecond)
    entity = get_entity_state(state, entity_guid)
    buffs = ActiveEffect.list_active(entity.effects, now)
    {:reply, buffs, state}
  end

  @impl true
  def handle_call({:get_stat_modifier, entity_guid, stat}, _from, state) do
    now = System.monotonic_time(:millisecond)
    entity = get_entity_state(state, entity_guid)
    modifier = ActiveEffect.get_stat_modifier(entity.effects, stat, now)
    {:reply, modifier, state}
  end

  @impl true
  def handle_call({:consume_absorb, entity_guid, damage}, _from, state) do
    now = System.monotonic_time(:millisecond)
    entity = get_entity_state(state, entity_guid)

    {effects, absorbed, remaining} = ActiveEffect.consume_absorb(entity.effects, damage, now)

    # Clean up timers for fully consumed buffs
    consumed_ids =
      Map.keys(entity.effects) -- Map.keys(effects)

    timers =
      Enum.reduce(consumed_ids, entity.timers, fn id, acc ->
        if ref = Map.get(acc, id), do: Process.cancel_timer(ref)
        Map.delete(acc, id)
      end)

    entity = %{entity | effects: effects, timers: timers}
    state = put_entity_state(state, entity_guid, entity)

    {:reply, {absorbed, remaining}, state}
  end

  @impl true
  def handle_call({:clear_entity, entity_guid}, _from, state) do
    entity = get_entity_state(state, entity_guid)

    # Cancel all timers
    Enum.each(entity.timers, fn {_id, ref} ->
      Process.cancel_timer(ref)
    end)

    state = %{state | entities: Map.delete(state.entities, entity_guid)}
    Logger.debug("Cleared all buffs for entity #{entity_guid}")
    {:reply, :ok, state}
  end

  @impl true
  def handle_info({:buff_expired, entity_guid, buff_id}, state) do
    entity = get_entity_state(state, entity_guid)

    if Map.has_key?(entity.effects, buff_id) do
      effects = ActiveEffect.remove(entity.effects, buff_id)
      timers = Map.delete(entity.timers, buff_id)
      entity = %{entity | effects: effects, timers: timers}
      state = put_entity_state(state, entity_guid, entity)

      Logger.debug("Buff #{buff_id} expired on entity #{entity_guid}")
      # Broadcast buff removal to the target
      CombatBroadcaster.send_buff_remove(entity_guid, buff_id, :expired)
      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  # Private helpers

  defp get_entity_state(state, entity_guid) do
    Map.get(state.entities, entity_guid, %{effects: ActiveEffect.new(), timers: %{}})
  end

  defp put_entity_state(state, entity_guid, entity) do
    %{state | entities: Map.put(state.entities, entity_guid, entity)}
  end
end
