defmodule BezgelorWorld.HousingManager do
  @moduledoc """
  Manages active housing instances.

  ## Overview

  The HousingManager tracks:
  - Active housing instances (lazily loaded on entry)
  - Players currently in each plot
  - Grace period before unloading empty plots

  ## State Structure

      %{
        instances: %{
          plot_id => %{
            plot: HousingPlot,
            players: MapSet.t(character_id),
            unload_timer: reference() | nil
          }
        },
        player_locations: %{
          character_id => plot_id
        }
      }
  """

  use GenServer

  alias BezgelorDb.Housing

  alias BezgelorProtocol.Packets.World.{
    ServerHousingEnter,
    ServerHousingData,
    ServerHousingDecorList,
    ServerHousingFabkitList,
    ServerHousingNeighborList
  }

  require Logger

  # Grace period before unloading empty plot (5 minutes)
  @unload_grace_ms 300_000

  @type instance :: %{
          plot: map(),
          players: MapSet.t(),
          unload_timer: reference() | nil
        }

  @type state :: %{
          instances: %{non_neg_integer() => instance()},
          player_locations: %{non_neg_integer() => non_neg_integer()}
        }

  ## Client API

  @doc "Start the HousingManager."
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Request entry to a housing plot.

  Returns `{:ok, packets}` on success with packets to send to client,
  or `{:error, reason}` on failure.
  """
  @spec enter_plot(non_neg_integer(), non_neg_integer()) ::
          {:ok, [struct()]} | {:error, :not_found | :denied}
  def enter_plot(character_id, plot_id) do
    GenServer.call(__MODULE__, {:enter_plot, character_id, plot_id})
  end

  @doc """
  Request entry to own housing plot (by character owner).

  Returns `{:ok, packets}` or `{:error, reason}`.
  """
  @spec enter_own_plot(non_neg_integer()) ::
          {:ok, [struct()]} | {:error, :not_found | :denied}
  def enter_own_plot(character_id) do
    GenServer.call(__MODULE__, {:enter_own_plot, character_id})
  end

  @doc """
  Exit current housing plot.
  """
  @spec exit_plot(non_neg_integer()) :: :ok
  def exit_plot(character_id) do
    GenServer.cast(__MODULE__, {:exit_plot, character_id})
  end

  @doc """
  Get the plot ID a character is currently in, or nil.
  """
  @spec get_player_location(non_neg_integer()) :: non_neg_integer() | nil
  def get_player_location(character_id) do
    GenServer.call(__MODULE__, {:get_player_location, character_id})
  end

  @doc """
  Get all players currently in a plot.
  """
  @spec get_players_in_plot(non_neg_integer()) :: [non_neg_integer()]
  def get_players_in_plot(plot_id) do
    GenServer.call(__MODULE__, {:get_players_in_plot, plot_id})
  end

  @doc """
  Broadcast a packet to all players in a plot.
  """
  @spec broadcast_to_plot(non_neg_integer(), struct()) :: :ok
  def broadcast_to_plot(plot_id, packet) do
    GenServer.cast(__MODULE__, {:broadcast, plot_id, packet})
  end

  ## Server Callbacks

  @impl true
  def init(_opts) do
    Logger.info("HousingManager started")
    {:ok, %{instances: %{}, player_locations: %{}}}
  end

  @impl true
  def handle_call({:enter_plot, character_id, plot_id}, _from, state) do
    case load_or_get_instance(plot_id, state) do
      {:ok, instance, state} ->
        # Check permission
        if Housing.can_visit?(plot_id, character_id) do
          {packets, state} = add_player_to_plot(character_id, plot_id, instance, state)
          {:reply, {:ok, packets}, state}
        else
          {:reply, {:error, :denied}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:enter_own_plot, character_id}, _from, state) do
    case Housing.get_plot(character_id) do
      {:ok, plot} ->
        case load_or_get_instance(plot.id, state) do
          {:ok, instance, state} ->
            {packets, state} = add_player_to_plot(character_id, plot.id, instance, state)
            {:reply, {:ok, packets}, state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      :error ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:get_player_location, character_id}, _from, state) do
    {:reply, Map.get(state.player_locations, character_id), state}
  end

  @impl true
  def handle_call({:get_players_in_plot, plot_id}, _from, state) do
    case Map.get(state.instances, plot_id) do
      nil -> {:reply, [], state}
      instance -> {:reply, MapSet.to_list(instance.players), state}
    end
  end

  @impl true
  def handle_cast({:exit_plot, character_id}, state) do
    state = remove_player_from_plot(character_id, state)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:broadcast, plot_id, packet}, state) do
    case Map.get(state.instances, plot_id) do
      nil ->
        {:noreply, state}

      instance ->
        # Broadcast to all players in the plot
        for player_id <- instance.players do
          send_to_player(player_id, packet)
        end

        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:unload_plot, plot_id}, state) do
    case Map.get(state.instances, plot_id) do
      nil ->
        {:noreply, state}

      instance ->
        if MapSet.size(instance.players) == 0 do
          Logger.info("Unloading empty housing plot #{plot_id}")
          state = %{state | instances: Map.delete(state.instances, plot_id)}
          {:noreply, state}
        else
          # Players joined during grace period, don't unload
          {:noreply, state}
        end
    end
  end

  ## Private Functions

  defp load_or_get_instance(plot_id, state) do
    case Map.get(state.instances, plot_id) do
      nil ->
        # Load from database
        case Housing.get_plot_by_id(plot_id) do
          {:ok, plot} ->
            instance = %{
              plot: plot,
              players: MapSet.new(),
              unload_timer: nil
            }

            state = %{state | instances: Map.put(state.instances, plot_id, instance)}
            Logger.info("Loaded housing plot #{plot_id} for character #{plot.character_id}")
            {:ok, instance, state}

          :error ->
            {:error, :not_found}
        end

      instance ->
        # Cancel unload timer if pending
        state =
          if instance.unload_timer do
            Process.cancel_timer(instance.unload_timer)
            instance = %{instance | unload_timer: nil}
            %{state | instances: Map.put(state.instances, plot_id, instance)}
          else
            state
          end

        {:ok, instance, state}
    end
  end

  defp add_player_to_plot(character_id, plot_id, instance, state) do
    # Remove from previous plot if any
    state = remove_player_from_plot(character_id, state)

    # Add to new plot
    instance = %{instance | players: MapSet.put(instance.players, character_id)}
    state = %{state | instances: Map.put(state.instances, plot_id, instance)}
    state = %{state | player_locations: Map.put(state.player_locations, character_id, plot_id)}

    # Build entry packets
    plot = instance.plot

    packets = [
      ServerHousingEnter.success(plot_id, plot.character_id),
      ServerHousingData.from_plot(plot),
      ServerHousingDecorList.from_decor_list(plot_id, plot.decor || []),
      ServerHousingFabkitList.from_fabkit_list(plot_id, plot.fabkits || []),
      ServerHousingNeighborList.from_neighbor_list(plot_id, plot.neighbors || [])
    ]

    Logger.debug("Character #{character_id} entered housing plot #{plot_id}")

    {packets, state}
  end

  defp remove_player_from_plot(character_id, state) do
    case Map.get(state.player_locations, character_id) do
      nil ->
        state

      plot_id ->
        state = %{state | player_locations: Map.delete(state.player_locations, character_id)}

        case Map.get(state.instances, plot_id) do
          nil ->
            state

          instance ->
            instance = %{instance | players: MapSet.delete(instance.players, character_id)}

            # Start unload timer if empty
            instance =
              if MapSet.size(instance.players) == 0 do
                timer_ref = Process.send_after(self(), {:unload_plot, plot_id}, @unload_grace_ms)
                %{instance | unload_timer: timer_ref}
              else
                instance
              end

            %{state | instances: Map.put(state.instances, plot_id, instance)}
        end
    end
  end

  defp send_to_player(character_id, packet) do
    # TODO: Route through session manager to find socket and send packet
    Logger.debug("Would send packet to character #{character_id}: #{inspect(packet.__struct__)}")
  end
end
