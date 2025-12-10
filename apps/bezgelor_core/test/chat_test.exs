defmodule BezgelorCore.ChatTest do
  use ExUnit.Case, async: true

  alias BezgelorCore.Chat

  describe "channel_to_int/1" do
    test "converts known channels to integers" do
      assert 0 == Chat.channel_to_int(:say)
      assert 1 == Chat.channel_to_int(:yell)
      assert 2 == Chat.channel_to_int(:whisper)
      assert 3 == Chat.channel_to_int(:system)
      assert 4 == Chat.channel_to_int(:emote)
      assert 5 == Chat.channel_to_int(:party)
      assert 6 == Chat.channel_to_int(:guild)
      assert 7 == Chat.channel_to_int(:zone)
    end

    test "unknown channels default to say (0)" do
      assert 0 == Chat.channel_to_int(:unknown)
      assert 0 == Chat.channel_to_int(:invalid)
    end
  end

  describe "int_to_channel/1" do
    test "converts integers to known channels" do
      assert :say == Chat.int_to_channel(0)
      assert :yell == Chat.int_to_channel(1)
      assert :whisper == Chat.int_to_channel(2)
      assert :system == Chat.int_to_channel(3)
      assert :emote == Chat.int_to_channel(4)
      assert :party == Chat.int_to_channel(5)
      assert :guild == Chat.int_to_channel(6)
      assert :zone == Chat.int_to_channel(7)
    end

    test "unknown integers default to say" do
      assert :say == Chat.int_to_channel(99)
      assert :say == Chat.int_to_channel(-1)
    end
  end

  describe "roundtrip" do
    test "channel_to_int and int_to_channel are inverse" do
      for channel <- [:say, :yell, :whisper, :system, :emote, :party, :guild, :zone] do
        int = Chat.channel_to_int(channel)
        assert channel == Chat.int_to_channel(int)
      end
    end
  end

  describe "range/1" do
    test "say range is 30.0" do
      assert 30.0 == Chat.range(:say)
    end

    test "yell range is 100.0" do
      assert 100.0 == Chat.range(:yell)
    end

    test "emote range is 30.0" do
      assert 30.0 == Chat.range(:emote)
    end

    test "whisper has nil range (global)" do
      assert nil == Chat.range(:whisper)
    end

    test "zone has nil range (zone-wide)" do
      assert nil == Chat.range(:zone)
    end

    test "system has nil range (broadcast)" do
      assert nil == Chat.range(:system)
    end

    test "unknown channels return nil" do
      assert nil == Chat.range(:unknown)
    end
  end

  describe "available?/1" do
    test "basic channels are available" do
      assert Chat.available?(:say)
      assert Chat.available?(:yell)
      assert Chat.available?(:whisper)
      assert Chat.available?(:system)
      assert Chat.available?(:emote)
      assert Chat.available?(:zone)
    end

    test "party and guild channels are not yet available" do
      refute Chat.available?(:party)
      refute Chat.available?(:guild)
    end

    test "unknown channels are not available" do
      refute Chat.available?(:unknown)
    end
  end

  describe "max_message_length/0" do
    test "returns maximum message length" do
      assert 500 == Chat.max_message_length()
    end
  end
end
