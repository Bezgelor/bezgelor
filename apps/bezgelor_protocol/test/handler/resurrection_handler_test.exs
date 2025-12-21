defmodule BezgelorProtocol.Handler.ResurrectionHandlerTest do
  use ExUnit.Case, async: false

  alias BezgelorProtocol.Handler.ResurrectionHandler
  alias BezgelorWorld.DeathManager

  @player_guid 0x1000000000000001

  setup do
    # Ensure DeathManager is running
    case GenServer.whereis(DeathManager) do
      nil -> {:ok, _} = DeathManager.start_link([])
      pid -> GenServer.call(pid, :clear_all, 5000)
    end

    state = %{
      current_opcode: :client_resurrect_accept,
      session_data: %{
        entity_guid: @player_guid,
        character_id: 1,
        account_id: 1,
        in_world: true,
        zone_id: 100
      }
    }

    %{state: state}
  end

  describe "handle/2 with :client_resurrect_accept" do
    test "accepts resurrection when player has pending offer", %{state: state} do
      # Set up player as dead with pending resurrection offer
      DeathManager.player_died(@player_guid, 100, {50.0, 10.0, 50.0}, nil)
      DeathManager.offer_resurrection(@player_guid, 0x1000000000000002, 12345, 35.0)

      # Create accept packet (accept = true)
      payload = <<1::little-8>>

      result = ResurrectionHandler.handle(payload, state)

      # Should return a reply with resurrection confirmation
      assert {:reply_world_encrypted, opcode, _payload, _new_state} = result
      assert opcode == :server_resurrect

      # Player should no longer be dead
      assert DeathManager.is_dead?(@player_guid) == false
    end

    test "returns error when player declines resurrection", %{state: state} do
      # Set up player as dead with pending resurrection offer
      DeathManager.player_died(@player_guid, 100, {50.0, 10.0, 50.0}, nil)
      DeathManager.offer_resurrection(@player_guid, 0x1000000000000002, 12345, 35.0)

      # Create decline packet (accept = false)
      payload = <<0::little-8>>

      result = ResurrectionHandler.handle(payload, state)

      # Should return ok (just acknowledge decline)
      assert {:ok, _new_state} = result

      # Player should still be dead
      assert DeathManager.is_dead?(@player_guid) == true
    end

    test "returns error when player has no pending offer", %{state: state} do
      # Set up player as dead but NO resurrection offer
      DeathManager.player_died(@player_guid, 100, {50.0, 10.0, 50.0}, nil)

      # Try to accept (but no offer exists)
      payload = <<1::little-8>>

      result = ResurrectionHandler.handle(payload, state)

      assert {:error, :no_offer} = result
    end

    test "returns error when player is not dead", %{state: state} do
      # Player is NOT dead
      payload = <<1::little-8>>

      result = ResurrectionHandler.handle(payload, state)

      # Should fail because player isn't dead
      assert {:error, _reason} = result
    end
  end
end
