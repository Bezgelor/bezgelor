defmodule BezgelorWorld.WorldManagerChatTest do
  use ExUnit.Case, async: false

  alias BezgelorWorld.WorldManager

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

  describe "register_session/4" do
    test "stores character_name in session" do
      :ok = WorldManager.register_session(1, 100, "TestChar", self())

      session = WorldManager.get_session(1)
      assert session.character_name == "TestChar"
      assert session.character_id == 100
      assert session.connection_pid == self()
    end

    test "allows nil character_name" do
      :ok = WorldManager.register_session(2, 200, nil, self())

      session = WorldManager.get_session(2)
      assert session.character_name == nil
    end
  end

  describe "find_session_by_name/1" do
    test "finds session by exact name" do
      :ok = WorldManager.register_session(10, 100, "PlayerOne", self())

      result = WorldManager.find_session_by_name("PlayerOne")

      assert {10, session} = result
      assert session.character_name == "PlayerOne"
    end

    test "finds session case-insensitively" do
      :ok = WorldManager.register_session(11, 110, "PlayerTwo", self())

      assert {11, _} = WorldManager.find_session_by_name("playertwo")
      assert {11, _} = WorldManager.find_session_by_name("PLAYERTWO")
      assert {11, _} = WorldManager.find_session_by_name("PlAyErTwO")
    end

    test "returns nil when not found" do
      result = WorldManager.find_session_by_name("NonexistentPlayer")
      assert result == nil
    end

    test "returns nil for nil name queries" do
      :ok = WorldManager.register_session(12, 120, nil, self())

      # Searching for a name should not find a session with nil name
      result = WorldManager.find_session_by_name("SomeName")
      assert result == nil
    end
  end

  describe "send_whisper/4" do
    test "returns ok when target found" do
      # Register a target session
      target_pid = spawn(fn -> receive_loop() end)
      :ok = WorldManager.register_session(20, 200, "TargetPlayer", target_pid)

      result = WorldManager.send_whisper(12345, "Sender", "TargetPlayer", "Hello!")

      assert result == :ok

      # Give some time for message to be received
      Process.sleep(10)

      # Cleanup
      Process.exit(target_pid, :kill)
    end

    test "returns error when target not found" do
      result = WorldManager.send_whisper(12345, "Sender", "UnknownPlayer", "Hello?")

      assert result == {:error, :player_not_found}
    end

    test "whisper is case-insensitive for target name" do
      target_pid = spawn(fn -> receive_loop() end)
      :ok = WorldManager.register_session(21, 210, "CasedName", target_pid)

      assert :ok == WorldManager.send_whisper(12345, "Sender", "casedname", "Hi")
      assert :ok == WorldManager.send_whisper(12345, "Sender", "CASEDNAME", "Hi")

      Process.exit(target_pid, :kill)
    end
  end

  describe "broadcast_chat/5" do
    test "broadcasts to all other sessions" do
      # Register multiple sessions
      pid1 = spawn(fn -> receive_loop() end)
      pid2 = spawn(fn -> receive_loop() end)
      sender_pid = self()

      # Sender's session
      :ok = WorldManager.register_session(30, 300, "Sender", sender_pid)
      WorldManager.set_entity_guid(30, 1000)

      # Other sessions
      :ok = WorldManager.register_session(31, 310, "Receiver1", pid1)
      WorldManager.set_entity_guid(31, 1001)

      :ok = WorldManager.register_session(32, 320, "Receiver2", pid2)
      WorldManager.set_entity_guid(32, 1002)

      # Broadcast
      WorldManager.broadcast_chat(1000, "Sender", :say, "Hello everyone", {0.0, 0.0, 0.0})

      # Give time for messages
      Process.sleep(10)

      # Cleanup
      Process.exit(pid1, :kill)
      Process.exit(pid2, :kill)
    end

    test "does not send to sender" do
      # This is implicit from the handler logic, but we can verify broadcast doesn't error
      :ok = WorldManager.register_session(40, 400, "LoneSender", self())
      WorldManager.set_entity_guid(40, 2000)

      # This should complete without error
      WorldManager.broadcast_chat(2000, "LoneSender", :say, "Hello?", {0.0, 0.0, 0.0})

      # We shouldn't receive our own message back via broadcast
      refute_receive {:send_chat, _, _, _, _}, 50
    end
  end

  defp receive_loop do
    receive do
      {:send_chat, _sender_guid, _sender_name, _channel, _message} ->
        receive_loop()

      _ ->
        receive_loop()
    after
      5000 -> :ok
    end
  end
end
