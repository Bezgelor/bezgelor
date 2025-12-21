defmodule BezgelorWorld.RealmMonitor do
  @moduledoc """
  Monitors realm health and updates online status in the database.

  ## Overview

  The RealmMonitor periodically checks the health of all realms by attempting
  TCP connections. It updates each realm's `online` status in the database.

  On startup, it marks the current realm as online immediately.

  ## Health Checking

  Every 30 seconds (configurable), the monitor:
  1. Fetches all realms from the database
  2. For each realm (except current), attempts a TCP connection
  3. Updates the `online` field based on connection success

  The current realm is always marked online (since we're running on it).

  ## Configuration

      config :bezgelor_world, BezgelorWorld.RealmMonitor,
        check_interval: 30_000,  # 30 seconds
        connect_timeout: 5_000   # 5 seconds

  ## Usage

  Started automatically by BezgelorWorld.Application:

      children = [
        BezgelorWorld.RealmMonitor,
        ...
      ]

  Can also check health on demand:

      BezgelorWorld.RealmMonitor.check_realms()
  """

  use GenServer

  alias BezgelorDb.Realms

  require Logger

  @default_check_interval 30_000
  @default_connect_timeout 5_000

  # Client API

  @doc """
  Start the realm monitor.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Trigger an immediate health check of all realms.
  """
  @spec check_realms() :: :ok
  def check_realms do
    GenServer.cast(__MODULE__, :check_realms)
  end

  @doc """
  Get the current realm ID this server represents.
  """
  @spec current_realm_id() :: integer()
  def current_realm_id do
    Application.get_env(:bezgelor_realm, :realm_id, 1)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    check_interval = Keyword.get(opts, :check_interval, default_check_interval())
    connect_timeout = Keyword.get(opts, :connect_timeout, default_connect_timeout())

    state = %{
      check_interval: check_interval,
      connect_timeout: connect_timeout
    }

    # Mark current realm as online immediately
    mark_current_realm_online()

    # Schedule first check
    schedule_check(check_interval)

    Logger.info("RealmMonitor started, current realm: #{current_realm_id()}")

    {:ok, state}
  end

  @impl true
  def handle_cast(:check_realms, state) do
    do_check_realms(state.connect_timeout)
    {:noreply, state}
  end

  @impl true
  def handle_info(:check_realms, state) do
    do_check_realms(state.connect_timeout)
    schedule_check(state.check_interval)
    {:noreply, state}
  end

  # Private Functions

  defp do_check_realms(connect_timeout) do
    current_id = current_realm_id()
    realms = Realms.list_realms()

    Enum.each(realms, fn realm ->
      if realm.id == current_id do
        # Always mark current realm as online
        ensure_online(realm, true)
      else
        # Check remote realm health
        online = check_realm_health(realm.address, realm.port, connect_timeout)
        update_realm_status(realm, online)
      end
    end)
  end

  defp check_realm_health(address, port, timeout) do
    # Convert address to charlist for :gen_tcp
    host = String.to_charlist(address)

    case :gen_tcp.connect(host, port, [:binary, active: false], timeout) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        true

      {:error, _reason} ->
        false
    end
  end

  defp update_realm_status(realm, online) when realm.online != online do
    case Realms.set_online(realm, online) do
      {:ok, _} ->
        Logger.info(
          "Realm '#{realm.name}' (#{realm.id}) is now #{if online, do: "online", else: "offline"}"
        )

      {:error, reason} ->
        Logger.warning("Failed to update realm '#{realm.name}' status: #{inspect(reason)}")
    end
  end

  defp update_realm_status(_realm, _online), do: :ok

  defp ensure_online(realm, true) when realm.online == true, do: :ok

  defp ensure_online(realm, online) do
    case Realms.set_online(realm, online) do
      {:ok, _} ->
        if online do
          Logger.info("Realm '#{realm.name}' (#{realm.id}) marked online (current realm)")
        end

      {:error, reason} ->
        Logger.warning("Failed to mark realm '#{realm.name}' online: #{inspect(reason)}")
    end
  end

  defp mark_current_realm_online do
    case Realms.get_realm(current_realm_id()) do
      nil ->
        Logger.warning("Current realm #{current_realm_id()} not found in database")

      realm ->
        ensure_online(realm, true)
    end
  end

  defp schedule_check(interval) do
    Process.send_after(self(), :check_realms, interval)
  end

  defp default_check_interval do
    Application.get_env(:bezgelor_world, __MODULE__, [])
    |> Keyword.get(:check_interval, @default_check_interval)
  end

  defp default_connect_timeout do
    Application.get_env(:bezgelor_world, __MODULE__, [])
    |> Keyword.get(:connect_timeout, @default_connect_timeout)
  end
end
