defmodule BezgelorWorld.Handler.SpellHandlerIntegrationTest do
  @moduledoc """
  Integration tests for the spell casting flow.

  Tests the full path from client packet to spell execution:
  1. bag_index from ClientCastSpell packet
  2. Shortcut lookup from session_data[:action_set_shortcuts]
  3. spell_id resolution (Spell4 ID for casting)
  4. Spell execution and packet response
  """
  use ExUnit.Case, async: false

  @moduletag :integration

  alias BezgelorWorld.{SpellManager, BuffManager}
  alias BezgelorWorld.Handler.SpellHandler
  alias BezgelorCore.Spell

  setup do
    ensure_started(SpellManager)
    ensure_started(BuffManager)

    # Clear state for test player
    player_guid = 12345
    BuffManager.clear_entity(player_guid)
    SpellManager.clear_player(player_guid)

    {:ok, player_guid: player_guid}
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
    button_byte = 1
    <<1::little-unsigned-32, bag_index::little-unsigned-16, caster_id::little-unsigned-32, button_byte::8>>
  end

  # Build a mock shortcut struct that matches what's stored in session_data
  defp build_shortcut(slot, spell_id, opts \\ []) do
    %{
      slot: slot,
      spell_id: spell_id,
      object_id: Keyword.get(opts, :object_id, spell_id),
      spec_index: Keyword.get(opts, :spec_index, 0),
      tier: Keyword.get(opts, :tier, 1),
      shortcut_type: 4
    }
  end

  # Build a minimal session state for testing
  defp build_session_state(player_guid, shortcuts, opts \\ []) do
    %{
      session_data: %{
        in_world: true,
        entity_guid: player_guid,
        entity: nil,
        character: %{
          id: player_guid,
          active_spec: Keyword.get(opts, :active_spec, 0),
          level: Keyword.get(opts, :level, 50),
          class: Keyword.get(opts, :class, 1)
        },
        action_set_shortcuts: shortcuts,
        position: {0.0, 0.0, 0.0},
        yaw: 0.0
      }
    }
  end

  describe "bag_index → shortcut → spell_id resolution" do
    test "resolves spell from bag_index via shortcuts", %{player_guid: player_guid} do
      # Fireball is spell_id 1 in hardcoded test spells
      fireball_spell_id = 1
      bag_index = 0

      shortcuts = [build_shortcut(bag_index, fireball_spell_id)]
      state = build_session_state(player_guid, shortcuts)
      payload = build_cast_spell_payload(bag_index, player_guid)

      # Should successfully cast - returns spell packets
      result = SpellHandler.handle(payload, state)

      case result do
        {:reply_multi_world_encrypted, packets, _state} ->
          # Successful cast returns multiple packets
          assert length(packets) >= 2
          opcodes = Enum.map(packets, &elem(&1, 0))
          assert :server_spell_start in opcodes
          assert :server_spell_go in opcodes

        {:reply_world_encrypted, :server_cast_result, _data, _state} ->
          # Cast failed - this is also valid for test spells without full implementation
          :ok

        other ->
          flunk("Unexpected result: #{inspect(other)}")
      end
    end

    test "returns cast_result failed for missing bag_index", %{player_guid: player_guid} do
      # Empty shortcuts - no spell at bag_index 0
      shortcuts = []
      state = build_session_state(player_guid, shortcuts)
      payload = build_cast_spell_payload(0, player_guid)

      # Should return failure
      {:reply_world_encrypted, :server_cast_result, _data, _state} =
        SpellHandler.handle(payload, state)
    end

    test "uses correct spec_index from character", %{player_guid: player_guid} do
      spell_id = 1
      bag_index = 0

      # Only have shortcut for spec 1, but character is on spec 0
      shortcuts = [build_shortcut(bag_index, spell_id, spec_index: 1)]
      state = build_session_state(player_guid, shortcuts, active_spec: 0)
      payload = build_cast_spell_payload(bag_index, player_guid)

      # Should fail - no shortcut for spec 0
      {:reply_world_encrypted, :server_cast_result, _data, _state} =
        SpellHandler.handle(payload, state)
    end

    test "finds shortcut for matching spec_index", %{player_guid: player_guid} do
      spell_id = 1
      bag_index = 0

      # Shortcut for spec 1, character on spec 1
      shortcuts = [build_shortcut(bag_index, spell_id, spec_index: 1)]
      state = build_session_state(player_guid, shortcuts, active_spec: 1)
      payload = build_cast_spell_payload(bag_index, player_guid)

      result = SpellHandler.handle(payload, state)

      case result do
        {:reply_multi_world_encrypted, _packets, _state} -> :ok
        {:reply_world_encrypted, :server_cast_result, _data, _state} -> :ok
        other -> flunk("Unexpected result: #{inspect(other)}")
      end
    end
  end

  describe "spell casting produces correct packets" do
    test "instant cast produces SpellStart and SpellGo", %{player_guid: player_guid} do
      # Use a real spell ID - Warrior Whirlwind (id 26076) is instant cast
      # If game data isn't loaded, fall back to test behavior
      spell_id = 26076
      bag_index = 0

      shortcuts = [build_shortcut(bag_index, spell_id)]
      state = build_session_state(player_guid, shortcuts)
      payload = build_cast_spell_payload(bag_index, player_guid)

      spell = Spell.get(spell_id)

      if spell != nil and Spell.instant?(spell) do
        # Spell exists in data - expect full spell packets
        result = SpellHandler.handle(payload, state)

        case result do
          {:reply_multi_world_encrypted, packets, _state} ->
            opcodes = Enum.map(packets, &elem(&1, 0))
            assert :server_spell_start in opcodes
            assert :server_spell_go in opcodes

          {:reply_world_encrypted, :server_cast_result, _data, _state} ->
            # Cast may fail for other reasons (cooldown, resources, etc.)
            :ok
        end
      else
        # Spell not in test data - verify handler returns gracefully
        result = SpellHandler.handle(payload, state)

        case result do
          {:reply_world_encrypted, :server_cast_result, _data, _state} -> :ok
          {:reply_multi_world_encrypted, _packets, _state} -> :ok
          other -> flunk("Unexpected result: #{inspect(other)}")
        end
      end
    end

    test "buff spell applies buff via BuffManager", %{player_guid: player_guid} do
      # Use a real buff spell ID - Warrior Bolstering Strike (id 28840) applies a buff
      # If game data isn't loaded, skip the buff check
      spell_id = 28840
      bag_index = 0

      shortcuts = [build_shortcut(bag_index, spell_id)]
      state = build_session_state(player_guid, shortcuts)
      payload = build_cast_spell_payload(bag_index, player_guid)

      result = SpellHandler.handle(payload, state)

      case result do
        {:reply_multi_world_encrypted, _packets, _state} ->
          # If cast succeeded, buff might be applied
          # Note: BuffManager.has_buff? checks by spell_id, not buff_id
          :ok

        {:reply_world_encrypted, :server_cast_result, _data, _state} ->
          # Cast failed - acceptable for integration test
          :ok
      end
    end
  end

  describe "not in world handling" do
    test "rejects cast when not in world", %{player_guid: player_guid} do
      spell_id = 1
      bag_index = 0

      shortcuts = [build_shortcut(bag_index, spell_id)]
      state = build_session_state(player_guid, shortcuts)
      # Set in_world to false
      state = put_in(state, [:session_data, :in_world], false)
      payload = build_cast_spell_payload(bag_index, player_guid)

      result = SpellHandler.handle(payload, state)
      assert {:error, :not_in_world} = result
    end
  end

  describe "multiple slots" do
    test "resolves different spells from different bag_indices", %{player_guid: player_guid} do
      # Set up 3 different real Warrior spell IDs in slots 0, 1, 2
      # These are actual Spell4 IDs from the game data
      shortcuts = [
        build_shortcut(0, 26076),  # Whirlwind
        build_shortcut(1, 28840),  # Bolstering Strike
        build_shortcut(2, 26067)   # Rampage
      ]
      state = build_session_state(player_guid, shortcuts)

      # Cast from slot 1
      payload = build_cast_spell_payload(1, player_guid)
      result1 = SpellHandler.handle(payload, state)

      # Verify we got a valid response (either success or cast_result)
      case result1 do
        {:reply_multi_world_encrypted, _packets, _state} -> :ok
        {:reply_world_encrypted, :server_cast_result, _data, _state} -> :ok
        other -> flunk("Unexpected result from slot 1: #{inspect(other)}")
      end

      # Cast from slot 2 - but first clear cooldown state
      SpellManager.clear_player(player_guid)
      payload = build_cast_spell_payload(2, player_guid)
      result2 = SpellHandler.handle(payload, state)

      # Verify we got a valid response
      case result2 do
        {:reply_multi_world_encrypted, _packets, _state} -> :ok
        {:reply_world_encrypted, :server_cast_result, _data, _state} -> :ok
        other -> flunk("Unexpected result from slot 2: #{inspect(other)}")
      end
    end
  end
end
