defmodule BezgelorProtocol.OpcodeTest do
  use ExUnit.Case, async: true

  alias BezgelorProtocol.Opcode

  describe "to_integer/1" do
    test "returns integer for known opcode" do
      assert Opcode.to_integer(:server_hello) == 0x0003
      assert Opcode.to_integer(:server_auth_encrypted) == 0x0076
      assert Opcode.to_integer(:client_hello_auth) == 0x0004
    end
  end

  describe "from_integer/1" do
    test "returns atom for known opcode" do
      assert Opcode.from_integer(0x0003) == {:ok, :server_hello}
      assert Opcode.from_integer(0x0076) == {:ok, :server_auth_encrypted}
    end

    test "returns error for unknown opcode" do
      assert Opcode.from_integer(0xFFFF) == {:error, :unknown_opcode}
    end
  end

  describe "name/1" do
    test "returns human-readable name" do
      assert Opcode.name(:server_hello) == "ServerHello"
      assert Opcode.name(:client_hello_auth) == "ClientHelloAuth"
    end
  end
end
