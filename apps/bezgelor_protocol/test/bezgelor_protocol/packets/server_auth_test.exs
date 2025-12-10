defmodule BezgelorProtocol.Packets.ServerAuthTest do
  use ExUnit.Case, async: true

  alias BezgelorProtocol.Packets.{ServerAuthAccepted, ServerAuthDenied}
  alias BezgelorProtocol.PacketWriter

  describe "ServerAuthAccepted" do
    test "writes packet with server proof and game token" do
      server_proof = :crypto.strong_rand_bytes(32)
      game_token = :crypto.strong_rand_bytes(16)

      packet = %ServerAuthAccepted{
        server_proof_m2: server_proof,
        game_token: game_token
      }

      writer = PacketWriter.new()
      {:ok, writer} = ServerAuthAccepted.write(packet, writer)
      binary = PacketWriter.to_binary(writer)

      # Should be 32 + 16 = 48 bytes
      assert byte_size(binary) == 48
      assert binary == server_proof <> game_token
    end

    test "returns correct opcode" do
      assert ServerAuthAccepted.opcode() == :server_auth_accepted
    end
  end

  describe "ServerAuthDenied" do
    test "writes packet with result and error value" do
      packet = %ServerAuthDenied{
        result: :version_mismatch,
        error_value: 0,
        suspended_days: 0.0
      }

      writer = PacketWriter.new()
      {:ok, writer} = ServerAuthDenied.write(packet, writer)
      binary = PacketWriter.to_binary(writer)

      # result: uint32 + error_value: uint32 + suspended_days: float32 = 12 bytes
      assert byte_size(binary) == 12

      <<result::little-32, error::little-32, _days::little-float-32>> = binary
      assert result == 19  # version_mismatch
      assert error == 0
    end

    test "writes suspended account with days remaining" do
      packet = %ServerAuthDenied{
        result: :account_suspended,
        error_value: 0,
        suspended_days: 7.5
      }

      writer = PacketWriter.new()
      {:ok, writer} = ServerAuthDenied.write(packet, writer)
      binary = PacketWriter.to_binary(writer)

      <<result::little-32, _error::little-32, days::little-float-32>> = binary
      assert result == 21  # account_suspended
      assert_in_delta days, 7.5, 0.001
    end

    test "returns correct opcode" do
      assert ServerAuthDenied.opcode() == :server_auth_denied
    end
  end
end
