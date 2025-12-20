defmodule BezgelorWorld.PvP.DuelManager do
  @moduledoc """
  Manages active duels between players.

  Handles the full duel lifecycle:
  - Challenge request/response
  - Countdown and start
  - Boundary tracking
  - Victory conditions
  - Stats recording
  """

  use GenServer

  require Logger

  alias BezgelorDb.PvP

  # Configuration
  @request_timeout_ms 30_000
  @countdown_seconds 5
  @duel_boundary_radius 40.0
  @duel_timeout_ms 600_000
  @out_of_bounds_grace_ms 5_000

  # Duel states
  @state_pending :pending
  @state_countdown :countdown
  @state_active :active
  @state_ended :ended

  defstruct [
    :id,
    :challenger_guid,
    :challenger_name,
    :target_guid,
    :target_name,
    :state,
    :center,
    :radius,
    :started_at,
    :ends_at,
    :winner_guid,
    :loser_guid,
    :end_reason,
    :out_of_bounds_player,
    :out_of_bounds_at
  ]

  @type duel :: %__MODULE__{
          id: String.t(),
          challenger_guid: non_neg_integer(),
          challenger_name: String.t(),
          target_guid: non_neg_integer(),
          target_name: String.t(),
          state: :pending | :countdown | :active | :ended,
          center: {float(), float(), float()},
          radius: float(),
          started_at: DateTime.t() | nil,
          ends_at: DateTime.t() | nil,
          winner_guid: non_neg_integer() | nil,
          loser_guid: non_neg_integer() | nil,
          end_reason: atom() | nil,
          out_of_bounds_player: non_neg_integer() | nil,
          out_of_bounds_at: integer() | nil
        }

  @type state :: %{
          duels: %{String.t() => duel()},
          player_duels: %{non_neg_integer() => String.t()},
          pending_requests: %{non_neg_integer() => {non_neg_integer(), reference()}}
        }

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Request a duel with another player.
  Returns {:ok, duel_id} or {:error, reason}.
  """
  @spec request_duel(
          non_neg_integer(),
          String.t(),
          non_neg_integer(),
          String.t(),
          {float(), float(), float()}
        ) ::
          {:ok, String.t()} | {:error, atom()}
  def request_duel(challenger_guid, challenger_name, target_guid, target_name, position) do
    GenServer.call(
      __MODULE__,
      {:request_duel, challenger_guid, challenger_name, target_guid, target_name, position}
    )
  end

  @doc """
  Respond to a duel request.
  """
  @spec respond_to_duel(non_neg_integer(), non_neg_integer(), boolean()) ::
          {:ok, duel()} | {:error, atom()}
  def respond_to_duel(target_guid, challenger_guid, accepted) do
    GenServer.call(__MODULE__, {:respond_to_duel, target_guid, challenger_guid, accepted})
  end

  @doc """
  Cancel a pending duel request.
  """
  @spec cancel_request(non_neg_integer(), non_neg_integer()) :: :ok | {:error, atom()}
  def cancel_request(challenger_guid, target_guid) do
    GenServer.call(__MODULE__, {:cancel_request, challenger_guid, target_guid})
  end

  @doc """
  Forfeit an active duel.
  """
  @spec forfeit_duel(non_neg_integer()) :: {:ok, duel()} | {:error, atom()}
  def forfeit_duel(player_guid) do
    GenServer.call(__MODULE__, {:forfeit_duel, player_guid})
  end

  @doc """
  Report player position for boundary checking.
  """
  @spec update_position(non_neg_integer(), {float(), float(), float()}) :: :ok
  def update_position(player_guid, position) do
    GenServer.cast(__MODULE__, {:update_position, player_guid, position})
  end

  @doc """
  Report damage dealt to a duel opponent.
  Returns {:ok, :continue} or {:ok, :ended, duel} if the duel ends.
  """
  @spec report_damage(non_neg_integer(), non_neg_integer(), non_neg_integer()) ::
          {:ok, :continue} | {:ok, :ended, duel()} | {:error, atom()}
  def report_damage(attacker_guid, victim_guid, victim_health) do
    GenServer.call(__MODULE__, {:report_damage, attacker_guid, victim_guid, victim_health})
  end

  @doc """
  Check if a player is in an active duel.
  """
  @spec in_duel?(non_neg_integer()) :: boolean()
  def in_duel?(player_guid) do
    GenServer.call(__MODULE__, {:in_duel?, player_guid})
  end

  @doc """
  Get active duel for a player.
  """
  @spec get_duel(non_neg_integer()) :: {:ok, duel()} | {:error, :not_in_duel}
  def get_duel(player_guid) do
    GenServer.call(__MODULE__, {:get_duel, player_guid})
  end

  @doc """
  Check if two players are dueling each other.
  """
  @spec dueling_each_other?(non_neg_integer(), non_neg_integer()) :: boolean()
  def dueling_each_other?(player1_guid, player2_guid) do
    GenServer.call(__MODULE__, {:dueling_each_other?, player1_guid, player2_guid})
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    Logger.info("DuelManager started")

    state = %{
      duels: %{},
      player_duels: %{},
      pending_requests: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call(
        {:request_duel, challenger_guid, challenger_name, target_guid, target_name, position},
        _from,
        state
      ) do
    cond do
      Map.has_key?(state.player_duels, challenger_guid) ->
        {:reply, {:error, :already_in_duel}, state}

      Map.has_key?(state.player_duels, target_guid) ->
        {:reply, {:error, :target_in_duel}, state}

      Map.has_key?(state.pending_requests, target_guid) ->
        {:reply, {:error, :target_has_pending_request}, state}

      true ->
        # Create timeout for the request
        timer_ref =
          Process.send_after(self(), {:request_timeout, target_guid}, @request_timeout_ms)

        pending = Map.put(state.pending_requests, target_guid, {challenger_guid, timer_ref})
        duel_id = generate_duel_id()

        duel = %__MODULE__{
          id: duel_id,
          challenger_guid: challenger_guid,
          challenger_name: challenger_name,
          target_guid: target_guid,
          target_name: target_name,
          state: @state_pending,
          center: position,
          radius: @duel_boundary_radius
        }

        duels = Map.put(state.duels, duel_id, duel)
        state = %{state | duels: duels, pending_requests: pending}

        Logger.debug("Duel request: #{challenger_name} challenged #{target_name}")
        {:reply, {:ok, duel_id}, state}
    end
  end

  def handle_call({:respond_to_duel, target_guid, challenger_guid, accepted}, _from, state) do
    case Map.get(state.pending_requests, target_guid) do
      nil ->
        {:reply, {:error, :no_pending_request}, state}

      {^challenger_guid, timer_ref} ->
        Process.cancel_timer(timer_ref)
        pending = Map.delete(state.pending_requests, target_guid)

        if accepted do
          # Find the pending duel
          duel =
            Enum.find_value(state.duels, fn {_id, d} ->
              if d.challenger_guid == challenger_guid and d.target_guid == target_guid and
                   d.state == @state_pending do
                d
              end
            end)

          if duel do
            # Start countdown
            duel = %{duel | state: @state_countdown}
            duels = Map.put(state.duels, duel.id, duel)

            # Track both players
            player_duels =
              state.player_duels
              |> Map.put(challenger_guid, duel.id)
              |> Map.put(target_guid, duel.id)

            # Schedule countdown end
            Process.send_after(self(), {:countdown_complete, duel.id}, @countdown_seconds * 1000)

            state = %{state | duels: duels, player_duels: player_duels, pending_requests: pending}
            Logger.debug("Duel accepted, starting countdown")
            {:reply, {:ok, duel}, state}
          else
            {:reply, {:error, :duel_not_found}, %{state | pending_requests: pending}}
          end
        else
          # Declined - remove the pending duel
          duels =
            state.duels
            |> Enum.reject(fn {_id, d} ->
              d.challenger_guid == challenger_guid and d.target_guid == target_guid and
                d.state == @state_pending
            end)
            |> Map.new()

          state = %{state | duels: duels, pending_requests: pending}
          Logger.debug("Duel declined")
          {:reply, {:ok, :declined}, state}
        end

      {_other_challenger, _timer_ref} ->
        {:reply, {:error, :wrong_challenger}, state}
    end
  end

  def handle_call({:cancel_request, challenger_guid, target_guid}, _from, state) do
    case Map.get(state.pending_requests, target_guid) do
      {^challenger_guid, timer_ref} ->
        Process.cancel_timer(timer_ref)
        pending = Map.delete(state.pending_requests, target_guid)

        # Remove the pending duel
        duels =
          state.duels
          |> Enum.reject(fn {_id, d} ->
            d.challenger_guid == challenger_guid and d.target_guid == target_guid and
              d.state == @state_pending
          end)
          |> Map.new()

        state = %{state | duels: duels, pending_requests: pending}
        {:reply, :ok, state}

      _ ->
        {:reply, {:error, :no_pending_request}, state}
    end
  end

  def handle_call({:forfeit_duel, player_guid}, _from, state) do
    case Map.get(state.player_duels, player_guid) do
      nil ->
        {:reply, {:error, :not_in_duel}, state}

      duel_id ->
        duel = Map.get(state.duels, duel_id)

        if duel.state == @state_active do
          opponent_guid =
            if duel.challenger_guid == player_guid,
              do: duel.target_guid,
              else: duel.challenger_guid

          {duel, state} = end_duel(state, duel, opponent_guid, player_guid, :forfeit)
          {:reply, {:ok, duel}, state}
        else
          {:reply, {:error, :duel_not_active}, state}
        end
    end
  end

  def handle_call({:report_damage, attacker_guid, victim_guid, victim_health}, _from, state) do
    # Verify both players are in a duel with each other
    case Map.get(state.player_duels, attacker_guid) do
      nil ->
        {:reply, {:error, :not_in_duel}, state}

      duel_id ->
        duel = Map.get(state.duels, duel_id)

        if duel.state == @state_active and
             ((duel.challenger_guid == attacker_guid and duel.target_guid == victim_guid) or
                (duel.target_guid == attacker_guid and duel.challenger_guid == victim_guid)) do
          if victim_health <= 0 do
            # Duel ended by defeat
            {duel, state} = end_duel(state, duel, attacker_guid, victim_guid, :defeat)
            {:reply, {:ok, :ended, duel}, state}
          else
            {:reply, {:ok, :continue}, state}
          end
        else
          {:reply, {:error, :invalid_duel_combat}, state}
        end
    end
  end

  def handle_call({:in_duel?, player_guid}, _from, state) do
    in_duel = Map.has_key?(state.player_duels, player_guid)
    {:reply, in_duel, state}
  end

  def handle_call({:get_duel, player_guid}, _from, state) do
    case Map.get(state.player_duels, player_guid) do
      nil ->
        {:reply, {:error, :not_in_duel}, state}

      duel_id ->
        duel = Map.get(state.duels, duel_id)
        {:reply, {:ok, duel}, state}
    end
  end

  def handle_call({:dueling_each_other?, player1_guid, player2_guid}, _from, state) do
    case Map.get(state.player_duels, player1_guid) do
      nil ->
        {:reply, false, state}

      duel_id ->
        duel = Map.get(state.duels, duel_id)

        result =
          duel.state == @state_active and
            ((duel.challenger_guid == player1_guid and duel.target_guid == player2_guid) or
               (duel.target_guid == player1_guid and duel.challenger_guid == player2_guid))

        {:reply, result, state}
    end
  end

  @impl true
  def handle_cast({:update_position, player_guid, position}, state) do
    case Map.get(state.player_duels, player_guid) do
      nil ->
        {:noreply, state}

      duel_id ->
        duel = Map.get(state.duels, duel_id)

        if duel.state == @state_active do
          state = check_boundary(state, duel, player_guid, position)
          {:noreply, state}
        else
          {:noreply, state}
        end
    end
  end

  @impl true
  def handle_info({:request_timeout, target_guid}, state) do
    case Map.get(state.pending_requests, target_guid) do
      {challenger_guid, _timer_ref} ->
        pending = Map.delete(state.pending_requests, target_guid)

        # Remove the pending duel
        duels =
          state.duels
          |> Enum.reject(fn {_id, d} ->
            d.challenger_guid == challenger_guid and d.target_guid == target_guid and
              d.state == @state_pending
          end)
          |> Map.new()

        Logger.debug("Duel request timed out")
        {:noreply, %{state | duels: duels, pending_requests: pending}}

      nil ->
        {:noreply, state}
    end
  end

  def handle_info({:countdown_complete, duel_id}, state) do
    case Map.get(state.duels, duel_id) do
      nil ->
        {:noreply, state}

      %{state: @state_countdown} = duel ->
        # Start the duel
        now = DateTime.utc_now()
        ends_at = DateTime.add(now, div(@duel_timeout_ms, 1000), :second)

        duel = %{duel | state: @state_active, started_at: now, ends_at: ends_at}
        duels = Map.put(state.duels, duel_id, duel)

        # Schedule duel timeout
        Process.send_after(self(), {:duel_timeout, duel_id}, @duel_timeout_ms)

        Logger.debug("Duel started: #{duel.challenger_name} vs #{duel.target_name}")
        {:noreply, %{state | duels: duels}}

      _duel ->
        {:noreply, state}
    end
  end

  def handle_info({:duel_timeout, duel_id}, state) do
    case Map.get(state.duels, duel_id) do
      nil ->
        {:noreply, state}

      %{state: @state_active} = duel ->
        # Duel timed out - determine winner by health or declare draw
        # For now, just end with timeout (challenger loses by default)
        {_duel, state} = end_duel(state, duel, duel.target_guid, duel.challenger_guid, :timeout)
        {:noreply, state}

      _duel ->
        {:noreply, state}
    end
  end

  def handle_info({:out_of_bounds_timeout, duel_id, player_guid}, state) do
    case Map.get(state.duels, duel_id) do
      nil ->
        {:noreply, state}

      %{state: @state_active, out_of_bounds_player: ^player_guid} = duel ->
        # Player didn't return in time - they lose
        opponent_guid =
          if duel.challenger_guid == player_guid,
            do: duel.target_guid,
            else: duel.challenger_guid

        {_duel, state} = end_duel(state, duel, opponent_guid, player_guid, :flee)
        {:noreply, state}

      _duel ->
        {:noreply, state}
    end
  end

  def handle_info({:cleanup_duel, duel_id}, state) do
    # Remove ended duel from tracking
    duels = Map.delete(state.duels, duel_id)
    {:noreply, %{state | duels: duels}}
  end

  # Private functions

  defp check_boundary(state, duel, player_guid, {px, py, pz}) do
    {cx, cy, cz} = duel.center

    distance =
      :math.sqrt(
        :math.pow(px - cx, 2) +
          :math.pow(py - cy, 2) +
          :math.pow(pz - cz, 2)
      )

    is_out_of_bounds = distance > duel.radius

    cond do
      is_out_of_bounds and duel.out_of_bounds_player != player_guid ->
        # Player just went out of bounds
        Process.send_after(
          self(),
          {:out_of_bounds_timeout, duel.id, player_guid},
          @out_of_bounds_grace_ms
        )

        duel = %{
          duel
          | out_of_bounds_player: player_guid,
            out_of_bounds_at: System.monotonic_time(:millisecond)
        }

        %{state | duels: Map.put(state.duels, duel.id, duel)}

      not is_out_of_bounds and duel.out_of_bounds_player == player_guid ->
        # Player returned to bounds
        duel = %{duel | out_of_bounds_player: nil, out_of_bounds_at: nil}
        %{state | duels: Map.put(state.duels, duel.id, duel)}

      true ->
        state
    end
  end

  defp end_duel(state, duel, winner_guid, loser_guid, reason) do
    winner_name =
      if duel.challenger_guid == winner_guid, do: duel.challenger_name, else: duel.target_name

    loser_name =
      if duel.challenger_guid == loser_guid, do: duel.challenger_name, else: duel.target_name

    duel = %{
      duel
      | state: @state_ended,
        winner_guid: winner_guid,
        loser_guid: loser_guid,
        end_reason: reason
    }

    # Update duel stats asynchronously
    spawn(fn ->
      record_duel_result(winner_guid, loser_guid)
    end)

    # Clean up
    duels = Map.put(state.duels, duel.id, duel)

    player_duels =
      state.player_duels
      |> Map.delete(duel.challenger_guid)
      |> Map.delete(duel.target_guid)

    # Schedule cleanup of ended duel
    Process.send_after(self(), {:cleanup_duel, duel.id}, 30_000)

    Logger.info("Duel ended: #{winner_name} defeated #{loser_name} (#{reason})")

    {duel, %{state | duels: duels, player_duels: player_duels}}
  end

  defp record_duel_result(winner_id, loser_id) do
    PvP.record_duel(winner_id, true)
    PvP.record_duel(loser_id, false)
  rescue
    error ->
      Logger.warning("Failed to record duel result: #{inspect(error)}")
  end

  defp generate_duel_id do
    Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end
end
