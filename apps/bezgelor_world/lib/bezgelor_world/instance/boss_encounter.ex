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
      players: Keyword.get(opts, :players, %{})
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

    Logger.info("Boss encounter #{state.boss_id} initialized with #{health} health, phase: #{inspect(initial_phase)}")

    state
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
    # Record phase in history
    phase_history = [state.current_phase | state.phase_history]

    # Apply phase modifiers
    modifiers = new_phase["modifiers"] || new_phase[:modifiers] || %{}

    # Reset ability cooldowns for new abilities
    abilities = new_phase["abilities"] || new_phase[:abilities] || []
    cooldowns = initialize_cooldowns(abilities)

    %{state |
      current_phase: new_phase,
      phase_history: phase_history,
      ability_cooldowns: cooldowns,
      damage_modifiers: Map.merge(state.damage_modifiers, modifiers)
    }
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
    # In a real implementation, this would send damage to affected players
    # via the zone/world server
    _amount = effect[:amount] || effect["amount"] || 0
    _damage_type = effect[:damage_type] || effect["damage_type"] || :physical
    state
  end

  defp process_telegraph_effect(state, effect) do
    # In a real implementation, this would send telegraph packets to players
    _shape = effect[:shape] || effect["shape"]
    _duration = effect[:duration] || effect["duration"] || 2000
    state
  end

  defp process_spawn_effect(state, effect) do
    params = effect[:params] || effect["params"] || %{}
    creature_id = params[:creature_id] || params["creature_id"]
    count = params[:count] || params["count"] || 1

    # Create add entries
    new_adds =
      for _ <- 1..count do
        %{
          guid: System.unique_integer([:positive]),
          creature_id: creature_id,
          health: 10000,  # Would be looked up from creature definition
          spawned_at: System.monotonic_time(:millisecond)
        }
      end

    %{state | active_adds: state.active_adds ++ new_adds}
  end

  defp process_debuff_effect(state, effect) do
    # In a real implementation, this would apply debuffs to players
    _name = effect[:name] || effect["name"]
    _duration = effect[:duration] || effect["duration"] || 10000
    state
  end

  defp process_buff_effect(state, effect) do
    name = effect[:name] || effect["name"]
    duration = effect[:duration] || effect["duration"] || 10000

    active_buffs = Map.put(state.active_buffs, name, %{
      expires_at: System.monotonic_time(:millisecond) + duration,
      stacks: effect[:stacks] || effect["stacks"] || 1
    })

    %{state | active_buffs: active_buffs}
  end

  defp process_movement_effect(state, effect) do
    # In a real implementation, this would apply movement to players
    _movement_type = effect[:movement_type] || effect["movement_type"]
    state
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

    # Notify instance
    BezgelorWorld.Instance.Instance.boss_defeated(state.instance_guid, state.boss_id)

    %{state | state: :defeated}
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
end
