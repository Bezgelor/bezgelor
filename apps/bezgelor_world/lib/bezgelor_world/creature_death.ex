defmodule BezgelorWorld.CreatureDeath do
  @moduledoc """
  Shared creature death handling logic.

  Extracted from creature_manager.ex and zone_manager.ex to avoid duplication.
  Both modules delegate to these functions for consistent death handling.
  """

  alias BezgelorCore.AI
  alias BezgelorWorld.{CombatParticipants, CorpseManager, Loot}

  import Bitwise

  require Logger

  @doc """
  Handle creature death and generate loot/XP rewards.

  ## Parameters

  - `creature_state` - Current creature state with template, entity, ai
  - `entity` - The creature entity
  - `killer_guid` - GUID of the killer
  - `killer_level` - Level of the killer (for loot scaling)
  - `opts` - Options
    - `:zone_id` - Zone ID for logging (optional)
    - `:instance_id` - Instance ID for logging (optional)
    - `:group_size` - Number of players in the group (for loot bonuses)
    - `:class_id` - Player class ID (for class-specific equipment drops)

  ## Returns

  `{result, new_creature_state}` where:
  - `result` is `{:ok, :killed, result_info}`
  - `new_creature_state` has updated entity, ai, and respawn_timer
  - `result_info` includes `participant_character_ids` for quest credit
  """
  @spec handle_death(map(), map(), non_neg_integer(), non_neg_integer(), Keyword.t()) ::
          {{:ok, :killed, map()}, map()}
  def handle_death(creature_state, entity, killer_guid, killer_level, opts \\ []) do
    template = creature_state.template
    zone_id = Keyword.get(opts, :zone_id, 0)
    instance_id = Keyword.get(opts, :instance_id, 0)

    # Resolve combat participants BEFORE setting AI to dead
    # (set_dead preserves combat_participants, but we want to be explicit)
    participant_character_ids =
      CombatParticipants.resolve(
        creature_state.ai,
        zone_id,
        instance_id
      )

    # Set AI to dead
    ai = AI.set_dead(creature_state.ai)

    # Generate loot using data-driven system
    creature_id = entity.creature_id
    creature_level = template.level

    # Extract loot-related options
    loot_opts = Keyword.take(opts, [:group_size, :class_id, :creature_tier])
    loot_drops = generate_loot(creature_id, creature_level, killer_level, template, loot_opts)

    # Spawn corpse entity if there's loot
    corpse_guid = spawn_corpse_if_needed(entity, loot_drops)

    # Calculate XP reward
    xp_reward = template.xp_reward

    # Start respawn timer
    respawn_timer =
      if template.respawn_time > 0 do
        Process.send_after(self(), {:respawn_creature, entity.guid}, template.respawn_time)
      else
        nil
      end

    new_creature_state = %{
      creature_state
      | entity: entity,
        ai: ai,
        respawn_timer: respawn_timer
    }

    result_info = %{
      creature_guid: entity.guid,
      creature_id: creature_id,
      xp_reward: xp_reward,
      loot_drops: loot_drops,
      gold: Loot.gold_from_drops(loot_drops),
      items: Loot.items_from_drops(loot_drops),
      killer_guid: killer_guid,
      reputation_rewards: template.reputation_rewards || [],
      corpse_guid: corpse_guid,
      participant_character_ids: participant_character_ids
    }

    log_death(entity, killer_guid, opts)

    {{:ok, :killed, result_info}, new_creature_state}
  end

  @doc """
  Generate loot drops for a killed creature.

  Uses the data-driven loot system if creature_id is present,
  otherwise falls back to template's loot_table_id.

  ## Options

  - `:group_size` - Number of players in the group (for drop bonuses)
  - `:creature_tier` - Creature tier (1-5) for equipment drops
  - `:class_id` - Player class ID for class-specific equipment
  """
  @spec generate_loot(
          non_neg_integer() | nil,
          non_neg_integer(),
          non_neg_integer(),
          map(),
          Keyword.t()
        ) ::
          [{non_neg_integer(), non_neg_integer()}]
  def generate_loot(creature_id, creature_level, killer_level, template, opts \\ []) do
    if creature_id && creature_id > 0 do
      # Use data-driven loot system with explicit creature level
      # Pass through group_size and other options for loot bonuses
      loot_opts = build_loot_opts(template, opts)
      Loot.roll_creature_loot(creature_id, creature_level, killer_level, loot_opts)
    else
      # Fall back to template's loot table if no creature_id
      if template.loot_table_id do
        Loot.roll_table(template.loot_table_id)
      else
        []
      end
    end
  end

  # Build loot options from template and caller options
  defp build_loot_opts(template, opts) do
    base_opts = []

    # Add group_size if provided
    base_opts =
      case Keyword.get(opts, :group_size) do
        nil -> base_opts
        size -> Keyword.put(base_opts, :group_size, size)
      end

    # Add creature_tier from template or options
    creature_tier = Keyword.get(opts, :creature_tier) || Map.get(template, :tier, 1)
    base_opts = Keyword.put(base_opts, :creature_tier, creature_tier)

    # Add class_id if provided (for class-specific equipment drops)
    case Keyword.get(opts, :class_id) do
      nil -> base_opts
      class_id -> Keyword.put(base_opts, :class_id, class_id)
    end
  end

  @doc """
  Check if a GUID belongs to a player entity.

  Player GUIDs have type bits = 1 in bits 60-63.
  """
  @spec is_player_guid?(non_neg_integer()) :: boolean()
  def is_player_guid?(guid) when is_integer(guid) do
    # Extract type from bits 60-63
    type = guid >>> 60 &&& 0xF
    type == 1
  end

  def is_player_guid?(_), do: false

  # Log the death with optional zone context
  defp log_death(entity, killer_guid, opts) do
    zone_id = Keyword.get(opts, :zone_id)
    instance_id = Keyword.get(opts, :instance_id)

    if zone_id && instance_id do
      Logger.debug(
        "Zone #{zone_id}/#{instance_id}: Creature #{entity.name} (#{entity.guid}) killed by #{killer_guid}"
      )
    else
      Logger.debug("Creature #{entity.name} (#{entity.guid}) killed by #{killer_guid}")
    end
  end

  # Spawn a corpse entity if there's loot to pick up
  defp spawn_corpse_if_needed(_entity, loot_drops) when loot_drops == [] or is_nil(loot_drops) do
    nil
  end

  defp spawn_corpse_if_needed(entity, loot_drops) do
    case CorpseManager.spawn_corpse(entity, loot_drops) do
      {:ok, corpse_guid} ->
        Logger.debug(
          "Spawned corpse #{corpse_guid} for creature #{entity.guid} with #{length(loot_drops)} loot items"
        )

        corpse_guid

      {:error, reason} ->
        Logger.warning("Failed to spawn corpse for creature #{entity.guid}: #{inspect(reason)}")
        nil
    end
  end
end
