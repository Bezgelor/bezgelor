defmodule BezgelorAuth.Integration.AuthFlowTest do
  @moduledoc """
  Integration test for the full authentication flow.

  Tests the complete client-server authentication handshake:
  1. Connect to auth server
  2. Receive ServerHello
  3. Send ClientHelloAuth
  4. Receive ServerAuthAccepted or ServerAuthDenied
  """

  use ExUnit.Case, async: false

  alias BezgelorDb.{Accounts, Repo}
  alias BezgelorProtocol.{Framing, Opcode, TcpListener}

  @moduletag :integration

  # Use a high ephemeral port for testing
  @test_port 46600

  setup_all do
    # Start the packet registry
    case BezgelorProtocol.PacketRegistry.start_link([]) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    # Start the TCP listener directly
    case TcpListener.start_link(
           port: @test_port,
           handler: BezgelorProtocol.Connection,
           handler_opts: [connection_type: :auth],
           name: :test_auth_listener
         ) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    # Wait for server to be ready
    :timer.sleep(100)

    on_exit(fn ->
      TcpListener.stop(:test_auth_listener)
    end)

    :ok
  end

  setup do
    # Checkout a database connection
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    :ok
  end

  describe "authentication flow" do
    test "successful connection receives ServerHello" do
      {:ok, socket} = :gen_tcp.connect(~c"localhost", @test_port, [:binary, active: false])

      # Should receive ServerHello packet
      {:ok, data} = :gen_tcp.recv(socket, 0, 5000)
      # At least a header
      assert byte_size(data) > 6

      # Parse the packet header
      <<_size::little-32, opcode::little-16, _payload::binary>> = data

      # Verify it's a ServerHello
      assert {:ok, :server_hello} = Opcode.from_integer(opcode)

      :gen_tcp.close(socket)
    end

    test "auth with non-existent account returns denial" do
      {:ok, socket} = :gen_tcp.connect(~c"localhost", @test_port, [:binary, active: false])

      # Receive and discard ServerHello
      {:ok, _hello} = :gen_tcp.recv(socket, 0, 5000)

      # Send ClientHelloAuth for non-existent account
      auth_packet = build_client_hello_auth(16042, "nonexistent@test.com")
      framed = Framing.frame_packet(Opcode.to_integer(:client_hello_auth), auth_packet)
      :ok = :gen_tcp.send(socket, framed)

      # Receive response
      {:ok, response_data} = :gen_tcp.recv(socket, 0, 5000)

      # Parse response
      <<_size::little-32, opcode::little-16, payload::binary>> = response_data

      # Should be ServerAuthDenied
      assert {:ok, :server_auth_denied} = Opcode.from_integer(opcode)

      # Parse denial payload
      <<result_code::little-32, _error::little-32, _days::little-float-32>> = payload

      # Result code 16 = invalid_token (account not found)
      assert result_code == 16

      :gen_tcp.close(socket)
    end

    test "auth with wrong build version returns version mismatch" do
      {:ok, socket} = :gen_tcp.connect(~c"localhost", @test_port, [:binary, active: false])

      # Receive and discard ServerHello
      {:ok, _hello} = :gen_tcp.recv(socket, 0, 5000)

      # Send ClientHelloAuth with wrong build
      auth_packet = build_client_hello_auth(99999, "test@example.com")
      framed = Framing.frame_packet(Opcode.to_integer(:client_hello_auth), auth_packet)
      :ok = :gen_tcp.send(socket, framed)

      # Receive response
      {:ok, response_data} = :gen_tcp.recv(socket, 0, 5000)

      # Parse response
      <<_size::little-32, opcode::little-16, payload::binary>> = response_data

      # Should be ServerAuthDenied
      assert {:ok, :server_auth_denied} = Opcode.from_integer(opcode)

      # Parse denial payload
      <<result_code::little-32, _error::little-32, _days::little-float-32>> = payload

      # Result code 19 = version_mismatch
      assert result_code == 19

      :gen_tcp.close(socket)
    end

    test "banned account returns account_banned" do
      # Create account and ban it
      email = "banned#{System.unique_integer([:positive])}@test.com"
      {:ok, account} = Accounts.create_account(email, "password123")
      # Permanent ban
      {:ok, _} = Accounts.create_suspension(account, "Cheating", nil)

      {:ok, socket} = :gen_tcp.connect(~c"localhost", @test_port, [:binary, active: false])

      # Receive and discard ServerHello
      {:ok, _hello} = :gen_tcp.recv(socket, 0, 5000)

      # Send ClientHelloAuth
      auth_packet = build_client_hello_auth(16042, email)
      framed = Framing.frame_packet(Opcode.to_integer(:client_hello_auth), auth_packet)
      :ok = :gen_tcp.send(socket, framed)

      # Receive response
      {:ok, response_data} = :gen_tcp.recv(socket, 0, 5000)

      # Parse response
      <<_size::little-32, opcode::little-16, payload::binary>> = response_data

      # Should be ServerAuthDenied
      assert {:ok, :server_auth_denied} = Opcode.from_integer(opcode)

      # Parse denial payload
      <<result_code::little-32, _error::little-32, _days::little-float-32>> = payload

      # Result code 20 = account_banned
      assert result_code == 20

      :gen_tcp.close(socket)
    end
  end

  # Build a ClientHelloAuth packet payload
  defp build_client_hello_auth(build, email) do
    client_key_a = :crypto.strong_rand_bytes(128)
    client_proof_m1 = :crypto.strong_rand_bytes(32)

    utf16_email = :unicode.characters_to_binary(email, :utf8, {:utf16, :little})
    email_length = String.length(email)

    <<
      build::little-32,
      email_length::little-32,
      utf16_email::binary,
      client_key_a::binary-size(128),
      client_proof_m1::binary-size(32)
    >>
  end
end
