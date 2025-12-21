defmodule BezgelorWorld.Handler.SpellHandlerBuffTest do
  use ExUnit.Case, async: false

  alias BezgelorWorld.{SpellManager, BuffManager}
  alias BezgelorWorld.Handler.SpellHandler
  alias BezgelorCore.Spell

  setup do
    # Ensure managers are running
    ensure_started(SpellManager)
    ensure_started(BuffManager)

    # Clear state
    BuffManager.clear_entity(12345)
    SpellManager.clear_player(12345)

    :ok
  end

  defp ensure_started(module) do
    case GenServer.whereis(module) do
      nil -> start_supervised!(module)
      _pid -> :already_running
    end
  end

  # Build ClientCastSpell binary payload:
  # spell_id: uint32, target_guid: uint64, x: float32, y: float32, z: float32
  defp build_cast_spell_payload(spell_id, target_guid) do
    <<spell_id::little-unsigned-32, target_guid::little-unsigned-64, 0.0::little-float-32,
      0.0::little-float-32, 0.0::little-float-32>>
  end

  describe "buff effect application" do
    test "casting Shield spell via SpellHandler applies absorb buff via BuffManager" do
      player_guid = 12345

      # Verify Shield spell exists with buff effect
      spell = Spell.get(4)
      assert spell.name == "Shield"
      assert hd(spell.effects).type == :buff

      # Build the ClientCastSpell packet payload (Shield spell targeting self)
      payload = build_cast_spell_payload(4, player_guid)

      # Create state simulating player in world
      state = %{
        session_data: %{
          in_world: true,
          entity_guid: player_guid,
          entity: nil
        }
      }

      # Call SpellHandler.handle directly
      {:reply, _opcode, _packet_data, _new_state} = SpellHandler.handle(payload, state)

      # Verify buff was applied via BuffManager
      assert BuffManager.has_buff?(player_guid, 4)

      # Verify absorb is available
      {absorbed, _remaining} = BuffManager.consume_absorb(player_guid, 50)
      assert absorbed == 50
    end

    test "buff is removed after duration expires" do
      player_guid = 12345

      # Apply a short-duration buff directly for testing
      buff =
        BezgelorCore.BuffDebuff.new(%{
          id: 999,
          spell_id: 999,
          buff_type: :absorb,
          amount: 100,
          duration: 50
        })

      {:ok, _} = BuffManager.apply_buff(player_guid, buff, player_guid)
      assert BuffManager.has_buff?(player_guid, 999)

      # Wait for expiration
      Process.sleep(100)

      refute BuffManager.has_buff?(player_guid, 999)
    end
  end
end
