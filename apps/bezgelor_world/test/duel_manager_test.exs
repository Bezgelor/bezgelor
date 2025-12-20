defmodule BezgelorWorld.DuelManagerTest do
  use ExUnit.Case, async: true

  alias BezgelorWorld.PvP.DuelManager

  # Use unique GUIDs per test to avoid conflicts with other tests
  defp unique_guid(base) do
    base + :erlang.unique_integer([:positive]) * 10000
  end

  defp test_position, do: {100.0, 50.0, 200.0}

  setup do
    # Generate unique GUIDs for this test to avoid interference
    challenger_guid = unique_guid(1000)
    target_guid = unique_guid(2000)

    # Ensure DuelManager is started (may already be running from app)
    case GenServer.whereis(DuelManager) do
      nil ->
        {:ok, _pid} = DuelManager.start_link([])

      _pid ->
        :ok
    end

    {:ok,
     challenger_guid: challenger_guid,
     challenger_name: "Challenger#{challenger_guid}",
     target_guid: target_guid,
     target_name: "Target#{target_guid}"}
  end

  describe "request_duel/5" do
    test "creates a duel request", ctx do
      assert {:ok, duel_id} =
               DuelManager.request_duel(
                 ctx.challenger_guid,
                 ctx.challenger_name,
                 ctx.target_guid,
                 ctx.target_name,
                 test_position()
               )

      assert is_binary(duel_id)
      assert String.length(duel_id) == 16
    end

    test "prevents challenger from starting multiple duels", ctx do
      {:ok, _duel_id} =
        DuelManager.request_duel(
          ctx.challenger_guid,
          ctx.challenger_name,
          ctx.target_guid,
          ctx.target_name,
          test_position()
        )

      # Accept the duel to move it to active
      DuelManager.respond_to_duel(ctx.target_guid, ctx.challenger_guid, true)

      # Wait for countdown to complete
      Process.sleep(5500)

      # Now try to start another duel
      other_guid = unique_guid(3000)

      assert {:error, :already_in_duel} =
               DuelManager.request_duel(
                 ctx.challenger_guid,
                 ctx.challenger_name,
                 other_guid,
                 "Other",
                 test_position()
               )
    end

    test "prevents challenging player already in duel", ctx do
      # Player A challenges Player B
      {:ok, _} =
        DuelManager.request_duel(
          ctx.challenger_guid,
          ctx.challenger_name,
          ctx.target_guid,
          ctx.target_name,
          test_position()
        )

      DuelManager.respond_to_duel(ctx.target_guid, ctx.challenger_guid, true)
      Process.sleep(5500)

      # Player C tries to challenge Player B (who is in duel)
      third_guid = unique_guid(3000)

      assert {:error, :target_in_duel} =
               DuelManager.request_duel(
                 third_guid,
                 "Third",
                 ctx.target_guid,
                 ctx.target_name,
                 test_position()
               )
    end

    test "prevents multiple pending requests to same target", ctx do
      {:ok, _} =
        DuelManager.request_duel(
          ctx.challenger_guid,
          ctx.challenger_name,
          ctx.target_guid,
          ctx.target_name,
          test_position()
        )

      another_guid = unique_guid(3000)

      assert {:error, :target_has_pending_request} =
               DuelManager.request_duel(
                 another_guid,
                 "Another",
                 ctx.target_guid,
                 ctx.target_name,
                 test_position()
               )
    end
  end

  describe "respond_to_duel/3" do
    test "accepting duel starts countdown", ctx do
      {:ok, _duel_id} =
        DuelManager.request_duel(
          ctx.challenger_guid,
          ctx.challenger_name,
          ctx.target_guid,
          ctx.target_name,
          test_position()
        )

      assert {:ok, duel} = DuelManager.respond_to_duel(ctx.target_guid, ctx.challenger_guid, true)
      assert duel.state == :countdown
      assert duel.challenger_guid == ctx.challenger_guid
      assert duel.target_guid == ctx.target_guid
    end

    test "declining removes pending duel", ctx do
      {:ok, _duel_id} =
        DuelManager.request_duel(
          ctx.challenger_guid,
          ctx.challenger_name,
          ctx.target_guid,
          ctx.target_name,
          test_position()
        )

      assert {:ok, :declined} =
               DuelManager.respond_to_duel(ctx.target_guid, ctx.challenger_guid, false)

      # Target should now be able to receive new requests
      new_challenger = unique_guid(3000)

      {:ok, _} =
        DuelManager.request_duel(
          new_challenger,
          "NewChallenger",
          ctx.target_guid,
          ctx.target_name,
          test_position()
        )
    end

    test "returns error for non-existent request", ctx do
      assert {:error, :no_pending_request} =
               DuelManager.respond_to_duel(ctx.target_guid, ctx.challenger_guid, true)
    end

    test "returns error for wrong challenger", ctx do
      {:ok, _} =
        DuelManager.request_duel(
          ctx.challenger_guid,
          ctx.challenger_name,
          ctx.target_guid,
          ctx.target_name,
          test_position()
        )

      wrong_challenger = unique_guid(9000)

      assert {:error, :wrong_challenger} =
               DuelManager.respond_to_duel(ctx.target_guid, wrong_challenger, true)
    end
  end

  describe "cancel_request/2" do
    test "cancels pending request", ctx do
      {:ok, _} =
        DuelManager.request_duel(
          ctx.challenger_guid,
          ctx.challenger_name,
          ctx.target_guid,
          ctx.target_name,
          test_position()
        )

      assert :ok = DuelManager.cancel_request(ctx.challenger_guid, ctx.target_guid)

      # Should be able to create new request after cancel
      {:ok, _} =
        DuelManager.request_duel(
          ctx.challenger_guid,
          ctx.challenger_name,
          ctx.target_guid,
          ctx.target_name,
          test_position()
        )
    end

    test "returns error for non-existent request", ctx do
      assert {:error, :no_pending_request} =
               DuelManager.cancel_request(ctx.challenger_guid, ctx.target_guid)
    end
  end

  describe "forfeit_duel/1" do
    test "forfeiting ends active duel", ctx do
      {:ok, _} =
        DuelManager.request_duel(
          ctx.challenger_guid,
          ctx.challenger_name,
          ctx.target_guid,
          ctx.target_name,
          test_position()
        )

      DuelManager.respond_to_duel(ctx.target_guid, ctx.challenger_guid, true)

      # Wait for countdown to complete and duel to become active
      Process.sleep(5500)

      assert {:ok, duel} = DuelManager.forfeit_duel(ctx.challenger_guid)
      assert duel.state == :ended
      assert duel.winner_guid == ctx.target_guid
      assert duel.loser_guid == ctx.challenger_guid
      assert duel.end_reason == :forfeit
    end

    test "returns error when not in duel", ctx do
      assert {:error, :not_in_duel} = DuelManager.forfeit_duel(ctx.challenger_guid)
    end
  end

  describe "in_duel?/1" do
    test "returns false when not in duel", ctx do
      assert DuelManager.in_duel?(ctx.challenger_guid) == false
    end

    test "returns true during active duel", ctx do
      {:ok, _} =
        DuelManager.request_duel(
          ctx.challenger_guid,
          ctx.challenger_name,
          ctx.target_guid,
          ctx.target_name,
          test_position()
        )

      DuelManager.respond_to_duel(ctx.target_guid, ctx.challenger_guid, true)
      Process.sleep(5500)

      assert DuelManager.in_duel?(ctx.challenger_guid) == true
      assert DuelManager.in_duel?(ctx.target_guid) == true
    end
  end

  describe "dueling_each_other?/2" do
    test "returns false when not dueling", ctx do
      assert DuelManager.dueling_each_other?(ctx.challenger_guid, ctx.target_guid) == false
    end

    test "returns true during active duel", ctx do
      {:ok, _} =
        DuelManager.request_duel(
          ctx.challenger_guid,
          ctx.challenger_name,
          ctx.target_guid,
          ctx.target_name,
          test_position()
        )

      DuelManager.respond_to_duel(ctx.target_guid, ctx.challenger_guid, true)
      Process.sleep(5500)

      assert DuelManager.dueling_each_other?(ctx.challenger_guid, ctx.target_guid) == true
      assert DuelManager.dueling_each_other?(ctx.target_guid, ctx.challenger_guid) == true

      # Third party should not be dueling either
      third_guid = unique_guid(9000)
      assert DuelManager.dueling_each_other?(ctx.challenger_guid, third_guid) == false
    end
  end

  describe "report_damage/3" do
    test "returns continue when health above zero", ctx do
      {:ok, _} =
        DuelManager.request_duel(
          ctx.challenger_guid,
          ctx.challenger_name,
          ctx.target_guid,
          ctx.target_name,
          test_position()
        )

      DuelManager.respond_to_duel(ctx.target_guid, ctx.challenger_guid, true)
      Process.sleep(5500)

      assert {:ok, :continue} =
               DuelManager.report_damage(ctx.challenger_guid, ctx.target_guid, 1000)
    end

    test "ends duel when health reaches zero", ctx do
      {:ok, _} =
        DuelManager.request_duel(
          ctx.challenger_guid,
          ctx.challenger_name,
          ctx.target_guid,
          ctx.target_name,
          test_position()
        )

      DuelManager.respond_to_duel(ctx.target_guid, ctx.challenger_guid, true)
      Process.sleep(5500)

      assert {:ok, :ended, duel} =
               DuelManager.report_damage(ctx.challenger_guid, ctx.target_guid, 0)

      assert duel.winner_guid == ctx.challenger_guid
      assert duel.loser_guid == ctx.target_guid
      assert duel.end_reason == :defeat
    end

    test "returns error when not in duel", ctx do
      assert {:error, :not_in_duel} =
               DuelManager.report_damage(ctx.challenger_guid, ctx.target_guid, 0)
    end
  end

  describe "boundary checking" do
    test "player leaving boundary starts grace period", ctx do
      {:ok, _} =
        DuelManager.request_duel(
          ctx.challenger_guid,
          ctx.challenger_name,
          ctx.target_guid,
          ctx.target_name,
          test_position()
        )

      DuelManager.respond_to_duel(ctx.target_guid, ctx.challenger_guid, true)
      Process.sleep(5500)

      # Move player outside boundary (40 unit radius)
      far_position = {200.0, 50.0, 200.0}
      DuelManager.update_position(ctx.challenger_guid, far_position)

      # Player should still be in duel during grace period
      assert DuelManager.in_duel?(ctx.challenger_guid) == true
    end

    test "player returning to boundary cancels flee", ctx do
      {:ok, _} =
        DuelManager.request_duel(
          ctx.challenger_guid,
          ctx.challenger_name,
          ctx.target_guid,
          ctx.target_name,
          test_position()
        )

      DuelManager.respond_to_duel(ctx.target_guid, ctx.challenger_guid, true)
      Process.sleep(5500)

      # Move player outside boundary
      far_position = {200.0, 50.0, 200.0}
      DuelManager.update_position(ctx.challenger_guid, far_position)

      # Move back inside boundary
      DuelManager.update_position(ctx.challenger_guid, test_position())

      # Should still be in duel
      Process.sleep(6000)
      assert DuelManager.in_duel?(ctx.challenger_guid) == true
    end
  end

  describe "get_duel/1" do
    test "returns duel when in active duel", ctx do
      {:ok, _} =
        DuelManager.request_duel(
          ctx.challenger_guid,
          ctx.challenger_name,
          ctx.target_guid,
          ctx.target_name,
          test_position()
        )

      DuelManager.respond_to_duel(ctx.target_guid, ctx.challenger_guid, true)
      Process.sleep(5500)

      assert {:ok, duel} = DuelManager.get_duel(ctx.challenger_guid)
      assert duel.challenger_guid == ctx.challenger_guid
      assert duel.target_guid == ctx.target_guid
      assert duel.state == :active
    end

    test "returns error when not in duel", ctx do
      assert {:error, :not_in_duel} = DuelManager.get_duel(ctx.challenger_guid)
    end
  end
end
