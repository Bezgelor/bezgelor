defmodule BezgelorPortal.TelemetryCollector do
  @moduledoc """
  A GenServer that collects telemetry events and buffers them for batch insertion.

  Attaches to configured telemetry events and stores them in memory.
  Periodically flushes the buffer to the database every 5 seconds (configurable).
  Also flushes immediately when the buffer reaches max size (1000 events).

  ## Configuration

  Configure in config/config.exs:

      config :bezgelor_portal, BezgelorPortal.TelemetryCollector,
        flush_interval: 5_000,
        max_buffer_size: 1000,
        tracked_events: [
          "bezgelor.auth.login_complete",
          "bezgelor.auth.login_failed",
          "bezgelor.character.created",
          "bezgelor.character.deleted",
          "bezgelor.quest.accepted",
          "bezgelor.quest.completed",
          "bezgelor.quest.abandoned",
          "bezgelor.creature.killed",
          "bezgelor.spell.cast",
          "bezgelor.guild.created",
          "bezgelor.guild.disbanded",
          "bezgelor.world.zone_entered"
        ]

  ## Metadata Sanitization

  Only whitelisted metadata keys are stored to prevent PII exposure:
  - :account_id
  - :character_id
  - :zone_id
  - :success
  - :creature_id
  - :quest_id
  - :item_id
  - :spell_id
  - :guild_id
  - :world_id

  All other metadata keys are filtered out.
  """

  use GenServer
  require Logger

  @default_config [
    flush_interval: 5_000,
    max_buffer_size: 1000,
    tracked_events: [
      "bezgelor.auth.login_complete",
      "bezgelor.auth.login_failed",
      "bezgelor.character.created",
      "bezgelor.character.deleted",
      "bezgelor.quest.accepted",
      "bezgelor.quest.completed",
      "bezgelor.quest.abandoned",
      "bezgelor.creature.killed",
      "bezgelor.spell.cast",
      "bezgelor.guild.created",
      "bezgelor.guild.disbanded",
      "bezgelor.world.zone_entered"
    ]
  ]

  @allowed_metadata_keys [
    :account_id,
    :character_id,
    :zone_id,
    :success,
    :creature_id,
    :quest_id,
    :item_id,
    :spell_id,
    :guild_id,
    :world_id
  ]

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get the current buffer size (for testing).
  """
  def buffer_size do
    GenServer.call(__MODULE__, :buffer_size)
  end

  @doc """
  Force flush the buffer immediately (for testing).
  """
  def flush do
    GenServer.call(__MODULE__, :flush)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    config = Application.get_env(:bezgelor_portal, __MODULE__, [])
    config = Keyword.merge(@default_config, config)

    flush_interval = Keyword.get(config, :flush_interval)
    max_buffer_size = Keyword.get(config, :max_buffer_size)
    tracked_events = Keyword.get(config, :tracked_events)

    # Attach to each tracked event
    handler_ids =
      Enum.map(tracked_events, fn event_name ->
        handler_id = {__MODULE__, event_name, make_ref()}

        :telemetry.attach(
          handler_id,
          parse_event_name(event_name),
          &__MODULE__.handle_event/4,
          %{collector: self()}
        )

        handler_id
      end)

    # Schedule first flush
    schedule_flush(flush_interval)

    Logger.info("TelemetryCollector started - tracking #{length(tracked_events)} events")

    {:ok,
     %{
       buffer: [],
       handler_ids: handler_ids,
       flush_interval: flush_interval,
       max_buffer_size: max_buffer_size
     }}
  end

  @impl true
  def terminate(_reason, state) do
    # Flush remaining events
    flush_buffer(state.buffer)

    # Detach all handlers to prevent leaks
    Enum.each(state.handler_ids, fn handler_id ->
      :telemetry.detach(handler_id)
    end)

    :ok
  end

  @impl true
  def handle_call(:buffer_size, _from, state) do
    {:reply, length(state.buffer), state}
  end

  @impl true
  def handle_call(:flush, _from, state) do
    count = flush_buffer(state.buffer)
    {:reply, {:ok, count}, %{state | buffer: []}}
  end

  @impl true
  def handle_cast({:add_event, event}, state) do
    new_buffer = [event | state.buffer]

    # Check if buffer reached max size
    if length(new_buffer) >= state.max_buffer_size do
      flush_buffer(new_buffer)
      {:noreply, %{state | buffer: []}}
    else
      {:noreply, %{state | buffer: new_buffer}}
    end
  end

  @impl true
  def handle_info(:flush, state) do
    # Flush current buffer
    flush_buffer(state.buffer)

    # Schedule next flush
    schedule_flush(state.flush_interval)

    {:noreply, %{state | buffer: []}}
  end

  # Telemetry Handler

  @doc false
  def handle_event(event_name, measurements, metadata, config) do
    collector = Map.get(config, :collector)

    if collector && Process.alive?(collector) do
      event = %{
        event_name: format_event_name(event_name),
        measurements: measurements,
        metadata: sanitize_metadata(metadata),
        occurred_at: DateTime.utc_now()
      }

      GenServer.cast(collector, {:add_event, event})
    end
  end

  # Private Functions

  defp schedule_flush(interval) do
    Process.send_after(self(), :flush, interval)
  end

  defp flush_buffer([]), do: 0

  defp flush_buffer(events) do
    {:ok, count} = BezgelorDb.Metrics.insert_events(events)
    Logger.debug("Flushed #{count} telemetry events to database")
    count
  end

  defp parse_event_name(name) when is_binary(name) do
    name
    |> String.split(".")
    |> Enum.map(&String.to_atom/1)
  end

  defp format_event_name(event_name) when is_list(event_name) do
    event_name
    |> Enum.map(&to_string/1)
    |> Enum.join(".")
  end

  defp sanitize_metadata(metadata) when is_map(metadata) do
    metadata
    |> Enum.filter(fn {key, _value} ->
      is_allowed_key?(key)
    end)
    |> Enum.into(%{}, fn {key, value} ->
      # Normalize to atom keys
      atom_key = normalize_key(key)
      {atom_key, value}
    end)
  end

  defp is_allowed_key?(key) do
    try do
      atom_key = if is_atom(key), do: key, else: String.to_existing_atom(key)
      atom_key in @allowed_metadata_keys
    rescue
      ArgumentError -> false
    end
  end

  defp normalize_key(key) do
    if is_atom(key), do: key, else: String.to_existing_atom(key)
  end
end
