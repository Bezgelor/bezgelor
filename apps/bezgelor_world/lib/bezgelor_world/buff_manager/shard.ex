defmodule BezgelorWorld.BuffManager.Shard do
  @moduledoc """
  Individual shard of the BuffManager.

  Each shard handles a subset of entities based on GUID hash.
  This distributes buff processing across multiple processes to
  avoid a single-process bottleneck.

  ## Sharding Strategy

  Entities are assigned to shards using `rem(entity_guid, num_shards)`.
  This ensures consistent routing for the same entity while distributing
  load relatively evenly.
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
          shard_id: non_neg_integer(),
          entities: %{non_neg_integer() => entity_state()}
        }

  ## Client API

  @doc "Start a BuffManager shard."
  def start_link(opts) do
    shard_id = Keyword.fetch!(opts, :shard_id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(shard_id))
  end

  @doc "Registry lookup for a specific shard."
  def via_tuple(shard_id) do
    {:via, Registry, {BezgelorWorld.BuffManager.Registry, shard_id}}
  end

  @doc "Apply a buff/debuff to an entity."
  @spec apply_buff(non_neg_integer(), non_neg_integer(), BuffDebuff.t(), non_neg_integer()) ::
          {:ok, reference()}
  def apply_buff(shard_id, entity_guid, %BuffDebuff{} = buff, caster_guid) do
    GenServer.call(via_tuple(shard_id), {:apply_buff, entity_guid, buff, caster_guid})
  end

  @doc "Remove a buff/debuff from an entity."
  @spec remove_buff(non_neg_integer(), non_neg_integer(), non_neg_integer()) ::
          :ok | {:error, :not_found}
  def remove_buff(shard_id, entity_guid, buff_id) do
    GenServer.call(via_tuple(shard_id), {:remove_buff, entity_guid, buff_id})
  end

  @doc "Check if an entity has a specific buff."
  @spec has_buff?(non_neg_integer(), non_neg_integer(), non_neg_integer()) :: boolean()
  def has_buff?(shard_id, entity_guid, buff_id) do
    GenServer.call(via_tuple(shard_id), {:has_buff?, entity_guid, buff_id})
  end

  @doc "Get all active buffs for an entity."
  @spec get_entity_buffs(non_neg_integer(), non_neg_integer()) :: [map()]
  def get_entity_buffs(shard_id, entity_guid) do
    GenServer.call(via_tuple(shard_id), {:get_entity_buffs, entity_guid})
  end

  @doc "Get total stat modifier for an entity."
  @spec get_stat_modifier(non_neg_integer(), non_neg_integer(), BuffDebuff.stat()) :: integer()
  def get_stat_modifier(shard_id, entity_guid, stat) do
    GenServer.call(via_tuple(shard_id), {:get_stat_modifier, entity_guid, stat})
  end

  @doc "Consume absorb shields for incoming damage."
  @spec consume_absorb(non_neg_integer(), non_neg_integer(), non_neg_integer()) ::
          {non_neg_integer(), non_neg_integer()}
  def consume_absorb(shard_id, entity_guid, damage) do
    GenServer.call(via_tuple(shard_id), {:consume_absorb, entity_guid, damage})
  end

  @doc "Clear all buffs from an entity."
  @spec clear_entity(non_neg_integer(), non_neg_integer()) :: :ok
  def clear_entity(shard_id, entity_guid) do
    GenServer.call(via_tuple(shard_id), {:clear_entity, entity_guid})
  end

  ## Server Callbacks

  @impl true
  def init(opts) do
    shard_id = Keyword.fetch!(opts, :shard_id)

    # Register with TickScheduler for coordinated periodic effect ticking
    if Process.whereis(BezgelorWorld.TickScheduler) do
      BezgelorWorld.TickScheduler.register_listener(self())
    end

    state = %{
      shard_id: shard_id,
      entities: %{}
    }

    Logger.debug("BuffManager.Shard #{shard_id} started")
    {:ok, state}
  end

  @impl true
  def handle_call({:apply_buff, entity_guid, buff, caster_guid}, _from, state) do
    now = System.monotonic_time(:millisecond)
    entity = get_entity_state(state, entity_guid)

    # Cancel existing expiration timer for this buff if present
    if timer_ref = Map.get(entity.timers, buff.id) do
      Process.cancel_timer(timer_ref)
    end

    # Apply the buff
    effects = ActiveEffect.apply(entity.effects, buff, caster_guid, now)

    # Schedule expiration timer
    timer_ref = Process.send_after(self(), {:buff_expired, entity_guid, buff.id}, buff.duration)
    timers = Map.put(entity.timers, buff.id, timer_ref)

    # Periodic effects are now processed by TickScheduler (no per-buff timers)

    # Update state
    entity = %{entity | effects: effects, timers: timers}
    state = put_entity_state(state, entity_guid, entity)

    Logger.debug("Shard #{state.shard_id}: Applied buff #{buff.id} to entity #{entity_guid}")
    {:reply, {:ok, timer_ref}, state}
  end

  @impl true
  def handle_call({:remove_buff, entity_guid, buff_id}, _from, state) do
    entity = get_entity_state(state, entity_guid)

    if Map.has_key?(entity.effects, buff_id) do
      # Cancel expiration timer
      if timer_ref = Map.get(entity.timers, buff_id) do
        Process.cancel_timer(timer_ref)
      end

      # Remove buff
      effects = ActiveEffect.remove(entity.effects, buff_id)
      timers = Map.delete(entity.timers, buff_id)
      entity = %{entity | effects: effects, timers: timers}
      state = put_entity_state(state, entity_guid, entity)

      Logger.debug("Shard #{state.shard_id}: Removed buff #{buff_id} from entity #{entity_guid}")
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
    consumed_ids = Map.keys(entity.effects) -- Map.keys(effects)

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

    # Cancel all expiration timers
    Enum.each(entity.timers, fn {_id, ref} ->
      Process.cancel_timer(ref)
    end)

    state = %{state | entities: Map.delete(state.entities, entity_guid)}
    Logger.debug("Shard #{state.shard_id}: Cleared all buffs for entity #{entity_guid}")
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

      Logger.debug("Shard #{state.shard_id}: Buff #{buff_id} expired on entity #{entity_guid}")
      CombatBroadcaster.send_buff_remove(entity_guid, buff_id, :expired)
      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:tick, _tick_number}, state) do
    # Coordinated tick from TickScheduler - process all periodic effects
    now = System.monotonic_time(:millisecond)
    process_all_periodic_ticks(state, now)
    {:noreply, state}
  end

  # Private helpers

  defp process_all_periodic_ticks(state, now) do
    Enum.each(state.entities, fn {entity_guid, entity} ->
      Enum.each(entity.effects, fn {buff_id, effect_data} ->
        buff = effect_data.buff

        if BuffDebuff.periodic?(buff) and ActiveEffect.active?(entity.effects, buff_id, now) do
          process_periodic_tick(entity_guid, effect_data.caster_guid, buff)
        end
      end)
    end)
  end

  defp process_periodic_tick(entity_guid, caster_guid, buff) do
    if buff.is_debuff do
      # DoT - damage over time
      Logger.debug(
        "Periodic damage tick: #{buff.amount} to entity #{entity_guid} from buff #{buff.id}"
      )

      effect = %{type: :damage, amount: buff.amount, is_crit: false}

      CombatBroadcaster.send_spell_effect(caster_guid, entity_guid, buff.spell_id, effect, [
        entity_guid
      ])
    else
      # HoT - heal over time
      Logger.debug(
        "Periodic heal tick: #{buff.amount} to entity #{entity_guid} from buff #{buff.id}"
      )

      effect = %{type: :heal, amount: buff.amount, is_crit: false}

      CombatBroadcaster.send_spell_effect(caster_guid, entity_guid, buff.spell_id, effect, [
        entity_guid
      ])
    end
  end

  defp get_entity_state(state, entity_guid) do
    Map.get(state.entities, entity_guid, %{
      effects: ActiveEffect.new(),
      timers: %{}
    })
  end

  defp put_entity_state(state, entity_guid, entity) do
    %{state | entities: Map.put(state.entities, entity_guid, entity)}
  end
end
