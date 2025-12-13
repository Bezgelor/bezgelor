defmodule BezgelorWorld.Instance.BossEncounter do
  @moduledoc """
  GenServer managing a single boss encounter at runtime.

  This process executes the encounter logic defined by the Boss DSL,
  managing:
  - Phase transitions based on health
  - Ability scheduling and execution
  - Interrupt armor state
  - Add spawns and management
  - Telegraph creation and damage application
  - Enrage timer
  - Victory and wipe conditions

  ## Lifecycle

  1. `:initializing` - Loading encounter definition
  2. `:engaged` - Fight in progress
  3. `:phase_transition` - Transitioning between phases
  4. `:intermission` - Intermission phase active
  5. `:defeated` - Boss killed
  6. `:resetting` - Wipe, returning to initial state
  """
  use GenServer

  alias BezgelorWorld.Instance.Registry, as: InstanceRegistry
  alias BezgelorWorld.{CombatBroadcaster, CreatureManager, WorldManager}
  alias BezgelorProtocol.Packets.World.{ServerTelegraph, ServerBossEngaged, ServerBossPhase, ServerBossDefeated}
  alias BezgelorProtocol.PacketWriter

  require Logger

  @ability_tick_interval 100  # Check abilities every 100ms
  @enrage_damage 999_999

  defstruct [
    :instance_guid,
    :boss_id,
    :boss_definition,
    :encounter_module,
    :difficulty,
    :mythic_level,
    :affix_ids,
    :boss_guid,
    :zone_id,
    boss_position: {0.0, 0.0, 0.0},
    state: :initializing,
    current_phase: nil,
    health_current: 0,
    health_max: 0,
    interrupt_armor_current: 0,
    interrupt_armor_max: 0,
    enrage_timer: nil,
    enrage_time_remaining: nil,
    engage_time: nil,
    ability_cooldowns: %{},
    active_adds: [],
    active_debuffs: %{},
    active_buffs: %{},
    players: %{},
    damage_modifiers: %{},
    phase_history: []
  ]

  @type t :: %__MODULE__{}

  # Client API

  @doc """
  Starts a boss encounter process.
  """
  def start_link(opts) do
    instance_guid = Keyword.fetch!(opts, :instance_guid)
    boss_id = Keyword.fetch!(opts, :boss_id)
    GenServer.start_link(__MODULE__, opts, name: InstanceRegistry.via_boss(instance_guid, boss_id))
  end

  @doc """
  Gets the current encounter state.
  """
  @spec get_state(pid()) :: {:ok, t()}
  def get_state(pid) do
    GenServer.call(pid, :get_state)
  end

  @doc """
  Reports damage dealt to the boss.
  """
  @spec deal_damage(pid(), non_neg_integer(), non_neg_integer()) :: :ok
  def deal_damage(pid, character_id, amount) do
    GenServer.cast(pid, {:damage, character_id, amount})
  end

  @doc """
  Reports an interrupt attempt.
  """
  @spec interrupt(pid(), non_neg_integer()) :: {:ok, atom()} | {:error, term()}
  def interrupt(pid, character_id) do
    GenServer.call(pid, {:interrupt, character_id})
  end

  @doc """
  Reports a player death during the encounter.
  """
  @spec player_died(pid(), non_neg_integer()) :: :ok
  def player_died(pid, character_id) do
    GenServer.cast(pid, {:player_died, character_id})
  end

  @doc """
  Reports add death.
  """
  @spec add_died(pid(), non_neg_integer()) :: :ok
  def add_died(pid, add_guid) do
    GenServer.cast(pid, {:add_died, add_guid})
  end

  @doc """
  Called when all players die (wipe).
  """
  @spec wipe(pid()) :: :ok
  def wipe(pid) do
    GenServer.cast(pid, :wipe)
  end

  @doc """
  Gets boss info for packets.
  """
  @spec get_info(pid()) :: {:ok, map()}
  def get_info(pid) do
    GenServer.call(pid, :get_info)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    state = %__MODULE__{
      instance_guid: Keyword.fetch!(opts, :instance_guid),
      boss_id: Keyword.fetch!(opts, :boss_id),
      boss_definition: Keyword.get(opts, :boss_definition, %{}),
      difficulty: Keyword.get(opts, :difficulty, :normal),
      mythic_level: Keyword.get(opts, :mythic_level, 0),
      affix_ids: Keyword.get(opts, :affix_ids, []),
      players: Keyword.get(opts, :players, %{}),
      boss_guid: Keyword.get(opts, :boss_guid),
      zone_id: Keyword.get(opts, :zone_id),
      boss_position: Keyword.get(opts, :boss_position, {0.0, 0.0, 0.0})
    }

    send(self(), :initialize)

    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, {:ok, state}, state}
  end

  def handle_call({:interrupt, character_id}, _from, state) do
    cond do
      state.interrupt_armor_current <= 0 ->
        {:reply, {:error, :no_armor}, state}

      state.interrupt_armor_current == :infinite ->
        {:reply, {:error, :uninterruptible}, state}

      true ->
        new_armor = state.interrupt_armor_current - 1

        Logger.debug("Interrupt from #{character_id}, armor: #{state.interrupt_armor_current} -> #{new_armor}")

        if new_armor <= 0 do
          # Moment of Opportunity triggered
          state = trigger_moo(state)
          {:reply, {:ok, :moo_triggered}, state}
        else
          {:reply, {:ok, :armor_reduced}, %{state | interrupt_armor_current: new_armor}}
        end
    end
  end

  def handle_call(:get_info, _from, state) do
    info = %{
      boss_id: state.boss_id,
      name: get_boss_name(state),
      health_current: state.health_current,
      health_max: state.health_max,
      phase: state.current_phase,
      interrupt_armor: state.interrupt_armor_current,
      enrage_time_remaining: state.enrage_time_remaining
    }

    {:reply, {:ok, info}, state}
  end

  @impl true
  def handle_cast({:damage, character_id, amount}, state) do
    # Apply damage modifiers (vulnerability, resistance, etc.)
    modified_amount = apply_damage_modifiers(state, amount)

    new_health = max(0, state.health_current - modified_amount)
    old_health_percent = health_percent(state)
    state = %{state | health_current: new_health}
    new_health_percent = health_percent(state)

    Logger.debug("Boss #{state.boss_id} took #{modified_amount} damage from #{character_id}, health: #{new_health}/#{state.health_max}")

    # Check for phase transition
    state = check_phase_transition(state, old_health_percent, new_health_percent)

    # Check for death
    state =
      if new_health <= 0 do
        handle_defeat(state)
      else
        state
      end

    {:noreply, state}
  end

  def handle_cast({:player_died, character_id}, state) do
    players = update_in(state.players[character_id] || %{}, [:alive], fn _ -> false end)
    state = %{state | players: Map.put(state.players, character_id, players[character_id] || %{alive: false})}

    # Check if all players are dead
    if all_players_dead?(state) do
      handle_wipe(state)
    else
      {:noreply, state}
    end
  end

  def handle_cast({:add_died, add_guid}, state) do
    active_adds = Enum.reject(state.active_adds, &(&1.guid == add_guid))
    {:noreply, %{state | active_adds: active_adds}}
  end

  def handle_cast(:wipe, state) do
    handle_wipe(state)
  end

  @impl true
  def handle_info(:initialize, state) do
    state = initialize_encounter(state)
    {:noreply, state}
  end

  def handle_info(:ability_tick, state) do
    if state.state == :engaged do
      state = process_abilities(state)
      schedule_ability_tick()
      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  def handle_info(:enrage, state) do
    Logger.warning("Boss #{state.boss_id} enraged!")
    state = trigger_enrage(state)
    {:noreply, state}
  end

  def handle_info({:ability_ready, ability_name}, state) do
    if state.state == :engaged do
      state = execute_ability(state, ability_name)
      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  def handle_info({:spawn_wave, creature_id, count}, state) do
    if state.state == :engaged do
      state = spawn_adds(state, %{creature_id: creature_id, count: count, spread: true})
      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private Functions

  defp initialize_encounter(state) do
    # Get health from definition
    base_health = get_in(state.boss_definition, ["health"]) || 500_000
    health = scale_health(base_health, state.difficulty, state.mythic_level, map_size(state.players))

    # Get interrupt armor
    ia_max = get_in(state.boss_definition, ["interrupt_armor"]) || 2

    # Get enrage timer
    enrage_ms = get_in(state.boss_definition, ["enrage_timer"]) || 480_000

    # Find initial phase
    phases = get_in(state.boss_definition, ["phases"]) || []
    initial_phase = find_phase_for_health(phases, 100)

    state = %{state |
      health_current: health,
      health_max: health,
      interrupt_armor_current: ia_max,
      interrupt_armor_max: ia_max,
      enrage_timer: enrage_ms,
      enrage_time_remaining: enrage_ms,
      engage_time: System.monotonic_time(:millisecond),
      current_phase: initial_phase,
      state: :engaged
    }

    # Schedule enrage
    if enrage_ms > 0 do
      Process.send_after(self(), :enrage, enrage_ms)
    end

    # Start ability tick
    schedule_ability_tick()

    # Broadcast boss engaged to all players
    broadcast_boss_engaged(state)

    Logger.info("Boss encounter #{state.boss_id} initialized with #{health} health, phase: #{inspect(initial_phase)}")

    state
  end

  defp broadcast_boss_engaged(state) do
    packet = %ServerBossEngaged{
      boss_id: state.boss_id,
      boss_guid: state.boss_guid || 0,
      name: get_boss_name(state),
      health_current: state.health_current,
      health_max: state.health_max,
      phase: get_phase_number(state.current_phase),
      enrage_timer: div(state.enrage_timer || 0, 1000)  # Convert ms to seconds
    }

    broadcast_boss_packet(packet, state)
  end

  defp scale_health(base, difficulty, mythic_level, player_count) do
    difficulty_mult =
      case difficulty do
        :normal -> 1.0
        :veteran -> 1.5
        :challenge -> 2.0
        :mythic_plus -> 1.5 + (mythic_level * 0.1)
      end

    player_mult =
      cond do
        player_count <= 5 -> 1.0
        player_count <= 20 -> player_count / 5
        true -> player_count / 10
      end

    round(base * difficulty_mult * player_mult)
  end

  defp health_percent(state) do
    if state.health_max > 0 do
      state.health_current * 100 / state.health_max
    else
      0
    end
  end

  defp find_phase_for_health(phases, health_percent) do
    Enum.find(phases, fn phase ->
      condition = phase["condition"] || phase[:condition]
      check_phase_condition(condition, health_percent)
    end)
  end

  defp check_phase_condition({:health_above, threshold}, health), do: health > threshold
  defp check_phase_condition({:health_below, threshold}, health), do: health < threshold
  defp check_phase_condition({:health_between, {low, high}}, health), do: health >= low and health <= high
  defp check_phase_condition(%{"health_above" => threshold}, health), do: health > threshold
  defp check_phase_condition(%{"health_below" => threshold}, health), do: health < threshold
  defp check_phase_condition(:always, _health), do: true
  defp check_phase_condition(nil, _health), do: true
  defp check_phase_condition(_, _health), do: false

  defp check_phase_transition(state, old_percent, new_percent) do
    phases = get_in(state.boss_definition, ["phases"]) || []
    new_phase = find_phase_for_health(phases, new_percent)

    if new_phase && new_phase != state.current_phase do
      Logger.info("Boss #{state.boss_id} transitioning from #{inspect(state.current_phase)} to #{inspect(new_phase)}")
      transition_to_phase(state, new_phase)
    else
      state
    end
  end

  defp transition_to_phase(state, new_phase) do
    old_phase = state.current_phase

    # Record phase in history
    phase_history = [old_phase | state.phase_history]

    # Apply phase modifiers
    modifiers = new_phase["modifiers"] || new_phase[:modifiers] || %{}

    # Reset ability cooldowns for new abilities
    abilities = new_phase["abilities"] || new_phase[:abilities] || []
    cooldowns = initialize_cooldowns(abilities)

    state = %{state |
      current_phase: new_phase,
      phase_history: phase_history,
      ability_cooldowns: cooldowns,
      damage_modifiers: Map.merge(state.damage_modifiers, modifiers)
    }

    # Broadcast phase transition
    broadcast_phase_transition(state, old_phase, new_phase)

    state
  end

  defp broadcast_phase_transition(state, old_phase, new_phase) do
    # Determine transition type
    transition_type =
      cond do
        health_percent(state) <= 20 -> :final
        new_phase[:always] || new_phase["always"] -> :intermission
        true -> :normal
      end

    packet = %ServerBossPhase{
      boss_guid: state.boss_guid || 0,
      old_phase: get_phase_number(old_phase),
      new_phase: get_phase_number(new_phase),
      health_percent: round(health_percent(state)),
      transition_type: transition_type,
      active_mechanics: []
    }

    broadcast_boss_packet(packet, state)
  end

  defp initialize_cooldowns(abilities) do
    now = System.monotonic_time(:millisecond)

    Map.new(abilities, fn ability ->
      name = ability["name"] || ability[:name]
      cooldown = ability["cooldown"] || ability[:cooldown] || 0
      # Stagger initial cooldowns slightly
      initial_delay = :rand.uniform(max(1, div(cooldown, 2)))
      {name, now + initial_delay}
    end)
  end

  defp schedule_ability_tick do
    Process.send_after(self(), :ability_tick, @ability_tick_interval)
  end

  defp process_abilities(state) do
    now = System.monotonic_time(:millisecond)
    abilities = get_phase_abilities(state)

    Enum.reduce(abilities, state, fn ability, acc ->
      name = ability["name"] || ability[:name]
      cooldown = ability["cooldown"] || ability[:cooldown] || 0
      last_used = Map.get(acc.ability_cooldowns, name, 0)

      if now >= last_used do
        execute_ability(acc, ability)
        |> put_in([:ability_cooldowns, name], now + cooldown)
      else
        acc
      end
    end)
  end

  defp get_phase_abilities(state) do
    case state.current_phase do
      %{"abilities" => abilities} -> abilities
      %{abilities: abilities} -> abilities
      _ -> []
    end
  end

  defp execute_ability(state, ability) when is_atom(ability) do
    abilities = get_phase_abilities(state)
    ability_def = Enum.find(abilities, fn a ->
      (a["name"] || a[:name]) == ability
    end)

    if ability_def do
      execute_ability(state, ability_def)
    else
      state
    end
  end

  defp execute_ability(state, ability) when is_map(ability) do
    name = ability["name"] || ability[:name]
    Logger.debug("Boss #{state.boss_id} executing ability: #{name}")

    # Process each effect
    effects = ability["effects"] || ability[:effects] || []

    Enum.reduce(effects, state, fn effect, acc ->
      process_effect(acc, effect, ability)
    end)
  end

  defp process_effect(state, effect, _ability) do
    type = effect["type"] || effect[:type]

    case type do
      :damage -> process_damage_effect(state, effect)
      :telegraph -> process_telegraph_effect(state, effect)
      :spawn -> process_spawn_effect(state, effect)
      :debuff -> process_debuff_effect(state, effect)
      :buff -> process_buff_effect(state, effect)
      :movement -> process_movement_effect(state, effect)
      :coordination -> process_coordination_effect(state, effect)
      :environmental -> process_environmental_effect(state, effect)
      _ -> state
    end
  end

  defp process_damage_effect(state, effect) do
    amount = effect[:amount] || effect["amount"] || 0
    damage_type = effect[:damage_type] || effect["damage_type"] || :physical
    target_type = effect[:target] || effect["target"] || :all

    # Get target player GUIDs based on target type
    target_guids = get_target_guids(state, target_type)

    if Enum.empty?(target_guids) do
      state
    else
      boss_guid = state.boss_guid || 0
      spell_id = effect[:spell_id] || effect["spell_id"] || 0

      # Send damage effect to each target
      Enum.each(target_guids, fn target_guid ->
        effect_data = %{type: :damage, amount: amount, damage_type: damage_type}
        CombatBroadcaster.send_spell_effect(boss_guid, target_guid, spell_id, effect_data, target_guids)
      end)

      Logger.debug("Applied #{amount} #{damage_type} damage to #{length(target_guids)} players")
      state
    end
  end

  # Get target GUIDs based on target type
  defp get_target_guids(state, target_type) do
    all_guids = get_player_entity_guids(state)

    case target_type do
      :all -> all_guids
      :random -> Enum.take_random(all_guids, 1)
      :tank -> get_role_guids(state, :tank) |> Enum.take(1)
      :healer -> get_role_guids(state, :healer) |> Enum.take_random(1)
      :farthest -> all_guids |> Enum.take(1)  # TODO: Calculate actual distance
      :nearest -> all_guids |> Enum.take(1)   # TODO: Calculate actual distance
      _ -> all_guids
    end
  end

  # Get GUIDs for players with a specific role
  defp get_role_guids(state, role) do
    state.players
    |> Enum.filter(fn {_id, player} -> player[:role] == role end)
    |> Enum.map(fn {character_id, _player} ->
      case WorldManager.get_session_by_character(character_id) do
        nil -> nil
        session -> session.entity_guid
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp process_telegraph_effect(state, effect) do
    shape = effect[:shape] || effect["shape"]
    duration = effect[:duration] || effect["duration"] || 2000
    radius = effect[:radius] || effect["radius"] || 5.0
    color = effect[:color] || effect["color"] || :red
    position = effect[:position] || effect["position"] || state.boss_position

    # Ensure position is a tuple
    position = normalize_position(position, state.boss_position)

    # Get all player entity GUIDs in the encounter
    recipient_guids = get_player_entity_guids(state)

    if Enum.empty?(recipient_guids) do
      Logger.debug("No players to broadcast telegraph to")
      state
    else
      # Send telegraph based on shape
      boss_guid = state.boss_guid || 0

      case shape do
        :circle ->
          CombatBroadcaster.broadcast_circle_telegraph(
            boss_guid,
            position,
            radius,
            duration,
            color,
            recipient_guids
          )

        :cone ->
          angle = effect[:angle] || effect["angle"] || 90.0
          length = effect[:length] || effect["length"] || 15.0
          rotation = effect[:rotation] || effect["rotation"] || 0.0

          CombatBroadcaster.broadcast_cone_telegraph(
            boss_guid,
            position,
            angle,
            length,
            rotation,
            duration,
            color,
            recipient_guids
          )

        :donut ->
          inner = effect[:inner_radius] || effect["inner_radius"] || 5.0
          outer = effect[:outer_radius] || effect["outer_radius"] || 15.0
          packet = ServerTelegraph.donut(boss_guid, position, inner, outer, duration, color)
          CombatBroadcaster.broadcast_telegraph(packet, recipient_guids)

        :line ->
          # Line telegraphs use rectangle shape
          width = effect[:width] || effect["width"] || 3.0
          length = effect[:length] || effect["length"] || 20.0
          rotation = effect[:rotation] || effect["rotation"] || 0.0
          packet = ServerTelegraph.rectangle(boss_guid, position, width, length, rotation, duration, color)
          CombatBroadcaster.broadcast_telegraph(packet, recipient_guids)

        :room_wide ->
          # Room-wide telegraphs use a large circle
          packet = ServerTelegraph.circle(boss_guid, position, 50.0, duration, color)
          CombatBroadcaster.broadcast_telegraph(packet, recipient_guids)

        _ ->
          Logger.warning("Unknown telegraph shape: #{inspect(shape)}, defaulting to circle")
          CombatBroadcaster.broadcast_circle_telegraph(
            boss_guid,
            position,
            radius,
            duration,
            color,
            recipient_guids
          )
      end

      Logger.debug("Broadcast #{shape} telegraph to #{length(recipient_guids)} players")
      state
    end
  end

  # Convert position to tuple if needed
  defp normalize_position({_x, _y, _z} = pos, _default), do: pos
  defp normalize_position([x, y, z], _default), do: {x, y, z}
  defp normalize_position(%{"x" => x, "y" => y, "z" => z}, _default), do: {x, y, z}
  defp normalize_position(nil, default), do: default
  defp normalize_position(_, default), do: default

  # Get entity GUIDs for all players in the encounter
  defp get_player_entity_guids(state) do
    state.players
    |> Map.keys()
    |> Enum.map(&WorldManager.get_session_by_character/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(& &1.entity_guid)
    |> Enum.reject(&is_nil/1)
  end

  defp process_spawn_effect(state, effect) do
    spawn_type = effect[:spawn_type] || effect["spawn_type"] || :add
    params = effect[:params] || effect["params"] || %{}

    case spawn_type do
      :add -> spawn_adds(state, params)
      :wave -> spawn_wave(state, params)
      _ -> spawn_adds(state, params)
    end
  end

  defp spawn_adds(state, params) do
    creature_id = params[:creature_id] || params["creature_id"]
    count = params[:count] || params["count"] || 1
    spread = params[:spread] || params["spread"] || false
    spread_radius = params[:spread_radius] || params["spread_radius"] || 10.0
    aggro_type = params[:aggro] || params["aggro"] || :random
    despawn_on_death = params[:despawn_on_boss_death] || params["despawn_on_boss_death"] || true

    {boss_x, boss_y, boss_z} = state.boss_position

    # Calculate spawn positions
    positions = calculate_spawn_positions(boss_x, boss_y, boss_z, count, spread, spread_radius)

    # Spawn each add via CreatureManager
    new_adds =
      positions
      |> Enum.map(fn position ->
        case CreatureManager.spawn_creature(creature_id, position) do
          {:ok, guid} ->
            # Set initial aggro based on type
            set_add_aggro(state, guid, aggro_type)

            %{
              guid: guid,
              creature_id: creature_id,
              spawned_at: System.monotonic_time(:millisecond),
              despawn_on_boss_death: despawn_on_death
            }

          {:error, reason} ->
            Logger.warning("Failed to spawn add #{creature_id}: #{inspect(reason)}")
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    Logger.debug("Spawned #{length(new_adds)} adds (creature_id: #{creature_id})")
    %{state | active_adds: state.active_adds ++ new_adds}
  end

  defp spawn_wave(state, params) do
    creature_id = params[:creature_id] || params["creature_id"]
    waves = params[:waves] || params["waves"] || 3
    per_wave = params[:per_wave] || params["per_wave"] || 2
    wave_interval = params[:wave_interval] || params["wave_interval"] || 10_000

    # Spawn first wave immediately
    state = spawn_adds(state, %{creature_id: creature_id, count: per_wave, spread: true})

    # Schedule remaining waves
    for wave_num <- 2..waves do
      delay = (wave_num - 1) * wave_interval
      Process.send_after(self(), {:spawn_wave, creature_id, per_wave}, delay)
    end

    state
  end

  defp calculate_spawn_positions(boss_x, boss_y, boss_z, count, spread, spread_radius) do
    if spread and count > 1 do
      # Spread adds in a circle around the boss
      angle_step = 2 * :math.pi() / count
      for i <- 0..(count - 1) do
        angle = i * angle_step
        x = boss_x + spread_radius * :math.cos(angle)
        z = boss_z + spread_radius * :math.sin(angle)
        {x, boss_y, z}
      end
    else
      # Spawn all at boss position with slight offset
      for i <- 0..(count - 1) do
        offset = i * 2.0
        {boss_x + offset, boss_y, boss_z}
      end
    end
  end

  defp set_add_aggro(state, creature_guid, aggro_type) do
    target_guid =
      case aggro_type do
        :tank -> get_role_guids(state, :tank) |> List.first()
        :healer -> get_role_guids(state, :healer) |> Enum.random()
        :random -> get_player_entity_guids(state) |> Enum.random()
        :fixate -> get_player_entity_guids(state) |> Enum.random()
        _ -> nil
      end

    if target_guid do
      CreatureManager.creature_enter_combat(creature_guid, target_guid)
    end
  end

  defp process_debuff_effect(state, effect) do
    alias BezgelorCore.BuffDebuff
    alias BezgelorWorld.BuffManager

    buff_id = effect[:buff_id] || effect["buff_id"] || System.unique_integer([:positive])
    spell_id = effect[:spell_id] || effect["spell_id"] || 0
    name = effect[:name] || effect["name"]
    duration = effect[:duration] || effect["duration"] || 10000
    amount = effect[:amount] || effect["amount"] || 0
    stacks = effect[:stacks] || effect["stacks"] || 1
    target_type = effect[:target] || effect["target"] || :all

    # Create debuff definition
    debuff = BuffDebuff.new(%{
      id: buff_id,
      spell_id: spell_id,
      buff_type: :stat_modifier,
      amount: -amount,  # Negative for debuffs
      duration: duration,
      is_debuff: true,
      stacks: stacks,
      max_stacks: stacks
    })

    target_guids = get_target_guids(state, target_type)
    boss_guid = state.boss_guid || 0

    if Enum.empty?(target_guids) do
      state
    else
      # Apply debuff to each target
      Enum.each(target_guids, fn target_guid ->
        BuffManager.apply_buff(target_guid, debuff, boss_guid)

        # Broadcast the debuff application to all players
        CombatBroadcaster.broadcast_buff_apply(target_guid, boss_guid, debuff, target_guids)
      end)

      Logger.debug("Applied debuff #{name || buff_id} to #{length(target_guids)} players")
      state
    end
  end

  defp process_buff_effect(state, effect) do
    alias BezgelorCore.BuffDebuff
    alias BezgelorWorld.BuffManager

    name = effect[:name] || effect["name"]
    buff_id = effect[:buff_id] || effect["buff_id"] || System.unique_integer([:positive])
    spell_id = effect[:spell_id] || effect["spell_id"] || 0
    duration = effect[:duration] || effect["duration"] || 10000
    amount = effect[:amount] || effect["amount"] || 0
    stacks = effect[:stacks] || effect["stacks"] || 1
    target = effect[:target] || effect["target"] || :boss

    # Track in local state for the boss
    active_buffs = Map.put(state.active_buffs, name, %{
      expires_at: System.monotonic_time(:millisecond) + duration,
      stacks: stacks
    })

    state = %{state | active_buffs: active_buffs}

    # If this is a buff targeting the boss itself (like invulnerability)
    # Also apply via BuffManager if boss has a GUID
    if target == :boss and state.boss_guid do
      buff = BuffDebuff.new(%{
        id: buff_id,
        spell_id: spell_id,
        buff_type: :stat_modifier,
        amount: amount,
        duration: duration,
        is_debuff: false,
        stacks: stacks,
        max_stacks: stacks
      })

      BuffManager.apply_buff(state.boss_guid, buff, state.boss_guid)

      # Broadcast to players so they see the buff on the boss
      recipient_guids = get_player_entity_guids(state)
      CombatBroadcaster.broadcast_buff_apply(state.boss_guid, state.boss_guid, buff, recipient_guids)
    end

    Logger.debug("Applied buff #{name} (duration: #{duration}ms)")
    state
  end

  defp process_movement_effect(state, effect) do
    movement_type = effect[:movement_type] || effect["movement_type"]
    distance = effect[:distance] || effect["distance"] || 10.0
    target_type = effect[:target] || effect["target"] || :all
    source = effect[:source] || effect["source"] || :boss

    target_guids = get_target_guids(state, target_type)

    if Enum.empty?(target_guids) do
      state
    else
      # Calculate knockback/pull direction from source
      {source_x, source_y, source_z} = get_source_position(state, source)

      Enum.each(target_guids, fn target_guid ->
        # Get player session to find their position
        case WorldManager.get_session_by_entity_guid(target_guid) do
          nil ->
            :ok

          _session ->
            # For knockback, calculate velocity away from source
            # For pull, calculate velocity toward source
            # Note: This is simplified - real implementation would need player position
            {vx, vy, vz} =
              case movement_type do
                :knockback -> {distance * 2.0, 0.0, distance}  # Away + upward
                :pull -> {-distance * 2.0, 0.0, 0.0}           # Toward
                :root -> {0.0, 0.0, 0.0}                        # No movement
                :slow -> {0.0, 0.0, 0.0}                        # Reduced speed
                _ -> {0.0, 0.0, 0.0}
              end

            # Send movement update with velocity (knockback/pull force)
            if vx != 0.0 or vy != 0.0 or vz != 0.0 do
              alias BezgelorProtocol.Packets.World.ServerMovement
              alias BezgelorProtocol.PacketWriter

              # Create movement packet with force
              packet = %ServerMovement{
                guid: target_guid,
                position_x: source_x,
                position_y: source_y,
                position_z: source_z,
                velocity_x: vx,
                velocity_y: vy,
                velocity_z: vz,
                movement_flags: 0x10,  # Forced movement flag
                timestamp: System.monotonic_time(:millisecond) |> rem(0xFFFFFFFF)
              }

              writer = PacketWriter.new()
              {:ok, writer} = ServerMovement.write(packet, writer)
              packet_data = PacketWriter.to_binary(writer)

              # Find connection for this entity and send
              case find_connection_for_guid(target_guid) do
                nil -> :ok
                connection_pid -> WorldManager.send_packet(connection_pid, :server_movement, packet_data)
              end
            end
        end
      end)

      Logger.debug("Applied #{movement_type} (#{distance}m) to #{length(target_guids)} players")
      state
    end
  end

  # Get source position for movement effects
  defp get_source_position(state, source) do
    case source do
      :boss -> state.boss_position
      :center -> {0.0, 0.0, 0.0}  # Room center - would need zone data
      {x, y, z} -> {x, y, z}
      _ -> state.boss_position
    end
  end

  # Find connection PID for an entity GUID
  defp find_connection_for_guid(entity_guid) do
    case WorldManager.get_session_by_entity_guid(entity_guid) do
      nil -> nil
      session -> session.connection_pid
    end
  end

  defp process_coordination_effect(state, effect) do
    # In a real implementation, this would set up coordination mechanics
    _coord_type = effect[:coord_type] || effect["coord_type"]
    state
  end

  defp process_environmental_effect(state, effect) do
    # In a real implementation, this would spawn environmental hazards
    _hazard_type = effect[:hazard_type] || effect["hazard_type"]
    state
  end

  defp apply_damage_modifiers(state, base_amount) do
    # Check for vulnerability/resistance modifiers
    vulnerability = Map.get(state.damage_modifiers, :vulnerable, 0)
    enrage_mult = Map.get(state.damage_modifiers, :enrage, 1.0)

    round(base_amount * (1 + vulnerability / 100) * enrage_mult)
  end

  defp trigger_moo(state) do
    # Moment of Opportunity - boss becomes vulnerable
    Logger.info("Boss #{state.boss_id} MoO triggered!")

    # Apply vulnerability
    modifiers = Map.put(state.damage_modifiers, :vulnerable, 100)

    # Reset interrupt armor
    %{state |
      interrupt_armor_current: state.interrupt_armor_max,
      damage_modifiers: modifiers
    }
  end

  defp trigger_enrage(state) do
    modifiers = Map.put(state.damage_modifiers, :enrage, 5.0)
    %{state | damage_modifiers: modifiers}
  end

  defp handle_defeat(state) do
    Logger.info("Boss #{state.boss_id} defeated!")

    # Calculate fight duration
    fight_duration =
      if state.engage_time do
        div(System.monotonic_time(:millisecond) - state.engage_time, 1000)
      else
        0
      end

    # Despawn adds that are marked despawn_on_boss_death
    despawn_adds(state)

    # Broadcast boss defeated to all players
    broadcast_boss_defeated(state, fight_duration)

    # Notify instance
    BezgelorWorld.Instance.Instance.boss_defeated(state.instance_guid, state.boss_id)

    %{state | state: :defeated, active_adds: []}
  end

  defp broadcast_boss_defeated(state, fight_duration) do
    # Check if this is the final boss (would need instance data)
    is_final = false  # Would check against instance boss list

    packet = %ServerBossDefeated{
      boss_id: state.boss_id,
      boss_guid: state.boss_guid || 0,
      fight_duration: fight_duration,
      is_final_boss: is_final,
      loot_method: :personal,
      lockout_created: true
    }

    broadcast_boss_packet(packet, state)
  end

  defp despawn_adds(state) do
    state.active_adds
    |> Enum.filter(fn add -> Map.get(add, :despawn_on_boss_death, true) end)
    |> Enum.each(fn add ->
      # Kill the add by dealing massive damage
      case CreatureManager.damage_creature(add.guid, state.boss_guid || 0, 999_999_999) do
        {:ok, :killed, _} ->
          Logger.debug("Despawned add #{add.guid}")
        _ ->
          Logger.debug("Add #{add.guid} already dead or not found")
      end
    end)
  end

  defp handle_wipe(state) do
    Logger.info("Boss #{state.boss_id} wipe!")

    # Notify instance
    BezgelorWorld.Instance.Instance.boss_wiped(state.instance_guid, state.boss_id)

    {:noreply, %{state | state: :resetting}}
  end

  defp all_players_dead?(state) do
    state.players
    |> Enum.filter(fn {_id, player} -> Map.get(player, :inside, true) end)
    |> Enum.all?(fn {_id, player} -> Map.get(player, :alive, true) == false end)
  end

  defp get_boss_name(state) do
    get_in(state.boss_definition, ["name"]) ||
      get_in(state.boss_definition, [:name]) ||
      "Unknown Boss"
  end

  # Get phase number from phase definition
  defp get_phase_number(nil), do: 0
  defp get_phase_number(phase) when is_map(phase) do
    name = phase["name"] || phase[:name] || "unknown"
    # Extract phase number from name like "phase_one" or "one"
    case name do
      "phase_one" -> 1
      "phase_two" -> 2
      "phase_three" -> 3
      "phase_four" -> 4
      "one" -> 1
      "two" -> 2
      "three" -> 3
      "four" -> 4
      _ -> length(Map.get(phase, :phase_history, []))
    end
  end
  defp get_phase_number(_), do: 0

  # Broadcast a boss packet to all players in the encounter
  defp broadcast_boss_packet(packet, state) do
    recipient_guids = get_player_entity_guids(state)

    if Enum.empty?(recipient_guids) do
      :ok
    else
      # Write the packet to binary
      writer = PacketWriter.new()
      {:ok, writer} = packet.__struct__.write(packet, writer)
      packet_data = PacketWriter.to_binary(writer)
      opcode = packet.__struct__.opcode()

      # Send to each player
      Enum.each(recipient_guids, fn guid ->
        case find_connection_for_guid(guid) do
          nil -> :ok
          connection_pid -> WorldManager.send_packet(connection_pid, opcode, packet_data)
        end
      end)
    end
  end
end
