defmodule BezgelorWorld.Integration.CharacterFlowTest do
  @moduledoc """
  Integration test for the world server character management flow.

  Tests the complete client-server interaction:
  1. Connect to world server
  2. Receive ServerHello
  3. Send ClientHelloRealm with session key
  4. Receive ServerCharacterList
  5. Create a character
  6. Delete a character
  """

  use ExUnit.Case, async: false

  alias BezgelorDb.{Accounts, Characters, Repo}
  alias BezgelorProtocol.{Framing, Opcode, TcpListener}

  @moduletag :integration

  # Use a high ephemeral port for testing
  @test_port 46602

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
           handler_opts: [connection_type: :world],
           name: :test_world_listener
         ) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    # Wait for server to be ready
    :timer.sleep(100)

    on_exit(fn ->
      TcpListener.stop(:test_world_listener)
    end)

    :ok
  end

  setup do
    # Checkout a database connection
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    :ok
  end

  describe "world authentication flow" do
    test "successful connection receives ServerHello" do
      {:ok, socket} = :gen_tcp.connect(~c"localhost", @test_port, [:binary, active: false])

      # Should receive ServerHello packet
      {:ok, data} = :gen_tcp.recv(socket, 0, 5000)
      assert byte_size(data) > 6

      # Parse the packet header
      <<_size::little-32, opcode::little-16, _payload::binary>> = data

      # Verify it's a ServerHello
      assert {:ok, :server_hello} = Opcode.from_integer(opcode)

      :gen_tcp.close(socket)
    end

    test "auth with valid session key receives character list" do
      # Create account with session key
      email = "world_test#{System.unique_integer([:positive])}@test.com"
      {:ok, account} = Accounts.create_account(email, "password123")
      session_key = BezgelorCrypto.Random.bytes(16)
      session_key_hex = Base.encode16(session_key)
      {:ok, _account} = Accounts.update_session_key(account, session_key_hex)

      {:ok, socket} = :gen_tcp.connect(~c"localhost", @test_port, [:binary, active: false])

      # Receive and discard ServerHello
      {:ok, _hello} = :gen_tcp.recv(socket, 0, 5000)

      # Send ClientHelloRealm with session key
      auth_packet = build_client_hello_realm(account.id, session_key, email)
      framed = Framing.frame_packet(Opcode.to_integer(:client_hello_realm), auth_packet)
      :ok = :gen_tcp.send(socket, framed)

      # Should receive ServerCharacterList
      {:ok, response_data} = :gen_tcp.recv(socket, 0, 5000)

      # Parse response
      <<_size::little-32, opcode::little-16, payload::binary>> = response_data

      assert {:ok, :server_character_list} = Opcode.from_integer(opcode)

      # Parse character list header
      <<max_chars::little-32, count::little-32, _rest::binary>> = payload
      assert max_chars == 12
      assert count == 0

      :gen_tcp.close(socket)
    end

    test "auth with invalid session key disconnects" do
      {:ok, socket} = :gen_tcp.connect(~c"localhost", @test_port, [:binary, active: false])

      # Receive and discard ServerHello
      {:ok, _hello} = :gen_tcp.recv(socket, 0, 5000)

      # Send ClientHelloRealm with invalid session key
      auth_packet = build_client_hello_realm(999_999, :crypto.strong_rand_bytes(16), "invalid@test.com")
      framed = Framing.frame_packet(Opcode.to_integer(:client_hello_realm), auth_packet)
      :ok = :gen_tcp.send(socket, framed)

      # Should receive connection closed or no response
      result = :gen_tcp.recv(socket, 0, 1000)
      assert result == {:error, :closed} or result == {:error, :timeout}

      :gen_tcp.close(socket)
    end

    test "auth receives existing characters" do
      # Create account with session key and characters
      email = "char_test#{System.unique_integer([:positive])}@test.com"
      {:ok, account} = Accounts.create_account(email, "password123")
      session_key = BezgelorCrypto.Random.bytes(16)
      session_key_hex = Base.encode16(session_key)
      {:ok, _account} = Accounts.update_session_key(account, session_key_hex)

      # Create a character
      {:ok, _character} =
        Characters.create_character(
          account.id,
          %{
            name: "TestChar#{System.unique_integer([:positive])}",
            sex: 0,
            race: 0,
            class: 0,
            faction_id: 166,
            world_id: 870,
            world_zone_id: 1
          },
          %{hair_style: 5}
        )

      {:ok, socket} = :gen_tcp.connect(~c"localhost", @test_port, [:binary, active: false])

      # Receive and discard ServerHello
      {:ok, _hello} = :gen_tcp.recv(socket, 0, 5000)

      # Send ClientHelloRealm
      auth_packet = build_client_hello_realm(account.id, session_key, email)
      framed = Framing.frame_packet(Opcode.to_integer(:client_hello_realm), auth_packet)
      :ok = :gen_tcp.send(socket, framed)

      # Should receive ServerCharacterList with 1 character
      {:ok, response_data} = :gen_tcp.recv(socket, 0, 5000)

      <<_size::little-32, opcode::little-16, payload::binary>> = response_data
      assert {:ok, :server_character_list} = Opcode.from_integer(opcode)

      # Parse character list
      <<max_chars::little-32, count::little-32, _rest::binary>> = payload
      assert max_chars == 12
      assert count == 1

      :gen_tcp.close(socket)
    end
  end

  describe "character creation flow" do
    test "can create a character via packet" do
      # Create account with session key
      email = "create_test#{System.unique_integer([:positive])}@test.com"
      {:ok, account} = Accounts.create_account(email, "password123")
      session_key = BezgelorCrypto.Random.bytes(16)
      session_key_hex = Base.encode16(session_key)
      {:ok, _account} = Accounts.update_session_key(account, session_key_hex)

      {:ok, socket} = :gen_tcp.connect(~c"localhost", @test_port, [:binary, active: false])

      # Authenticate first
      {:ok, _hello} = :gen_tcp.recv(socket, 0, 5000)
      auth_packet = build_client_hello_realm(account.id, session_key, email)
      framed = Framing.frame_packet(Opcode.to_integer(:client_hello_realm), auth_packet)
      :ok = :gen_tcp.send(socket, framed)
      {:ok, _char_list} = :gen_tcp.recv(socket, 0, 5000)

      # Create a character
      char_name = "NewHero#{System.unique_integer([:positive])}"
      create_packet = build_client_character_create(char_name, 0, 0, 0, 2)
      framed = Framing.frame_packet(Opcode.to_integer(:client_character_create), create_packet)
      :ok = :gen_tcp.send(socket, framed)

      # Should receive ServerCharacterCreate with success
      {:ok, response_data} = :gen_tcp.recv(socket, 0, 5000)

      <<_size::little-32, opcode::little-16, payload::binary>> = response_data
      assert {:ok, :server_character_create} = Opcode.from_integer(opcode)

      # Parse result
      <<result::little-32, char_id::little-64>> = payload
      assert result == 0
      assert char_id > 0

      :gen_tcp.close(socket)
    end
  end

  # Helper to build ClientHelloRealm packet
  defp build_client_hello_realm(account_id, session_key, email) do
    utf16_email = :unicode.characters_to_binary(email, :utf8, {:utf16, :little})
    email_length = String.length(email)

    <<
      account_id::little-32,
      session_key::binary-size(16),
      email_length::little-32,
      utf16_email::binary
    >>
  end

  # Helper to build ClientCharacterCreate packet
  defp build_client_character_create(name, sex, race, class, path) do
    utf16_name = :unicode.characters_to_binary(name, :utf8, {:utf16, :little})
    name_length = String.length(name)

    # Build appearance data (all defaults)
    appearance = <<
      0::little-32,
      0::little-32,
      0::little-32,
      0::little-32,
      0::little-32,
      0::little-32,
      0::little-32,
      0::little-32,
      0::little-32,
      0::little-32,
      0::little-32,
      0::little-32,
      0::little-32,
      0::little-32,
      0::little-32,
      0::little-32,
      0::little-32,
      0::little-32
    >>

    <<
      name_length::little-32,
      utf16_name::binary,
      sex::little-32,
      race::little-32,
      class::little-32,
      path::little-32
    >> <> appearance
  end
end
