defmodule BezgelorWorld.SpellManager do
  @moduledoc """
  Manages spell casting state for players.

  ## Overview

  The SpellManager tracks:
  - Active spell casts (for cast-time spells)
  - Spell cooldowns per player
  - Cast completion timers

  This is a per-player state manager, typically called by the SpellHandler
  to process spell cast requests.

  ## Cast State

  When a player starts casting a spell with cast time > 0, their cast state
  is tracked. The state includes the spell ID, target, start time, and
  scheduled completion timer.

  ## Cooldowns

  Cooldowns are tracked using monotonic time. When a spell is cast, its
  cooldown is recorded. The global cooldown (GCD) is also tracked.
  """

  use GenServer

  alias BezgelorCore.{Spell, SpellEffect, Cooldown}

  require Logger

  @type cast_state :: %{
          spell_id: non_neg_integer(),
          target_guid: non_neg_integer() | nil,
          target_position: {float(), float(), float()} | nil,
          start_time: integer(),
          duration: non_neg_integer(),
          timer_ref: reference() | nil
        }

  @type player_state :: %{
          cast: cast_state() | nil,
          cooldowns: Cooldown.cooldown_state()
        }

  @type state :: %{
          players: %{non_neg_integer() => player_state()}
        }

  ## Client API

  @doc "Start the SpellManager."
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Attempt to cast a spell.

  Returns one of:
  - `{:ok, :instant}` - Instant cast succeeded
  - `{:ok, :casting, cast_time}` - Cast started with given duration
  - `{:error, reason}` - Cast failed with reason
  """
  @spec cast_spell(non_neg_integer(), non_neg_integer(), non_neg_integer() | nil, tuple() | nil, map()) ::
          {:ok, :instant, map()} | {:ok, :casting, non_neg_integer()} | {:error, atom()}
  def cast_spell(player_guid, spell_id, target_guid, target_position, caster_stats) do
    GenServer.call(__MODULE__, {:cast_spell, player_guid, spell_id, target_guid, target_position, caster_stats})
  end

  @doc """
  Cancel the current cast for a player.
  """
  @spec cancel_cast(non_neg_integer()) :: :ok | {:error, :not_casting}
  def cancel_cast(player_guid) do
    GenServer.call(__MODULE__, {:cancel_cast, player_guid})
  end

  @doc """
  Check if a player is currently casting.
  """
  @spec casting?(non_neg_integer()) :: boolean()
  def casting?(player_guid) do
    GenServer.call(__MODULE__, {:casting?, player_guid})
  end

  @doc """
  Get current cast info for a player.
  """
  @spec get_cast(non_neg_integer()) :: cast_state() | nil
  def get_cast(player_guid) do
    GenServer.call(__MODULE__, {:get_cast, player_guid})
  end

  @doc """
  Check if a spell is ready (not on cooldown, GCD ready).
  """
  @spec spell_ready?(non_neg_integer(), non_neg_integer()) :: boolean()
  def spell_ready?(player_guid, spell_id) do
    GenServer.call(__MODULE__, {:spell_ready?, player_guid, spell_id})
  end

  @doc """
  Get remaining cooldown for a spell.
  """
  @spec get_cooldown(non_neg_integer(), non_neg_integer()) :: non_neg_integer()
  def get_cooldown(player_guid, spell_id) do
    GenServer.call(__MODULE__, {:get_cooldown, player_guid, spell_id})
  end

  @doc """
  Clear all state for a player (on logout/disconnect).
  """
  @spec clear_player(non_neg_integer()) :: :ok
  def clear_player(player_guid) do
    GenServer.cast(__MODULE__, {:clear_player, player_guid})
  end

  ## Server Callbacks

  @impl true
  def init(_opts) do
    state = %{
      players: %{}
    }

    Logger.info("SpellManager started")
    {:ok, state}
  end

  @impl true
  def handle_call({:cast_spell, player_guid, spell_id, target_guid, target_position, caster_stats}, _from, state) do
    player = get_player_state(state, player_guid)

    case validate_cast(spell_id, player) do
      {:ok, spell} ->
        if Spell.instant?(spell) do
          # Instant cast - apply effects immediately
          {result, player} = do_instant_cast(spell, player, caster_stats)
          state = put_player_state(state, player_guid, player)
          {:reply, {:ok, :instant, result}, state}
        else
          # Cast time spell - start casting
          {player, _timer_ref} = start_cast(spell, target_guid, target_position, player, player_guid)
          state = put_player_state(state, player_guid, player)
          {:reply, {:ok, :casting, spell.cast_time}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:cancel_cast, player_guid}, _from, state) do
    player = get_player_state(state, player_guid)

    case player.cast do
      nil ->
        {:reply, {:error, :not_casting}, state}

      cast ->
        # Cancel the timer
        if cast.timer_ref, do: Process.cancel_timer(cast.timer_ref)

        player = %{player | cast: nil}
        state = put_player_state(state, player_guid, player)
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call({:casting?, player_guid}, _from, state) do
    player = get_player_state(state, player_guid)
    {:reply, player.cast != nil, state}
  end

  @impl true
  def handle_call({:get_cast, player_guid}, _from, state) do
    player = get_player_state(state, player_guid)
    {:reply, player.cast, state}
  end

  @impl true
  def handle_call({:spell_ready?, player_guid, spell_id}, _from, state) do
    player = get_player_state(state, player_guid)
    spell = Spell.get(spell_id)
    ready = spell != nil and Cooldown.can_cast?(player.cooldowns, spell_id, spell.gcd)
    {:reply, ready, state}
  end

  @impl true
  def handle_call({:get_cooldown, player_guid, spell_id}, _from, state) do
    player = get_player_state(state, player_guid)
    remaining = Cooldown.remaining(player.cooldowns, spell_id)
    {:reply, remaining, state}
  end

  @impl true
  def handle_cast({:clear_player, player_guid}, state) do
    # Cancel any active cast timer
    case get_in(state.players, [player_guid, :cast, :timer_ref]) do
      nil -> :ok
      ref -> Process.cancel_timer(ref)
    end

    state = %{state | players: Map.delete(state.players, player_guid)}
    {:noreply, state}
  end

  @impl true
  def handle_info({:cast_complete, player_guid, spell_id}, state) do
    player = get_player_state(state, player_guid)

    case player.cast do
      %{spell_id: ^spell_id} = _cast ->
        # Cast completed successfully
        spell = Spell.get(spell_id)

        # Apply cooldowns
        cooldowns = Cooldown.apply_cast(
          player.cooldowns,
          spell_id,
          spell.cooldown,
          spell.gcd,
          Spell.global_cooldown()
        )

        player = %{player | cast: nil, cooldowns: cooldowns}
        state = put_player_state(state, player_guid, player)

        # Notify the player's connection about cast completion
        # This would be done through WorldManager or direct process message
        Logger.debug("Cast completed: player #{player_guid} spell #{spell_id}")

        {:noreply, state}

      _ ->
        # Cast was cancelled or different spell
        {:noreply, state}
    end
  end

  # Private functions

  defp get_player_state(state, player_guid) do
    Map.get(state.players, player_guid, %{cast: nil, cooldowns: Cooldown.new()})
  end

  defp put_player_state(state, player_guid, player) do
    %{state | players: Map.put(state.players, player_guid, player)}
  end

  defp validate_cast(spell_id, player) do
    spell = Spell.get(spell_id)

    cond do
      spell == nil ->
        {:error, :not_known}

      player.cast != nil ->
        {:error, :already_casting}

      not Cooldown.can_cast?(player.cooldowns, spell_id, spell.gcd) ->
        {:error, :cooldown}

      true ->
        {:ok, spell}
    end
  end

  defp do_instant_cast(spell, player, caster_stats) do
    # Apply cooldowns
    cooldowns = Cooldown.apply_cast(
      player.cooldowns,
      spell.id,
      spell.cooldown,
      spell.gcd,
      Spell.global_cooldown()
    )

    player = %{player | cooldowns: cooldowns}

    # Calculate effect results
    effects = calculate_effects(spell, caster_stats)

    result = %{
      spell_id: spell.id,
      effects: effects,
      cooldown: spell.cooldown,
      gcd: if(spell.gcd, do: Spell.global_cooldown(), else: 0)
    }

    {result, player}
  end

  defp start_cast(spell, target_guid, target_position, player, player_guid) do
    # Schedule cast completion
    timer_ref = Process.send_after(self(), {:cast_complete, player_guid, spell.id}, spell.cast_time)

    cast = %{
      spell_id: spell.id,
      target_guid: target_guid,
      target_position: target_position,
      start_time: System.monotonic_time(:millisecond),
      duration: spell.cast_time,
      timer_ref: timer_ref
    }

    {%{player | cast: cast}, timer_ref}
  end

  defp calculate_effects(spell, caster_stats) do
    Enum.map(spell.effects, fn effect ->
      {amount, is_crit} = SpellEffect.calculate(effect, caster_stats, %{})

      %{
        type: effect.type,
        amount: amount,
        is_crit: is_crit
      }
    end)
  end
end
