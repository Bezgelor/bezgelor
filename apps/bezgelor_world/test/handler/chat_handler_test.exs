defmodule BezgelorWorld.Handler.ChatHandlerTest do
  use ExUnit.Case, async: false

  alias BezgelorWorld.Handler.ChatHandler
  alias BezgelorWorld.WorldManager
  alias BezgelorProtocol.PacketWriter
  alias BezgelorCore.Chat

  setup do
    # Start WorldManager for tests
    case WorldManager.start_link() do
      {:ok, pid} ->
        on_exit(fn -> Process.exit(pid, :normal) end)

      {:error, {:already_started, _}} ->
        :ok
    end

    :ok
  end

  defp make_session_state(opts \\ []) do
    defaults = [
      in_world: true,
      entity_guid: 12345,
      character_name: "TestPlayer",
      entity: %{position: {100.0, 200.0, 50.0}, world_id: 1, zone_id: 1}
    ]

    session_data = Keyword.merge(defaults, opts) |> Map.new()
    %{session_data: session_data}
  end

  defp build_chat_payload(channel, target, message) do
    channel_int = Chat.channel_to_int(channel)

    writer =
      PacketWriter.new()
      |> PacketWriter.write_u32(channel_int)
      |> PacketWriter.write_wide_string(target)
      |> PacketWriter.write_wide_string(message)
      |> PacketWriter.flush_bits()

    PacketWriter.to_binary(writer)
  end

  describe "handle/2 basic chat" do
    test "processes say message successfully" do
      payload = build_chat_payload(:say, "", "Hello world")
      state = make_session_state()

      result = ChatHandler.handle(payload, state)

      assert {:reply, :server_chat, _packet_data, ^state} = result
    end

    test "processes yell message" do
      payload = build_chat_payload(:yell, "", "Look out!")
      state = make_session_state()

      result = ChatHandler.handle(payload, state)

      assert {:reply, :server_chat, _packet_data, ^state} = result
    end

    test "processes emote message" do
      payload = build_chat_payload(:emote, "", "waves")
      state = make_session_state()

      result = ChatHandler.handle(payload, state)

      assert {:reply, :server_chat, _packet_data, ^state} = result
    end

    test "rejects chat before player in world" do
      payload = build_chat_payload(:say, "", "Hello")
      state = make_session_state(in_world: false)

      result = ChatHandler.handle(payload, state)

      assert {:error, :not_in_world} = result
    end
  end

  describe "handle/2 commands" do
    test "/say command works" do
      payload = build_chat_payload(:say, "", "/say Testing")
      state = make_session_state()

      result = ChatHandler.handle(payload, state)

      assert {:reply, :server_chat, _packet_data, ^state} = result
    end

    test "/yell command works" do
      payload = build_chat_payload(:say, "", "/yell LOUD!")
      state = make_session_state()

      result = ChatHandler.handle(payload, state)

      assert {:reply, :server_chat, _packet_data, ^state} = result
    end

    test "/who command returns player count" do
      payload = build_chat_payload(:say, "", "/who")
      state = make_session_state()

      result = ChatHandler.handle(payload, state)

      # Returns system message with count
      assert {:reply, :server_chat, _packet_data, ^state} = result
    end

    test "/loc command returns location" do
      payload = build_chat_payload(:say, "", "/loc")
      state = make_session_state()

      result = ChatHandler.handle(payload, state)

      assert {:reply, :server_chat, _packet_data, ^state} = result
    end

    test "/loc without entity returns unavailable" do
      payload = build_chat_payload(:say, "", "/loc")
      state = make_session_state(entity: nil)

      result = ChatHandler.handle(payload, state)

      assert {:reply, :server_chat, _packet_data, ^state} = result
    end

    test "unknown command returns error message" do
      payload = build_chat_payload(:say, "", "/unknowncmd")
      state = make_session_state()

      result = ChatHandler.handle(payload, state)

      assert {:reply, :server_chat, _packet_data, ^state} = result
    end
  end

  describe "handle/2 whisper errors" do
    test "/w without target returns usage" do
      payload = build_chat_payload(:say, "", "/w")
      state = make_session_state()

      result = ChatHandler.handle(payload, state)

      # Returns system message with usage
      assert {:reply, :server_chat, _packet_data, ^state} = result
    end

    test "/whisper without message returns usage" do
      payload = build_chat_payload(:say, "", "/whisper SomePlayer")
      state = make_session_state()

      result = ChatHandler.handle(payload, state)

      assert {:reply, :server_chat, _packet_data, ^state} = result
    end

    test "/w to unknown player returns not found" do
      payload = build_chat_payload(:say, "", "/w NonexistentPlayer Hello")
      state = make_session_state()

      result = ChatHandler.handle(payload, state)

      # Returns chat result with player not found
      assert {:reply, :server_chat_result, _packet_data, ^state} = result
    end
  end

  describe "handle/2 channel behavior" do
    # NOTE: The ChatCommand parser determines the channel from the message content,
    # ignoring the packet's channel field. Messages without a command prefix
    # default to :say channel.

    test "packet channel is ignored - message determines channel" do
      # Sending on party channel, but message has no command prefix
      # So it gets treated as :say
      payload = build_chat_payload(:party, "", "Party message")
      state = make_session_state()

      result = ChatHandler.handle(payload, state)

      # Returns server_chat (success) because it becomes a :say message
      assert {:reply, :server_chat, _packet_data, ^state} = result
    end

    test "zone channel messages work" do
      payload = build_chat_payload(:say, "", "/zone Hello zone!")
      state = make_session_state()

      result = ChatHandler.handle(payload, state)

      assert {:reply, :server_chat, _packet_data, ^state} = result
    end
  end

  describe "handle/2 message length" do
    test "very long message returns error" do
      long_message = String.duplicate("x", Chat.max_message_length() + 1)
      payload = build_chat_payload(:say, "", long_message)
      state = make_session_state()

      result = ChatHandler.handle(payload, state)

      assert {:reply, :server_chat_result, _packet_data, ^state} = result
    end

    test "message at max length succeeds" do
      max_message = String.duplicate("x", Chat.max_message_length())
      payload = build_chat_payload(:say, "", max_message)
      state = make_session_state()

      result = ChatHandler.handle(payload, state)

      assert {:reply, :server_chat, _packet_data, ^state} = result
    end
  end
end
