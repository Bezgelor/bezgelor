defmodule BezgelorDev.LlmAssistantTest do
  use ExUnit.Case, async: true

  alias BezgelorDev.LlmAssistant
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
        }
      ],
      last_packet_received_at: ~U[2024-01-15 11:59:58Z],
      last_packet_sent_at: nil
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
      player_commentary: Keyword.get(opts, :player_commentary, "Opening my bag"),
      llm_analysis: Keyword.get(opts, :llm_analysis, nil)
    }
  end

  describe "generate_analysis_prompt/1" do
    test "generates prompt with opcode information" do
      event = sample_event()
      prompt = LlmAssistant.generate_analysis_prompt(event)

      assert prompt =~ "WildStar Packet Analysis Request"
      assert prompt =~ "0x1234"
      assert prompt =~ "8 bytes"
      assert prompt =~ "Client → Server"
    end

    test "includes Bezgelor context in prompt" do
      event = sample_event()
      prompt = LlmAssistant.generate_analysis_prompt(event)

      assert prompt =~ "Bezgelor"
      assert prompt =~ "Elixir WildStar server emulator"
      assert prompt =~ "NexusForever"
    end

    test "includes player state context" do
      event = sample_event()
      prompt = LlmAssistant.generate_analysis_prompt(event)

      assert prompt =~ "TestPlayer"
      assert prompt =~ "Thayd"
      assert prompt =~ "authenticated"
      assert prompt =~ "In World**: true"
    end

    test "includes recent packets table" do
      event = sample_event()
      prompt = LlmAssistant.generate_analysis_prompt(event)

      assert prompt =~ "ClientMove"
      assert prompt =~ "2000ms"
    end

    test "includes player commentary" do
      event = sample_event(player_commentary: "I clicked on an NPC")
      prompt = LlmAssistant.generate_analysis_prompt(event)

      assert prompt =~ "I clicked on an NPC"
    end

    test "handles nil commentary" do
      event = sample_event(player_commentary: nil)
      prompt = LlmAssistant.generate_analysis_prompt(event)

      assert prompt =~ "No description provided during capture"
    end

    test "includes hex dump of payload" do
      # "Hello"
      payload = <<0x48, 0x65, 0x6C, 0x6C, 0x6F>>
      event = sample_event(payload: payload)
      prompt = LlmAssistant.generate_analysis_prompt(event)

      assert prompt =~ "48 65 6C 6C 6F"
    end

    test "includes base64 encoded payload" do
      payload = <<1, 2, 3, 4>>
      event = sample_event(payload: payload)
      prompt = LlmAssistant.generate_analysis_prompt(event)

      assert prompt =~ Base.encode64(payload)
    end

    test "requests implementation guidance" do
      event = sample_event()
      prompt = LlmAssistant.generate_analysis_prompt(event)

      assert prompt =~ "Suggest an opcode name"
      assert prompt =~ "Analyze the byte structure"
      assert prompt =~ "Generate Elixir code"
      assert prompt =~ "Reference NexusForever"
    end

    test "includes codebase structure information" do
      event = sample_event()
      prompt = LlmAssistant.generate_analysis_prompt(event)

      assert prompt =~ "bezgelor_protocol/lib/bezgelor_protocol/opcode.ex"
      assert prompt =~ "bezgelor_protocol/lib/bezgelor_protocol/packets/"
      assert prompt =~ "bezgelor_protocol/lib/bezgelor_protocol/handler/"
      assert prompt =~ "Readable"
      assert prompt =~ "Handler"
    end

    test "handles empty recent packets" do
      context = %{sample_context() | recent_packets: []}
      event = sample_event(context: context)
      prompt = LlmAssistant.generate_analysis_prompt(event)

      assert prompt =~ "No recent packets recorded"
    end

    test "handles nil position" do
      context = %{sample_context() | player_position: nil}
      event = sample_event(context: context)
      prompt = LlmAssistant.generate_analysis_prompt(event)

      assert prompt =~ "Position**: Unknown"
    end
  end

  describe "generate_batch_prompt/1" do
    test "generates batch prompt for multiple events" do
      events = [
        sample_event(opcode: 0x1111, opcode_hex: "0x1111"),
        sample_event(opcode: 0x2222, opcode_hex: "0x2222"),
        sample_event(opcode: 0x3333, opcode_hex: "0x3333")
      ]

      prompt = LlmAssistant.generate_batch_prompt(events)

      assert prompt =~ "Batch WildStar Packet Analysis"
      assert prompt =~ "3 unknown packets"
      assert prompt =~ "0x1111"
      assert prompt =~ "0x2222"
      assert prompt =~ "0x3333"
    end

    test "includes packet numbers" do
      events = [
        sample_event(opcode_hex: "0x1111"),
        sample_event(opcode_hex: "0x2222")
      ]

      prompt = LlmAssistant.generate_batch_prompt(events)

      assert prompt =~ "Packet 1: 0x1111"
      assert prompt =~ "Packet 2: 0x2222"
    end

    test "includes context for each packet" do
      events = [sample_event(player_commentary: "First action")]

      prompt = LlmAssistant.generate_batch_prompt(events)

      assert prompt =~ "First action"
      assert prompt =~ "Zone:"
      assert prompt =~ "State:"
    end

    test "requests summary analysis" do
      events = [sample_event()]

      prompt = LlmAssistant.generate_batch_prompt(events)

      assert prompt =~ "Summary Request"
      assert prompt =~ "summary table"
      assert prompt =~ "implementation order"
      assert prompt =~ "patterns"
    end
  end
