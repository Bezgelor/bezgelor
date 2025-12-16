defmodule BezgelorProtocol.Packets.World.ClientResurrectAcceptTest do
  use ExUnit.Case, async: true

  alias BezgelorProtocol.Packets.World.ClientResurrectAccept
  alias BezgelorProtocol.PacketReader

  describe "read/1" do
    test "reads accept response" do
      # accept = true (1)
      binary = <<1::little-8>>
      reader = PacketReader.new(binary)

      {:ok, packet, _reader} = ClientResurrectAccept.read(reader)

      assert packet.accept == true
    end

    test "reads decline response" do
      # accept = false (0)
      binary = <<0::little-8>>
      reader = PacketReader.new(binary)

      {:ok, packet, _reader} = ClientResurrectAccept.read(reader)

      assert packet.accept == false
    end

    test "treats any non-zero value as accept" do
      binary = <<5::little-8>>
      reader = PacketReader.new(binary)

      {:ok, packet, _reader} = ClientResurrectAccept.read(reader)

      assert packet.accept == true
    end
  end

  describe "opcode/0" do
    test "returns correct opcode" do
      assert ClientResurrectAccept.opcode() == :client_resurrect_accept
    end
  end
end
