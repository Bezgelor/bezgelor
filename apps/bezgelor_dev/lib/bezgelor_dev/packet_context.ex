defmodule BezgelorDev.PacketContext do
  @moduledoc """
  Rich context captured alongside unknown/unhandled packets.

  This struct contains all available information about the game state
  when a packet event occurs, enabling better analysis and reverse
  engineering of the protocol.
  """

  @type packet_record :: %{
          direction: :inbound | :outbound,
          opcode: atom() | integer(),
          opcode_name: String.t(),
          size: integer(),
          timestamp: DateTime.t(),
          time_ago_ms: integer()
        }

  @type t :: %__MODULE__{
          connection_id: String.t(),
          connection_type: :auth | :realm | :world,
          timestamp: DateTime.t(),
          player_id: integer() | nil,
          player_name: String.t() | nil,
          player_position: {float(), float(), float()} | nil,
          player_zone_id: integer() | nil,
          player_zone_name: String.t() | nil,
          session_state: atom(),
          in_world: boolean(),
          recent_packets: [packet_record()],
          last_packet_received_at: DateTime.t() | nil,
          last_packet_sent_at: DateTime.t() | nil
        }

  defstruct [
    :connection_id,
    :connection_type,
    :timestamp,
    :player_id,
    :player_name,
    :player_position,
    :player_zone_id,
    :player_zone_name,
    :session_state,
    :in_world,
    :recent_packets,
    :last_packet_received_at,
    :last_packet_sent_at
  ]

  @doc """
  Creates a new PacketContext from connection state.
  """
  @spec from_connection_state(map()) :: t()
  def from_connection_state(conn_state) do
    session_data = Map.get(conn_state, :session_data, %{})

    %__MODULE__{
      connection_id: generate_connection_id(conn_state),
      connection_type: Map.get(conn_state, :connection_type, :unknown),
      timestamp: DateTime.utc_now(),
      player_id: get_in(session_data, [:character, :id]),
      player_name: get_in(session_data, [:character, :name]),
      player_position: extract_position(session_data),
      player_zone_id: get_in(session_data, [:zone_id]),
      player_zone_name: get_in(session_data, [:zone_name]),
      session_state: Map.get(conn_state, :state, :unknown),
      in_world: Map.get(session_data, :in_world, false),
      recent_packets: [],
      last_packet_received_at: nil,
      last_packet_sent_at: nil
    }
  end

  @doc """
  Adds a packet record to the context's recent packets list.
  """
  @spec add_packet(t(), :inbound | :outbound, atom() | integer(), integer()) :: t()
  def add_packet(%__MODULE__{} = context, direction, opcode, size) do
    now = DateTime.utc_now()

    record = %{
      direction: direction,
      opcode: opcode,
      opcode_name: format_opcode_name(opcode),
      size: size,
      timestamp: now,
      time_ago_ms: 0
    }

    # Update last packet timestamps
    context =
      case direction do
        :inbound -> %{context | last_packet_received_at: now}
        :outbound -> %{context | last_packet_sent_at: now}
      end

    # Add to recent packets, keeping only the configured limit
    max_packets = BezgelorDev.packet_history_size()
    recent = [record | context.recent_packets] |> Enum.take(max_packets)

    %{context | recent_packets: recent}
  end

  @doc """
  Updates time_ago_ms for all recent packets relative to current time.
  """
  @spec update_time_deltas(t()) :: t()
  def update_time_deltas(%__MODULE__{} = context) do
    now = DateTime.utc_now()

    updated_packets =
      Enum.map(context.recent_packets, fn packet ->
        time_ago = DateTime.diff(now, packet.timestamp, :millisecond)
        %{packet | time_ago_ms: time_ago}
      end)

    %{context | recent_packets: updated_packets}
  end

  @doc """
  Serializes the context to a map for JSON encoding.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = context) do
    %{
      connection_id: context.connection_id,
      connection_type: context.connection_type,
      timestamp: DateTime.to_iso8601(context.timestamp),
      player: %{
        id: context.player_id,
        name: context.player_name,
        position: format_position(context.player_position),
        zone_id: context.player_zone_id,
        zone_name: context.player_zone_name
      },
      session: %{
        state: context.session_state,
        in_world: context.in_world
      },
      recent_packets: Enum.map(context.recent_packets, &packet_to_map/1),
      last_packet_received_at: format_datetime(context.last_packet_received_at),
      last_packet_sent_at: format_datetime(context.last_packet_sent_at)
    }
  end

  # Private functions

  defp generate_connection_id(conn_state) do
    socket = Map.get(conn_state, :socket)
    port_info = if socket, do: inspect(socket), else: "unknown"
    hash = :erlang.phash2({port_info, System.monotonic_time()}, 0xFFFF)
    "conn_#{Integer.to_string(hash, 16)}"
  end

  defp extract_position(session_data) do
    case get_in(session_data, [:position]) do
      %{x: x, y: y, z: z} -> {x, y, z}
      {x, y, z} -> {x, y, z}
      _ -> nil
    end
  end

  defp format_opcode_name(opcode) when is_atom(opcode) do
    # Try to get human-readable name from Opcode module
    try do
      BezgelorProtocol.Opcode.name(opcode)
    rescue
      _ -> Atom.to_string(opcode)
    end
  end

  defp format_opcode_name(opcode) when is_integer(opcode) do
    "0x#{Integer.to_string(opcode, 16)}"
  end

  defp format_position(nil), do: nil
  defp format_position({x, y, z}), do: %{x: x, y: y, z: z}

  defp format_datetime(nil), do: nil
  defp format_datetime(dt), do: DateTime.to_iso8601(dt)

  defp packet_to_map(packet) do
    %{
      direction: packet.direction,
      opcode: format_opcode_for_json(packet.opcode),
      opcode_name: packet.opcode_name,
      size: packet.size,
      timestamp: DateTime.to_iso8601(packet.timestamp),
      time_ago_ms: packet.time_ago_ms
    }
  end

  defp format_opcode_for_json(opcode) when is_atom(opcode), do: Atom.to_string(opcode)
  defp format_opcode_for_json(opcode) when is_integer(opcode), do: opcode
end
