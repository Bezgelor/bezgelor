defmodule BezgelorDev.ReportGeneratorTest do
  use ExUnit.Case, async: true

  alias BezgelorDev.ReportGenerator
  alias BezgelorDev.PacketContext

  defp sample_context do
    %PacketContext{
      connection_id: "conn_test",
      connection_type: :world,
      timestamp: ~U[2024-01-15 12:00:00Z],
      player_id: 123,
      player_name: "TestPlayer",
      player_position: {100.5, 200.5, 300.5},
      player_zone_id: 42,
      player_zone_name: "Thayd",
      session_state: :authenticated,
      in_world: true,
      recent_packets: [
        %{
          direction: :inbound,
          opcode: :client_move,
          opcode_name: "ClientMove",
          size: 24,
          timestamp: ~U[2024-01-15 11:59:58Z],
          time_ago_ms: 2000
        },
        %{
          direction: :outbound,
          opcode: :server_ack,
          opcode_name: "ServerAck",
          size: 8,
          timestamp: ~U[2024-01-15 11:59:55Z],
          time_ago_ms: 5000
        }
      ],
      last_packet_received_at: ~U[2024-01-15 11:59:58Z],
      last_packet_sent_at: ~U[2024-01-15 11:59:55Z]
    }
  end

  defp sample_event(opts \\ []) do
    %{
      type: Keyword.get(opts, :type, :unknown_opcode),
      timestamp: Keyword.get(opts, :timestamp, ~U[2024-01-15 12:00:00Z]),
      opcode: Keyword.get(opts, :opcode, 0x1234),
      opcode_hex: Keyword.get(opts, :opcode_hex, "0x1234"),
      payload: Keyword.get(opts, :payload, <<1, 2, 3, 4, 5, 6, 7, 8>>),
      payload_hex: Keyword.get(opts, :payload_hex, "0102030405060708"),
      error: Keyword.get(opts, :error, nil),
      context: Keyword.get(opts, :context, sample_context()),
      player_commentary: Keyword.get(opts, :player_commentary, "I was opening my inventory"),
      claude_analysis: Keyword.get(opts, :claude_analysis, nil)
    }
  end

  describe "generate_markdown_report/1" do
    test "generates markdown with opcode information" do
      event = sample_event()
      report = ReportGenerator.generate_markdown_report(event)

      assert report =~ "# Unknown Packet Report: 0x1234"
      assert report =~ "**Opcode**: 0x1234"
      assert report =~ "**Size**: 8 bytes"
      assert report =~ "Client → Server"
    end

    test "includes player state context" do
      event = sample_event()
      report = ReportGenerator.generate_markdown_report(event)

      assert report =~ "TestPlayer"
      assert report =~ "Thayd"
      assert report =~ "authenticated"
      assert report =~ "In World**: true"
    end

    test "includes recent packets table" do
      event = sample_event()
      report = ReportGenerator.generate_markdown_report(event)

      assert report =~ "ClientMove"
      assert report =~ "ServerAck"
      assert report =~ "C→S"
      assert report =~ "S→C"
    end

    test "includes player commentary" do
      event = sample_event(player_commentary: "Testing the UI")
      report = ReportGenerator.generate_markdown_report(event)

      assert report =~ "Testing the UI"
    end

    test "handles nil commentary" do
      event = sample_event(player_commentary: nil)
      report = ReportGenerator.generate_markdown_report(event)

      assert report =~ "No description provided"
    end

    test "includes error details when present" do
      event = sample_event(error: {:invalid_data, "bad format"})
      report = ReportGenerator.generate_markdown_report(event)

      assert report =~ "Error Details"
      assert report =~ "invalid_data"
      assert report =~ "bad format"
    end

    test "generates appropriate title for each capture type" do
      unknown = sample_event(type: :unknown_opcode)
      unhandled = sample_event(type: :unhandled_opcode)
      error = sample_event(type: :handler_error)

      assert ReportGenerator.generate_markdown_report(unknown) =~ "Unknown Packet Report"
      assert ReportGenerator.generate_markdown_report(unhandled) =~ "Unhandled Packet Report"
      assert ReportGenerator.generate_markdown_report(error) =~ "Handler Error Report"
    end

    test "includes hex dump of payload" do
      # "Hello"
      payload = <<0x48, 0x65, 0x6C, 0x6C, 0x6F>>
      event = sample_event(payload: payload)
      report = ReportGenerator.generate_markdown_report(event)

      assert report =~ "48 65 6C 6C 6F"
      assert report =~ "|Hello|"
    end

    test "includes base64 encoded payload" do
      payload = <<1, 2, 3, 4>>
      event = sample_event(payload: payload)
      report = ReportGenerator.generate_markdown_report(event)

      assert report =~ Base.encode64(payload)
    end
  end

  describe "generate_json_report/1" do
    test "generates valid JSON" do
      event = sample_event()
      json = ReportGenerator.generate_json_report(event)

      assert {:ok, decoded} = Jason.decode(json)
      assert is_map(decoded)
    end

    test "includes all required fields" do
      event = sample_event()
      json = ReportGenerator.generate_json_report(event)
      {:ok, decoded} = Jason.decode(json)

      assert decoded["type"] == "unknown_opcode"
      assert decoded["timestamp"] =~ "2024-01-15"
      assert decoded["opcode"]["hex"] == "0x1234"
      assert decoded["payload"]["size"] == 8
      assert decoded["player_commentary"] == "I was opening my inventory"
    end

    test "includes context information" do
      event = sample_event()
      json = ReportGenerator.generate_json_report(event)
      {:ok, decoded} = Jason.decode(json)

      context = decoded["context"]
      assert context["connection_type"] == "world"
      assert context["player"]["name"] == "TestPlayer"
      assert context["player"]["zone_name"] == "Thayd"
      assert context["session"]["state"] == "authenticated"
    end

    test "handles error field" do
      event = sample_event(error: {:test_error, "reason"})
      json = ReportGenerator.generate_json_report(event)
      {:ok, decoded} = Jason.decode(json)

      assert decoded["error"] =~ "test_error"
    end

    test "includes base64 payload" do
      payload = <<10, 20, 30>>
      event = sample_event(payload: payload)
      json = ReportGenerator.generate_json_report(event)
      {:ok, decoded} = Jason.decode(json)

      assert decoded["payload"]["base64"] == Base.encode64(payload)
    end
  end

  describe "generate_summary_report/2" do
    test "generates session summary" do
      captures = [
        sample_event(type: :unknown_opcode, opcode: 0x1111, opcode_hex: "0x1111"),
        sample_event(type: :unknown_opcode, opcode: 0x2222, opcode_hex: "0x2222"),
        sample_event(type: :unhandled_opcode, opcode: :known_opcode, opcode_hex: "0x3333"),
        sample_event(
          type: :handler_error,
          opcode: :erroring_opcode,
          opcode_hex: "0x4444",
          error: :some_error
        )
      ]

      state = %{
        session_id: "test_session_123",
        session_start: ~U[2024-01-15 10:00:00Z],
        capture_count: 4
      }

      report = ReportGenerator.generate_summary_report(captures, state)

      assert report =~ "test_session_123"
      assert report =~ "Total Captures**: 4"
      assert report =~ "Captures by Type"
      assert report =~ "Unknown Opcode"
      assert report =~ "Unhandled Opcode"
      assert report =~ "Handler Error"
    end

    test "lists unique unknown opcodes" do
      captures = [
        sample_event(type: :unknown_opcode, opcode: 0x1111, opcode_hex: "0x1111"),
        # duplicate
        sample_event(type: :unknown_opcode, opcode: 0x1111, opcode_hex: "0x1111"),
        sample_event(type: :unknown_opcode, opcode: 0x2222, opcode_hex: "0x2222")
      ]

      state = %{session_id: "test", session_start: DateTime.utc_now(), capture_count: 3}
      report = ReportGenerator.generate_summary_report(captures, state)

      assert report =~ "0x1111"
      assert report =~ "0x2222"
    end

    test "handles empty captures list" do
      state = %{session_id: "empty_session", session_start: DateTime.utc_now(), capture_count: 0}
      report = ReportGenerator.generate_summary_report([], state)

      assert report =~ "empty_session"
      assert report =~ "Total Captures**: 0"
      assert report =~ "None captured"
    end
  end
end
