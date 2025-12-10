defmodule BezgelorCore.ChatCommandTest do
  use ExUnit.Case, async: true

  alias BezgelorCore.ChatCommand

  describe "parse/1" do
    test "plain message defaults to say channel" do
      assert {:chat, :say, "Hello world"} == ChatCommand.parse("Hello world")
    end

    test "empty message defaults to say channel" do
      assert {:chat, :say, ""} == ChatCommand.parse("")
    end

    test "/say command" do
      assert {:chat, :say, "Hello"} == ChatCommand.parse("/say Hello")
    end

    test "/s alias for say" do
      assert {:chat, :say, "Hi there"} == ChatCommand.parse("/s Hi there")
    end

    test "/yell command" do
      assert {:chat, :yell, "Look out!"} == ChatCommand.parse("/yell Look out!")
    end

    test "/y alias for yell" do
      assert {:chat, :yell, "Hey!"} == ChatCommand.parse("/y Hey!")
    end

    test "/emote command" do
      assert {:chat, :emote, "waves"} == ChatCommand.parse("/emote waves")
    end

    test "/e alias for emote" do
      assert {:chat, :emote, "dances"} == ChatCommand.parse("/e dances")
    end

    test "/me alias for emote" do
      assert {:chat, :emote, "laughs"} == ChatCommand.parse("/me laughs")
    end

    test "/zone command" do
      assert {:chat, :zone, "LFG dungeon"} == ChatCommand.parse("/zone LFG dungeon")
    end

    test "/z alias for zone" do
      assert {:chat, :zone, "Anyone there?"} == ChatCommand.parse("/z Anyone there?")
    end

    test "commands are case insensitive" do
      assert {:chat, :say, "Hello"} == ChatCommand.parse("/SAY Hello")
      assert {:chat, :yell, "Hi"} == ChatCommand.parse("/YELL Hi")
    end
  end

  describe "parse/1 whisper" do
    test "/whisper with target and message" do
      assert {:whisper, "PlayerName", "Hello!"} == ChatCommand.parse("/whisper PlayerName Hello!")
    end

    test "/w alias for whisper" do
      assert {:whisper, "TestPlayer", "Hi there"} == ChatCommand.parse("/w TestPlayer Hi there")
    end

    test "/tell alias for whisper" do
      assert {:whisper, "Friend", "What's up?"} == ChatCommand.parse("/tell Friend What's up?")
    end

    test "whisper without target returns error" do
      assert {:error, :whisper_no_target} == ChatCommand.parse("/whisper")
      assert {:error, :whisper_no_target} == ChatCommand.parse("/w")
    end

    test "whisper with target but no message returns error" do
      assert {:error, :whisper_no_message} == ChatCommand.parse("/whisper PlayerName")
      assert {:error, :whisper_no_message} == ChatCommand.parse("/w Target")
    end

    test "whisper preserves message with spaces" do
      assert {:whisper, "Player", "This is a longer message"} ==
               ChatCommand.parse("/w Player This is a longer message")
    end
  end

  describe "parse/1 actions" do
    test "/who command" do
      assert {:action, :who, []} == ChatCommand.parse("/who")
    end

    test "/who ignores arguments" do
      assert {:action, :who, []} == ChatCommand.parse("/who extra args")
    end

    test "/loc command" do
      assert {:action, :location, []} == ChatCommand.parse("/loc")
    end

    test "/location command" do
      assert {:action, :location, []} == ChatCommand.parse("/location")
    end
  end

  describe "parse/1 unknown commands" do
    test "unknown command returns error" do
      assert {:error, {:unknown_command, "unknowncommand"}} == ChatCommand.parse("/unknowncommand")
    end

    test "unknown command with args returns error" do
      assert {:error, {:unknown_command, "foo"}} == ChatCommand.parse("/foo bar baz")
    end
  end

  describe "command?/1" do
    test "returns true for commands" do
      assert ChatCommand.command?("/say Hello")
      assert ChatCommand.command?("/w Player Hi")
      assert ChatCommand.command?("/who")
    end

    test "returns false for regular messages" do
      refute ChatCommand.command?("Hello world")
      refute ChatCommand.command?("")
      refute ChatCommand.command?("Not a /command")
    end
  end
end
