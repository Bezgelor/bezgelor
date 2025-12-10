defmodule BezgelorRealm.Integration.RealmFlowTest do
  @moduledoc """
  Integration test for the full realm authentication flow.

  Tests the complete client-server realm handshake:
  1. Connect to realm server
  2. Receive ServerHello
  3. Send ClientHelloAuth with game token
  4. Receive ServerAuthAccepted + ServerRealmMessages + ServerRealmInfo
  OR
  4. Receive ServerAuthDenied
  """

  use ExUnit.Case, async: false

  alias BezgelorDb.{Accounts, Realms, Repo}
  alias BezgelorProtocol.{Framing, Opcode, TcpListener}

  @moduletag :integration

  # Use a high ephemeral port for testing
  @test_port 46601

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
           handler_opts: [connection_type: :realm],
           name: :test_realm_listener
         ) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    # Wait for server to be ready
    :timer.sleep(100)

    on_exit(fn ->
      TcpListener.stop(:test_realm_listener)
    end)

    :ok
  end

  setup do
    # Checkout a database connection
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    :ok
  end

  describe "realm authentication flow" do
    test "successful connection receives ServerHello" do
      {:ok, socket} = :gen_tcp.connect(~c"localhost", @test_port, [:binary, active: false])

      # Should receive ServerHello packet
      {:ok, data} = :gen_tcp.recv(socket, 0, 5000)
      assert byte_size(data) > 6  # At least a header

      # Parse the packet header
      <<_size::little-32, opcode::little-16, _payload::binary>> = data

      # Verify it's a ServerHello
      assert {:ok, :server_hello} = Opcode.from_integer(opcode)

      :gen_tcp.close(socket)
    end

    test "auth with valid game token succeeds" do
      # Create account with game token
      email = "realm_test#{System.unique_integer([:positive])}@test.com"
      {:ok, account} = Accounts.create_account(email, "password123")
      game_token = BezgelorCrypto.Random.bytes(16)
      game_token_hex = Base.encode16(game_token)
      {:ok, _account} = Accounts.update_game_token(account, game_token_hex)

      # Create an online realm
      {:ok, _realm} = Realms.create_realm(%{
        name: "TestRealm#{System.unique_integer([:positive])}",
        address: "127.0.0.1",
        port: 24000,
        type: :pve,
        online: true
      })

      {:ok, socket} = :gen_tcp.connect(~c"localhost", @test_port, [:binary, active: false])

      # Receive and discard ServerHello
      {:ok, _hello} = :gen_tcp.recv(socket, 0, 5000)

      # Send ClientHelloAuth with game token
      auth_packet = build_client_hello_auth(16042, email, game_token)
      framed = Framing.frame_packet(Opcode.to_integer(:client_hello_auth_realm), auth_packet)
      :ok = :gen_tcp.send(socket, framed)

      # Should receive ServerAuthAccepted
      {:ok, response_data} = :gen_tcp.recv(socket, 0, 5000)

      # Parse response - may contain multiple packets
      <<_size::little-32, opcode::little-16, _payload::binary>> = response_data

      assert {:ok, :server_auth_accepted_realm} = Opcode.from_integer(opcode)

      :gen_tcp.close(socket)
    end

    test "auth with invalid token returns denial" do
      {:ok, socket} = :gen_tcp.connect(~c"localhost", @test_port, [:binary, active: false])

      # Receive and discard ServerHello
      {:ok, _hello} = :gen_tcp.recv(socket, 0, 5000)

      # Send ClientHelloAuth with invalid/random token
      auth_packet = build_client_hello_auth(16042, "invalid@test.com", :crypto.strong_rand_bytes(16))
      framed = Framing.frame_packet(Opcode.to_integer(:client_hello_auth_realm), auth_packet)
      :ok = :gen_tcp.send(socket, framed)

      # Receive response
      {:ok, response_data} = :gen_tcp.recv(socket, 0, 5000)

      # Parse response
      <<_size::little-32, opcode::little-16, payload::binary>> = response_data

      # Should be ServerAuthDenied
      assert {:ok, :server_auth_denied_realm} = Opcode.from_integer(opcode)

      # Parse denial payload
      <<result_code::little-32, _error::little-32, _days::little-float-32>> = payload

      # Result code 16 = invalid_token
      assert result_code == 16

      :gen_tcp.close(socket)
    end

    test "auth with wrong build version returns version mismatch" do
      {:ok, socket} = :gen_tcp.connect(~c"localhost", @test_port, [:binary, active: false])

      # Receive and discard ServerHello
      {:ok, _hello} = :gen_tcp.recv(socket, 0, 5000)

      # Send ClientHelloAuth with wrong build
      auth_packet = build_client_hello_auth(99999, "test@example.com", :crypto.strong_rand_bytes(16))
      framed = Framing.frame_packet(Opcode.to_integer(:client_hello_auth_realm), auth_packet)
      :ok = :gen_tcp.send(socket, framed)

      # Receive response
      {:ok, response_data} = :gen_tcp.recv(socket, 0, 5000)

      # Parse response
      <<_size::little-32, opcode::little-16, payload::binary>> = response_data

      # Should be ServerAuthDenied
      assert {:ok, :server_auth_denied_realm} = Opcode.from_integer(opcode)

      # Parse denial payload
      <<result_code::little-32, _error::little-32, _days::little-float-32>> = payload

      # Result code 19 = version_mismatch
      assert result_code == 19

      :gen_tcp.close(socket)
    end

    test "auth with no online realms returns no_realms_available" do
      # Create account with game token but NO online realms
      email = "norealm_test#{System.unique_integer([:positive])}@test.com"
      {:ok, account} = Accounts.create_account(email, "password123")
      game_token = BezgelorCrypto.Random.bytes(16)
      game_token_hex = Base.encode16(game_token)
      {:ok, _account} = Accounts.update_game_token(account, game_token_hex)

      # Ensure no online realms exist for this test
      # (Previous tests may have created online realms)
      # Create an offline realm
      {:ok, _realm} = Realms.create_realm(%{
        name: "OfflineRealm#{System.unique_integer([:positive])}",
        address: "127.0.0.1",
        port: 24001,
        type: :pve,
        online: false
      })

      # Set all realms offline for this test
      Realms.list_realms()
      |> Enum.each(fn r -> Realms.set_online(r, false) end)

      {:ok, socket} = :gen_tcp.connect(~c"localhost", @test_port, [:binary, active: false])

      # Receive and discard ServerHello
      {:ok, _hello} = :gen_tcp.recv(socket, 0, 5000)

      # Send ClientHelloAuth
      auth_packet = build_client_hello_auth(16042, email, game_token)
      framed = Framing.frame_packet(Opcode.to_integer(:client_hello_auth_realm), auth_packet)
      :ok = :gen_tcp.send(socket, framed)

      # Receive response
      {:ok, response_data} = :gen_tcp.recv(socket, 0, 5000)

      # Parse response
      <<_size::little-32, opcode::little-16, payload::binary>> = response_data

      # Should be ServerAuthDenied
      assert {:ok, :server_auth_denied_realm} = Opcode.from_integer(opcode)

      # Parse denial payload
      <<result_code::little-32, _error::little-32, _days::little-float-32>> = payload

      # Result code 18 = no_realms_available
      assert result_code == 18

      :gen_tcp.close(socket)
    end
  end

  # Build a ClientHelloAuth packet payload for realm server
  defp build_client_hello_auth(build, email, game_token) do
    utf16_email = :unicode.characters_to_binary(email, :utf8, {:utf16, :little})
    email_length = String.length(email)
    uuid_1 = :crypto.strong_rand_bytes(16)

    <<
      build::little-32,
      0x1588::little-64,  # crypt_key_integer
      email_length::little-32,
      utf16_email::binary,
      uuid_1::binary-size(16),
      game_token::binary-size(16),
      0::little-32,  # inet_address
      0::little-32,  # language
      0::little-32,  # game_mode
      0::little-32,  # unused
      0::little-32   # datacenter_id
    >>
  end
end
