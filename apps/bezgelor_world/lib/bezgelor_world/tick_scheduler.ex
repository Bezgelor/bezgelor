defmodule BezgelorWorld.TickScheduler do
  @moduledoc """
  Zone-wide tick scheduler for coordinated periodic effect processing.

  ## Overview

  WildStar uses a 1-second server tick for all periodic effects. This ensures:
  - All DoTs tick simultaneously
  - All HoTs tick simultaneously
  - Fair timing in PvP (no one's DoT ticks right before another's heal)

  ## Architecture

  The TickScheduler fires every 1000ms and notifies all registered listeners.
  BuffManager.Shard registers as a listener and processes all due periodic
  effects when it receives a tick notification.

  ## Usage

      # Register to receive tick notifications
      TickScheduler.register_listener(self())

      # Handle tick in your GenServer
      def handle_info({:tick, tick_number}, state) do
        # Process periodic effects
        {:noreply, state}
      end
  """

  use GenServer

  require Logger

  # WildStar's 1-second tick
  @default_tick_interval 1000

  ## Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Register a process to receive tick notifications.

  The process will receive `{:tick, tick_number}` messages.
  """
  @spec register_listener(pid()) :: :ok
  def register_listener(pid) do
    GenServer.call(__MODULE__, {:register, pid})
  end

  @doc """
  Unregister a process from tick notifications.
  """
  @spec unregister_listener(pid()) :: :ok
  def unregister_listener(pid) do
    GenServer.call(__MODULE__, {:unregister, pid})
  end

  @doc """
  Get current tick number.
  """
  @spec current_tick() :: non_neg_integer()
  def current_tick do
    GenServer.call(__MODULE__, :current_tick)
  end

  @doc """
  Get the tick interval in milliseconds.
  """
  @spec tick_interval() :: non_neg_integer()
  def tick_interval do
    GenServer.call(__MODULE__, :tick_interval)
  end

  ## Server Callbacks

  @impl true
  def init(opts) do
    tick_interval = Keyword.get(opts, :tick_interval, @default_tick_interval)

    state = %{
      tick_interval: tick_interval,
      tick_number: 0,
      listeners: MapSet.new()
    }

    # Schedule first tick
    Process.send_after(self(), :tick, tick_interval)

    Logger.info("TickScheduler started with #{tick_interval}ms interval")
    {:ok, state}
  end

  @impl true
  def handle_call({:register, pid}, _from, state) do
    # Monitor the process so we can clean up if it dies
    Process.monitor(pid)
    listeners = MapSet.put(state.listeners, pid)
    {:reply, :ok, %{state | listeners: listeners}}
  end

  @impl true
  def handle_call({:unregister, pid}, _from, state) do
    listeners = MapSet.delete(state.listeners, pid)
    {:reply, :ok, %{state | listeners: listeners}}
  end

  @impl true
  def handle_call(:current_tick, _from, state) do
    {:reply, state.tick_number, state}
  end

  @impl true
  def handle_call(:tick_interval, _from, state) do
    {:reply, state.tick_interval, state}
  end

  @impl true
  def handle_info(:tick, state) do
    tick_number = state.tick_number + 1

    # Notify all listeners
    Enum.each(state.listeners, fn pid ->
      send(pid, {:tick, tick_number})
    end)

    # Schedule next tick
    Process.send_after(self(), :tick, state.tick_interval)

    {:noreply, %{state | tick_number: tick_number}}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Clean up dead listener
    listeners = MapSet.delete(state.listeners, pid)
    {:noreply, %{state | listeners: listeners}}
  end
end
