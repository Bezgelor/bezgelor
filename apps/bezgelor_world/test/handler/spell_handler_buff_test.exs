defmodule BezgelorWorld.Handler.SpellHandlerBuffTest do
  use ExUnit.Case, async: false

  @moduletag :integration

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

  # Build ClientCastSpell binary payload matching the actual packet format:
  # client_unique_id: uint32, bag_index: uint16, caster_id: uint32, button_pressed: 1 bit
  defp build_cast_spell_payload(bag_index, caster_id) do
    # The button_pressed bit needs to be packed - we'll write a byte with bit set
    button_byte = 1
    <<1::little-unsigned-32, bag_index::little-unsigned-16, caster_id::little-unsigned-32, button_byte::8>>
  end

  # Build a mock shortcut struct that matches what's stored in session_data
  defp build_shortcut(slot, spell_id, spec_index \\ 0) do
    %{slot: slot, spell_id: spell_id, spec_index: spec_index}
  end

  describe "buff effect application" do
    test "casting Shield spell via SpellHandler applies absorb buff via BuffManager" do
      player_guid = 12345
      shield_spell_id = 4
      bag_index = 0

      # Verify Shield spell exists with buff effect
      spell = Spell.get(shield_spell_id)
      assert spell.name == "Shield"
      assert hd(spell.effects).type == :buff

      # Build the ClientCastSpell packet payload
      # Using bag_index 0 which will be resolved via action_set_shortcuts
      payload = build_cast_spell_payload(bag_index, player_guid)

      # Create state simulating player in world with action_set_shortcuts
      state = %{
        session_data: %{
          in_world: true,
          entity_guid: player_guid,
          entity: nil,
          character: %{active_spec: 0, level: 50, class: 1},
          action_set_shortcuts: [
            build_shortcut(bag_index, shield_spell_id)
          ]
        }
      }

      # Call SpellHandler.handle directly
      # Note: spell casting now returns multiple packets (SpellStart + SpellGo)
      {:reply_multi_world_encrypted, _packets, _new_state} = SpellHandler.handle(payload, state)

      # Verify buff was applied via BuffManager
      assert BuffManager.has_buff?(player_guid, shield_spell_id)

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
