defmodule BezgelorDev.DevCapture do
  @compile {:no_warn_undefined, BezgelorProtocol.Opcode}
  @moduledoc """
  GenServer for capturing and managing unknown/unhandled packet events.

  This is the central coordinator for the development capture system.
  It maintains packet history per connection, captures events, and
  routes them to the appropriate handler (logging or interactive).

  ## Architecture

  - Maintains a map of connection_id -> PacketContext
  - Captures events are processed based on current mode
  - In `:logging` mode, writes to files immediately
  - In `:interactive` mode, pauses and prompts for player input
  """

  use GenServer
  require Logger

  alias BezgelorDev.PacketContext
  alias BezgelorDev.InteractivePrompt
  alias BezgelorDev.ReportGenerator

  @type capture_type :: :unknown_opcode | :unhandled_opcode | :handler_error

  @type capture_event :: %{
          type: capture_type(),
          timestamp: DateTime.t(),
          opcode: integer() | atom(),
          opcode_hex: String.t(),
          payload: binary(),
          payload_hex: String.t(),
          error: term() | nil,
          context: PacketContext.t(),
          player_commentary: String.t() | nil,
          llm_analysis: map() | nil
        }

  defstruct [
    :session_id,
    :session_start,
    :capture_count,
    contexts: %{},
    captures: []
  ]

  # Client API

  @doc """
  Starts the DevCapture GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Captures an unknown opcode event (opcode not defined in Opcode module).
  """
  @spec capture_unknown_opcode(integer(), binary(), map()) :: :ok
  def capture_unknown_opcode(opcode_int, payload, conn_state) do
    GenServer.cast(__MODULE__, {:capture, :unknown_opcode, opcode_int, payload, nil, conn_state})
  end

  @doc """
  Captures an unhandled opcode event (opcode known but no handler).
  """
  @spec capture_unhandled_opcode(atom(), binary(), map()) :: :ok
  def capture_unhandled_opcode(opcode_atom, payload, conn_state) do
    GenServer.cast(
      __MODULE__,
      {:capture, :unhandled_opcode, opcode_atom, payload, nil, conn_state}
    )
  end

  @doc """
  Captures a handler error event.
  """
  @spec capture_handler_error(atom(), binary(), term(), map()) :: :ok
  def capture_handler_error(opcode_atom, payload, error, conn_state) do
    GenServer.cast(
      __MODULE__,
      {:capture, :handler_error, opcode_atom, payload, error, conn_state}
    )
  end

  @doc """
  Tracks a packet for context history.
  """
  @spec track_packet(:inbound | :outbound, atom() | integer(), binary(), map()) :: :ok
  def track_packet(direction, opcode, payload, conn_state) do
    GenServer.cast(__MODULE__, {:track_packet, direction, opcode, byte_size(payload), conn_state})
  end

  @doc """
  Gets the recent packets for a connection.
  """
  @spec get_recent_packets(String.t(), pos_integer()) :: [PacketContext.packet_record()]
  def get_recent_packets(connection_id, count \\ 20) do
    GenServer.call(__MODULE__, {:get_recent_packets, connection_id, count})
  end

  @doc """
  Gets all pending captures that haven't been analyzed.
  """
  @spec get_pending_captures() :: [capture_event()]
  def get_pending_captures do
    GenServer.call(__MODULE__, :get_pending_captures)
  end

  @doc """
  Exports all captures to files.
  """
  @spec export_captures(atom()) :: {:ok, String.t()} | {:error, term()}
  def export_captures(format \\ :markdown) do
    GenServer.call(__MODULE__, {:export_captures, format})
  end

  @doc """
  Gets session statistics.
  """
  @spec get_stats() :: map()
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    session_id = generate_session_id()
    Logger.info("DevCapture started - Session: #{session_id}")

    state = %__MODULE__{
      session_id: session_id,
      session_start: DateTime.utc_now(),
      capture_count: 0,
      contexts: %{},
      captures: []
    }

    # Ensure capture directory exists
    ensure_capture_directory(session_id)

    {:ok, state}
  end

  @impl true
  def handle_cast({:capture, type, opcode, payload, error, conn_state}, state) do
    # Get or create context for this connection
    connection_id = get_connection_id(conn_state)
    context = get_or_create_context(state, connection_id, conn_state)
    context = PacketContext.update_time_deltas(context)

    # Build capture event
    event = build_capture_event(type, opcode, payload, error, context)

    # Process based on mode
    {event, state} = process_capture(event, state)

    # Update state
    state = %{state | capture_count: state.capture_count + 1, captures: [event | state.captures]}

    {:noreply, state}
  end

  @impl true
  def handle_cast({:track_packet, direction, opcode, size, conn_state}, state) do
    connection_id = get_connection_id(conn_state)
    context = get_or_create_context(state, connection_id, conn_state)
    context = PacketContext.add_packet(context, direction, opcode, size)

    state = put_in(state.contexts[connection_id], context)
    {:noreply, state}
  end

  @impl true
  def handle_call({:get_recent_packets, connection_id, count}, _from, state) do
    packets =
      case Map.get(state.contexts, connection_id) do
        nil -> []
        context -> Enum.take(context.recent_packets, count)
      end

    {:reply, packets, state}
  end

  @impl true
  def handle_call(:get_pending_captures, _from, state) do
    pending = Enum.filter(state.captures, fn c -> is_nil(c.llm_analysis) end)
    {:reply, pending, state}
  end

  @impl true
  def handle_call({:export_captures, format}, _from, state) do
    result = do_export_captures(state, format)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      session_id: state.session_id,
      session_start: DateTime.to_iso8601(state.session_start),
      capture_count: state.capture_count,
      active_connections: map_size(state.contexts),
      captures_by_type: count_by_type(state.captures)
    }

    {:reply, stats, state}
  end

  # Private Functions

  defp generate_session_id do
    now = DateTime.utc_now()
    date_part = Calendar.strftime(now, "%Y-%m-%d_%H-%M-%S")
    random_part = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "#{date_part}_#{random_part}"
  end

  defp ensure_capture_directory(session_id) do
    base_dir = BezgelorDev.capture_directory()
    session_dir = Path.join([base_dir, "sessions", session_id])

    File.mkdir_p!(Path.join(session_dir, "captures"))
    File.mkdir_p!(Path.join(session_dir, "generated_stubs"))

    # Write session info
    session_info = %{
      session_id: session_id,
      started_at: DateTime.to_iso8601(DateTime.utc_now()),
      mode: BezgelorDev.mode(),
      interactive_mode: BezgelorDev.interactive_mode()
    }

    info_path = Path.join(session_dir, "session_info.json")
    File.write!(info_path, Jason.encode!(session_info, pretty: true))
  end

  defp get_connection_id(conn_state) do
    # Generate a consistent ID for this connection
    socket = Map.get(conn_state, :socket)
    port_info = if socket, do: :erlang.phash2(socket, 0xFFFF), else: 0
    "conn_#{Integer.to_string(port_info, 16)}"
  end

  defp get_or_create_context(state, connection_id, conn_state) do
    case Map.get(state.contexts, connection_id) do
      nil -> PacketContext.from_connection_state(conn_state)
      context -> context
    end
  end

  defp build_capture_event(type, opcode, payload, error, context) do
    opcode_hex = format_opcode_hex(opcode)

    %{
      type: type,
      timestamp: DateTime.utc_now(),
      opcode: opcode,
      opcode_hex: opcode_hex,
      payload: payload,
      payload_hex: Base.encode16(payload, case: :lower),
      error: error,
      context: context,
      player_commentary: nil,
      llm_analysis: nil
    }
  end

  defp format_opcode_hex(opcode) when is_integer(opcode) do
    "0x#{Integer.to_string(opcode, 16) |> String.pad_leading(4, "0")}"
  end

  defp format_opcode_hex(opcode) when is_atom(opcode) do
    try do
      int_val = BezgelorProtocol.Opcode.to_integer(opcode)
      "0x#{Integer.to_string(int_val, 16) |> String.pad_leading(4, "0")}"
    rescue
      _ -> Atom.to_string(opcode)
    end
  end

  defp process_capture(event, state) do
    case BezgelorDev.mode() do
      :logging ->
        # Just save to file
        save_capture_to_file(event, state)
        {event, state}

      :interactive ->
        # Prompt for context and optionally analyze
        process_interactive_capture(event, state)

      _ ->
        {event, state}
    end
  end

  defp process_interactive_capture(event, state) do
    # Get player commentary via interactive prompt
    {commentary, action} = InteractivePrompt.prompt_for_context(event)

    event = %{event | player_commentary: commentary}

    case action do
      :log ->
        # Save to file for later Claude Code analysis
        path = save_capture_to_file(event, state)
        InteractivePrompt.display_save_confirmation(path)
        {event, state}

      :skip ->
        # Don't save, just continue
        {event, state}

      :quit ->
        # User wants to disable dev mode
        Logger.info("Dev capture mode disabled by user")
        Application.put_env(:bezgelor_dev, :mode, :disabled)
        {event, state}
    end
  end

  defp save_capture_to_file(event, state) do
    base_dir = BezgelorDev.capture_directory()
    session_dir = Path.join([base_dir, "sessions", state.session_id, "captures"])

    # Generate filename
    count = state.capture_count + 1
    count_str = String.pad_leading(Integer.to_string(count), 3, "0")
    opcode_str = String.replace(event.opcode_hex, "0x", "")
    type_str = Atom.to_string(event.type)

    base_name = "#{count_str}_#{opcode_str}_#{type_str}"

    # Write markdown report
    md_path = Path.join(session_dir, "#{base_name}.md")
    md_content = ReportGenerator.generate_markdown_report(event)
    File.write!(md_path, md_content)

    # Write JSON for programmatic access
    json_path = Path.join(session_dir, "#{base_name}.json")
    json_content = ReportGenerator.generate_json_report(event)
    File.write!(json_path, json_content)

    # Also generate LLM analysis prompt
    prompt_path = Path.join(session_dir, "#{base_name}_prompt.md")
    prompt_content = BezgelorDev.LlmAssistant.generate_analysis_prompt(event)
    File.write!(prompt_path, prompt_content)

    Logger.debug("Saved capture to #{md_path}")

    # Return the prompt path for display
    prompt_path
  end

  defp do_export_captures(state, format) do
    base_dir = BezgelorDev.capture_directory()
    reports_dir = Path.join(base_dir, "reports")
    File.mkdir_p!(reports_dir)

    date_str = Calendar.strftime(DateTime.utc_now(), "%Y-%m-%d")
    filename = "summary_#{date_str}_#{state.session_id}"

    case format do
      :markdown ->
        path = Path.join(reports_dir, "#{filename}.md")
        content = ReportGenerator.generate_summary_report(state.captures, state)
        File.write!(path, content)
        {:ok, path}

      :json ->
        path = Path.join(reports_dir, "#{filename}.json")
        content = Jason.encode!(Enum.map(state.captures, &capture_to_json/1), pretty: true)
        File.write!(path, content)
        {:ok, path}

      _ ->
        {:error, :unsupported_format}
    end
  end

  defp capture_to_json(event) do
    %{
      type: event.type,
      timestamp: DateTime.to_iso8601(event.timestamp),
      opcode: event.opcode,
      opcode_hex: event.opcode_hex,
      payload_hex: event.payload_hex,
      payload_base64: Base.encode64(event.payload),
      error: if(event.error, do: inspect(event.error), else: nil),
      context: PacketContext.to_map(event.context),
      player_commentary: event.player_commentary,
      llm_analysis: event.llm_analysis
    }
  end

  defp count_by_type(captures) do
    captures
    |> Enum.group_by(& &1.type)
    |> Enum.map(fn {type, items} -> {type, length(items)} end)
    |> Enum.into(%{})
  end
end
