defmodule BezgelorWorld.BuffManager do
  @moduledoc """
  Manages active buffs and debuffs for all entities.

  ## Overview

  The BuffManager tracks:
  - Active buffs/debuffs per entity
  - Expiration timers for automatic removal
  - Stat modifiers from buff effects
  - Absorb shield values

  ## Sharding

  Buff management is distributed across multiple shards (GenServer processes)
  to avoid a single-process bottleneck. Entities are assigned to shards using
  `rem(entity_guid, num_shards)` for consistent routing.

  The number of shards is configurable via application config:

      config :bezgelor_world, :buff_manager_shards, 8

  ## State Structure (per shard)

      %{
        entities: %{
          entity_guid => %{
            effects: ActiveEffect.state(),
            timers: %{buff_id => timer_ref}
          }
        }
      }
  """

  use Supervisor

  alias BezgelorCore.BuffDebuff
  alias BezgelorWorld.BuffManager.Shard

  require Logger

  # Default number of shards
  @default_num_shards 8

  ## Supervisor

  @doc "Start the BuffManager supervisor with all shards."
  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    num_shards = num_shards()

    # Create the registry for shards
    children = [
      {Registry, keys: :unique, name: BezgelorWorld.BuffManager.Registry}
    ]

    # Add shard children
    shard_children =
      for shard_id <- 0..(num_shards - 1) do
        Supervisor.child_spec(
          {Shard, shard_id: shard_id},
          id: {Shard, shard_id}
        )
      end

    Logger.info("BuffManager starting with #{num_shards} shards")

    Supervisor.init(children ++ shard_children, strategy: :one_for_one)
  end

  ## Client API - Routes to appropriate shard

  @doc """
  Apply a buff/debuff to an entity.

  Returns `{:ok, timer_ref}` with the expiration timer reference.
  """
  @spec apply_buff(non_neg_integer(), BuffDebuff.t(), non_neg_integer()) ::
          {:ok, reference()}
  def apply_buff(entity_guid, %BuffDebuff{} = buff, caster_guid) do
    shard_id = shard_for_entity(entity_guid)
    Shard.apply_buff(shard_id, entity_guid, buff, caster_guid)
  end

  @doc """
  Remove a buff/debuff from an entity.
  """
  @spec remove_buff(non_neg_integer(), non_neg_integer()) :: :ok | {:error, :not_found}
  def remove_buff(entity_guid, buff_id) do
    shard_id = shard_for_entity(entity_guid)
    Shard.remove_buff(shard_id, entity_guid, buff_id)
  end

  @doc """
  Check if an entity has a specific buff.
  """
  @spec has_buff?(non_neg_integer(), non_neg_integer()) :: boolean()
  def has_buff?(entity_guid, buff_id) do
    shard_id = shard_for_entity(entity_guid)
    Shard.has_buff?(shard_id, entity_guid, buff_id)
  end

  @doc """
  Get all active buffs for an entity.
  """
  @spec get_entity_buffs(non_neg_integer()) :: [map()]
  def get_entity_buffs(entity_guid) do
    shard_id = shard_for_entity(entity_guid)
    Shard.get_entity_buffs(shard_id, entity_guid)
  end

  @doc """
  Get total stat modifier for an entity.
  """
  @spec get_stat_modifier(non_neg_integer(), BuffDebuff.stat()) :: integer()
  def get_stat_modifier(entity_guid, stat) do
    shard_id = shard_for_entity(entity_guid)
    Shard.get_stat_modifier(shard_id, entity_guid, stat)
  end

  @doc """
  Consume absorb shields for incoming damage.

  Returns `{absorbed_amount, remaining_damage}`.
  """
  @spec consume_absorb(non_neg_integer(), non_neg_integer()) ::
          {non_neg_integer(), non_neg_integer()}
  def consume_absorb(entity_guid, damage) do
    shard_id = shard_for_entity(entity_guid)
    Shard.consume_absorb(shard_id, entity_guid, damage)
  end

  @doc """
  Clear all buffs from an entity (on death/logout).
  """
  @spec clear_entity(non_neg_integer()) :: :ok
  def clear_entity(entity_guid) do
    shard_id = shard_for_entity(entity_guid)
    Shard.clear_entity(shard_id, entity_guid)
  end

  ## Private

  @doc false
  def shard_for_entity(entity_guid) do
    rem(entity_guid, num_shards())
  end

  @doc false
  def num_shards do
    Application.get_env(:bezgelor_world, :buff_manager_shards, @default_num_shards)
  end
end
