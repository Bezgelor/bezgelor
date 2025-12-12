defmodule BezgelorDev.PacketContextTest do
  use ExUnit.Case, async: true

  alias BezgelorDev.PacketContext

  describe "from_connection_state/1" do
    test "creates context with default values for empty conn_state" do
      conn_state = %{}
      context = PacketContext.from_connection_state(conn_state)

      assert context.connection_type == :unknown
      assert context.session_state == :unknown
      assert context.player_id == nil
      assert context.player_name == nil
      assert context.player_position == nil
      assert context.player_zone_id == nil
      assert context.player_zone_name == nil
      assert context.in_world == false
      assert context.recent_packets == []
      assert context.last_packet_received_at == nil
      assert context.last_packet_sent_at == nil
      assert is_binary(context.connection_id)
      assert %DateTime{} = context.timestamp
    end

    test "creates context from populated conn_state" do
      conn_state = %{
        connection_type: :world,
        state: :authenticated,
        session_data: %{
          character: %{id: 12345, name: "TestPlayer"},
          zone_id: 100,
          zone_name: "Nexus",
          position: %{x: 1.0, y: 2.0, z: 3.0},
          in_world: true
        }
      }

      context = PacketContext.from_connection_state(conn_state)

      assert context.connection_type == :world
      assert context.session_state == :authenticated
      assert context.player_id == 12345
      assert context.player_name == "TestPlayer"
      assert context.player_zone_id == 100
      assert context.player_zone_name == "Nexus"
      assert context.player_position == {1.0, 2.0, 3.0}
      assert context.in_world == true
    end

    test "handles tuple position format" do
      conn_state = %{
        session_data: %{
          position: {10.5, 20.5, 30.5}
        }
      }

      context = PacketContext.from_connection_state(conn_state)
      assert context.player_position == {10.5, 20.5, 30.5}
    end
  end

  describe "add_packet/4" do
    test "adds inbound packet to context" do
      context = PacketContext.from_connection_state(%{})
      updated = PacketContext.add_packet(context, :inbound, :client_hello, 100)

      assert length(updated.recent_packets) == 1
      assert updated.last_packet_received_at != nil
      assert updated.last_packet_sent_at == nil

      [packet] = updated.recent_packets
      assert packet.direction == :inbound
      assert packet.opcode == :client_hello
      assert packet.size == 100
      assert packet.time_ago_ms == 0
    end

    test "adds outbound packet to context" do
      context = PacketContext.from_connection_state(%{})
      updated = PacketContext.add_packet(context, :outbound, :server_hello, 200)

      assert length(updated.recent_packets) == 1
      assert updated.last_packet_received_at == nil
      assert updated.last_packet_sent_at != nil

      [packet] = updated.recent_packets
      assert packet.direction == :outbound
      assert packet.opcode == :server_hello
      assert packet.size == 200
    end

    test "maintains order with newest first" do
      context = PacketContext.from_connection_state(%{})

      context =
        context
        |> PacketContext.add_packet(:inbound, :first, 10)
        |> PacketContext.add_packet(:inbound, :second, 20)
        |> PacketContext.add_packet(:inbound, :third, 30)

      assert length(context.recent_packets) == 3
      [newest | _rest] = context.recent_packets
      assert newest.opcode == :third
    end

    test "respects packet_history_size limit" do
      original = Application.get_env(:bezgelor_dev, :packet_history_size)

      try do
        Application.put_env(:bezgelor_dev, :packet_history_size, 3)

        context = PacketContext.from_connection_state(%{})

        context =
          Enum.reduce(1..5, context, fn i, ctx ->
            PacketContext.add_packet(ctx, :inbound, :"packet_#{i}", i * 10)
          end)

        # Should only keep the 3 most recent
        assert length(context.recent_packets) == 3

        opcodes = Enum.map(context.recent_packets, & &1.opcode)
        assert opcodes == [:packet_5, :packet_4, :packet_3]
      after
        if original, do: Application.put_env(:bezgelor_dev, :packet_history_size, original)
      end
    end

    test "handles integer opcodes" do
      context = PacketContext.from_connection_state(%{})
      updated = PacketContext.add_packet(context, :inbound, 0x1234, 50)

      [packet] = updated.recent_packets
      assert packet.opcode == 0x1234
      assert packet.opcode_name == "0x1234"
    end
  end

  describe "update_time_deltas/1" do
    test "updates time_ago_ms for all packets" do
      context = PacketContext.from_connection_state(%{})
      context = PacketContext.add_packet(context, :inbound, :test, 10)

      # Small delay to ensure measurable time difference
      Process.sleep(10)

      updated = PacketContext.update_time_deltas(context)

      [packet] = updated.recent_packets
      assert packet.time_ago_ms >= 10
    end
  end

  describe "to_map/1" do
    test "converts context to serializable map" do
      conn_state = %{
        connection_type: :world,
        state: :authenticated,
        session_data: %{
          character: %{id: 1, name: "Test"},
          zone_id: 50,
          in_world: true
        }
      }

      context = PacketContext.from_connection_state(conn_state)
      context = PacketContext.add_packet(context, :inbound, :test_packet, 42)
      map = PacketContext.to_map(context)

      assert is_binary(map.connection_id)
      assert map.connection_type == :world
      assert is_binary(map.timestamp)  # ISO8601 string

      assert map.player.id == 1
      assert map.player.name == "Test"
      assert map.player.zone_id == 50

      assert map.session.state == :authenticated
      assert map.session.in_world == true

      assert length(map.recent_packets) == 1
      [packet_map] = map.recent_packets
      assert packet_map.direction == :inbound
      assert packet_map.size == 42
    end

    test "handles nil player position" do
      context = PacketContext.from_connection_state(%{})
      map = PacketContext.to_map(context)

      assert map.player.position == nil
    end

    test "formats position as map with x, y, z" do
      conn_state = %{
        session_data: %{position: {1.5, 2.5, 3.5}}
      }

      context = PacketContext.from_connection_state(conn_state)
      map = PacketContext.to_map(context)

      assert map.player.position == %{x: 1.5, y: 2.5, z: 3.5}
    end
  end
end