end

defmodule BezgelorDev.LlmAssistantFileTest do
  # Separate module for file system tests - not async due to Application.put_env
  use ExUnit.Case, async: false

  alias BezgelorDev.LlmAssistant
  alias BezgelorDev.PacketContext

  setup do
    # Create temp directory for each test
    tmp_dir = Path.join(System.tmp_dir!(), "bezgelor_test_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)

    # Store original config
    original_dir = Application.get_env(:bezgelor_dev, :capture_directory)

    on_exit(fn ->
      # Clean up temp directory
      File.rm_rf!(tmp_dir)
      # Restore original config
      if original_dir do
        Application.put_env(:bezgelor_dev, :capture_directory, original_dir)
      else
        Application.delete_env(:bezgelor_dev, :capture_directory)
      end
    end)

    {:ok, tmp_dir: tmp_dir}
  end

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
      recent_packets: [],
      last_packet_received_at: nil,
      last_packet_sent_at: nil
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
      player_commentary: Keyword.get(opts, :player_commentary, "Opening my bag"),
      llm_analysis: Keyword.get(opts, :llm_analysis, nil)
    }
  end

  describe "save_prompts_for_analysis/2" do
    test "saves individual prompts to files", %{tmp_dir: tmp_dir} do
      Application.put_env(:bezgelor_dev, :capture_directory, tmp_dir)

      session_id = "test_session"
      session_dir = Path.join([tmp_dir, "sessions", session_id])
      File.mkdir_p!(session_dir)

      events = [
        sample_event(opcode_hex: "0x1234"),
        sample_event(opcode_hex: "0x5678")
      ]

      {:ok, prompts_dir} = LlmAssistant.save_prompts_for_analysis(session_id, events)

      assert File.exists?(prompts_dir)
      assert File.exists?(Path.join(prompts_dir, "prompt_1234.md"))
      assert File.exists?(Path.join(prompts_dir, "prompt_5678.md"))
    end

    test "saves batch prompt when multiple events", %{tmp_dir: tmp_dir} do
      Application.put_env(:bezgelor_dev, :capture_directory, tmp_dir)

      session_id = "test_session"
      session_dir = Path.join([tmp_dir, "sessions", session_id])
      File.mkdir_p!(session_dir)

      events = [
        sample_event(opcode_hex: "0x1111"),
        sample_event(opcode_hex: "0x2222")
      ]

      {:ok, prompts_dir} = LlmAssistant.save_prompts_for_analysis(session_id, events)

      batch_path = Path.join(prompts_dir, "batch_analysis.md")
      assert File.exists?(batch_path)

      content = File.read!(batch_path)
      assert content =~ "Batch"
      assert content =~ "0x1111"
      assert content =~ "0x2222"
    end

    test "does not create batch prompt for single event", %{tmp_dir: tmp_dir} do
      Application.put_env(:bezgelor_dev, :capture_directory, tmp_dir)

      session_id = "test_session"
      session_dir = Path.join([tmp_dir, "sessions", session_id])
      File.mkdir_p!(session_dir)

      events = [sample_event(opcode_hex: "0x1234")]

      {:ok, prompts_dir} = LlmAssistant.save_prompts_for_analysis(session_id, events)

      # Individual prompt should exist
      assert File.exists?(Path.join(prompts_dir, "prompt_1234.md"))

      # Batch prompt should not exist
      refute File.exists?(Path.join(prompts_dir, "batch_analysis.md"))
    end
  end
end
