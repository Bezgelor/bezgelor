defmodule BezgelorProtocol.PacketRegistryTest do
  use ExUnit.Case, async: true

  alias BezgelorProtocol.PacketRegistry

  describe "lookup/1" do
    test "returns handler for known opcode" do
      # ServerHello has no client handler (server-only packet)
      assert PacketRegistry.lookup(:server_hello) == nil

      # These are client packets that need handlers
      assert PacketRegistry.lookup(:client_hello_auth) != nil
    end

    test "returns nil for unknown opcode" do
      assert PacketRegistry.lookup(:nonexistent_opcode) == nil
    end
  end

  describe "register/2" do
    test "registers custom handler" do
      defmodule TestHandler do
        def handle(_payload, _state), do: {:ok, %{}}
      end

      :ok = PacketRegistry.register(:test_opcode, TestHandler)
      assert PacketRegistry.lookup(:test_opcode) == TestHandler
    end
  end
end
