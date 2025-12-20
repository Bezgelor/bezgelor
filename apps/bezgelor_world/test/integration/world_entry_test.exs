defmodule BezgelorWorld.Integration.WorldEntryTest do
  @moduledoc """
  Integration test for the world entry flow.

  Tests the complete flow from character selection to world entry:
  1. Connect and authenticate to world server
  2. Select a character
  3. Receive ServerWorldEnter
  4. Send ClientEnteredWorld
  5. Receive ServerEntityCreate
  6. Send movement updates
  """

  use ExUnit.Case, async: false

  alias BezgelorDb.{Accounts, Characters, Repo}
  alias BezgelorProtocol.{Framing, Opcode, TcpListener}

  @moduletag :integration

  # Use a high ephemeral port for testing
  @test_port 46603

  setup_all do
    # Start the packet registry
    case BezgelorProtocol.PacketRegistry.start_link([]) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    # Start the WorldManager
    case BezgelorWorld.WorldManager.start_link([]) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    # Start the TCP listener directly
    case TcpListener.start_link(
           port: @test_port,
           handler: BezgelorProtocol.Connection,
           handler_opts: [connection_type: :world],
           name: :test_world_entry_listener
         ) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    # Wait for server to be ready
    :timer.sleep(100)

    on_exit(fn ->
      TcpListener.stop(:test_world_entry_listener)
    end)

    :ok
  end

  setup do
    # Checkout a database connection
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    :ok
  end

  describe "world entry flow" do
    test "character select sends ServerWorldEnter" do
      # Create account, session key, and character
      {socket, _account, character} = setup_authenticated_client()

      # Send ClientCharacterSelect
      select_packet = build_client_character_select(character.id)
      framed = Framing.frame_packet(Opcode.to_integer(:client_character_select), select_packet)
      :ok = :gen_tcp.send(socket, framed)

      # Should receive ServerWorldEnter
      {:ok, response_data} = :gen_tcp.recv(socket, 0, 5000)

      # Parse response
      <<_size::little-32, opcode::little-16, payload::binary>> = response_data

      assert {:ok, :server_world_enter} = Opcode.from_integer(opcode)

      # Parse world enter packet
      <<
        char_id::little-64,
        world_id::little-32,
        zone_id::little-32,
        _pos_x::little-float-32,
        _pos_y::little-float-32,
        _pos_z::little-float-32,
        _rot_x::little-float-32,
        _rot_y::little-float-32,
        _rot_z::little-float-32,
        _time::little-32,
        _weather::little-32
      >> = payload

      assert char_id == character.id
      assert world_id == character.world_id
      assert zone_id == character.world_zone_id

      :gen_tcp.close(socket)
    end

    test "ClientEnteredWorld spawns player entity" do
      # Create account, session key, and character
      {socket, _account, character} = setup_authenticated_client()

      # Select character
      select_packet = build_client_character_select(character.id)
      framed = Framing.frame_packet(Opcode.to_integer(:client_character_select), select_packet)
      :ok = :gen_tcp.send(socket, framed)

      # Receive ServerWorldEnter
      {:ok, _world_enter} = :gen_tcp.recv(socket, 0, 5000)

      # Send ClientEnteredWorld (empty payload)
      entered_packet = <<>>
      framed = Framing.frame_packet(Opcode.to_integer(:client_entered_world), entered_packet)
      :ok = :gen_tcp.send(socket, framed)

      # Should receive ServerEntityCreate
      {:ok, response_data} = :gen_tcp.recv(socket, 0, 5000)

      # Parse response
      <<_size::little-32, opcode::little-16, payload::binary>> = response_data

      assert {:ok, :server_entity_create} = Opcode.from_integer(opcode)

      # Parse entity create packet
      <<
        guid::little-64,
        entity_type::little-32,
        _rest::binary
      >> = payload

      assert guid > 0
      # player
      assert entity_type == 1

      :gen_tcp.close(socket)
    end

    test "movement updates are accepted" do
      # Create account, session key, and character
      {socket, _account, character} = setup_authenticated_client()

      # Complete world entry
      select_packet = build_client_character_select(character.id)
      framed = Framing.frame_packet(Opcode.to_integer(:client_character_select), select_packet)
      :ok = :gen_tcp.send(socket, framed)
      {:ok, _world_enter} = :gen_tcp.recv(socket, 0, 5000)

      entered_packet = <<>>
      framed = Framing.frame_packet(Opcode.to_integer(:client_entered_world), entered_packet)
      :ok = :gen_tcp.send(socket, framed)
      {:ok, _entity_create} = :gen_tcp.recv(socket, 0, 5000)

      # Send movement packet
      movement_packet = build_client_movement(100.0, 200.0, 300.0)
      framed = Framing.frame_packet(Opcode.to_integer(:client_movement), movement_packet)
      :ok = :gen_tcp.send(socket, framed)

      # Movement doesn't send a response, but connection should stay open
      # Wait briefly and verify connection is still alive
      :timer.sleep(100)

      # Try to send another movement - if connection closed, this will fail
      movement_packet2 = build_client_movement(110.0, 210.0, 310.0)
      framed = Framing.frame_packet(Opcode.to_integer(:client_movement), movement_packet2)
      result = :gen_tcp.send(socket, framed)
      assert result == :ok

      :gen_tcp.close(socket)
    end
  end

  # Helper functions

  defp setup_authenticated_client do
    # Create account with session key
    email = "world_entry_test#{System.unique_integer([:positive])}@test.com"
    {:ok, account} = Accounts.create_account(email, "password123")
    session_key = BezgelorCrypto.Random.bytes(16)
    session_key_hex = Base.encode16(session_key)
    {:ok, account} = Accounts.update_session_key(account, session_key_hex)

    # Create a character
    {:ok, character} =
      Characters.create_character(
        account.id,
        %{
          name: "WorldEntry#{System.unique_integer([:positive])}",
          sex: 0,
          race: 0,
          class: 0,
          faction_id: 166,
          world_id: 870,
          world_zone_id: 1
        },
        %{hair_style: 5}
      )

    # Connect to server
    {:ok, socket} = :gen_tcp.connect(~c"localhost", @test_port, [:binary, active: false])

    # Receive and discard ServerHello
    {:ok, _hello} = :gen_tcp.recv(socket, 0, 5000)

    # Send ClientHelloRealm
    auth_packet = build_client_hello_realm(account.id, session_key, email)
    framed = Framing.frame_packet(Opcode.to_integer(:client_hello_realm), auth_packet)
    :ok = :gen_tcp.send(socket, framed)

    # Receive and discard ServerCharacterList
    {:ok, _char_list} = :gen_tcp.recv(socket, 0, 5000)

    {socket, account, character}
  end

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

  defp build_client_character_select(character_id) do
    <<character_id::little-64>>
  end

  defp build_client_movement(pos_x, pos_y, pos_z) do
    <<
      pos_x::little-float-32,
      pos_y::little-float-32,
      pos_z::little-float-32,
      # rotation_x
      0.0::little-float-32,
      # rotation_y
      0.0::little-float-32,
      # rotation_z
      0.0::little-float-32,
      # velocity_x
      0.0::little-float-32,
      # velocity_y
      0.0::little-float-32,
      # velocity_z
      0.0::little-float-32,
      # movement_flags
      0::little-32,
      # timestamp
      0::little-32
    >>
  end
end
