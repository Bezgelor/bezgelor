defmodule BezgelorProtocol.Handler.TeleportCommandHandlerTest do
  use ExUnit.Case, async: true

  alias BezgelorProtocol.Handler.TeleportCommandHandler

  describe "handle/2" do
    setup do
      session = %{
        session_data: %{
          player_guid: 12345,
          zone_id: 1,
          instance_id: 1,
          world_id: 426,
          character: %{id: 1, name: "TestPlayer"}
        }
      }

      %{session: session}
    end

    test "parses single world location ID argument", %{session: session} do
      # This will fail because location doesn't exist, but parsing works
      assert {:error, :invalid_location} = TeleportCommandHandler.handle("999999999", session)
    end

    test "parses three coordinate arguments as cross-zone teleport when world differs", %{
      session: session
    } do
      # Change session to have world_id nil (new character state) so it becomes cross-zone
      session = put_in(session, [:session_data, :world_id], nil)

      # Cross-zone teleport doesn't require zone instance
      result = TeleportCommandHandler.handle("100.0 50.0 200.0", session)

      # Defaults to world 426 when session world_id is nil
      assert {:ok, updated_session} = result
      assert updated_session.session_data.world_id == 426
    end

    test "parses four arguments (world_id + coordinates)", %{session: session} do
      # Cross-zone teleport to new world
      result = TeleportCommandHandler.handle("1387 -3835.0 -980.0 -6050.0", session)

      # Cross-zone just updates session (no entity check)
      assert {:ok, updated_session} = result
      assert updated_session.session_data.world_id == 1387
    end

    test "returns error for invalid arguments", %{session: session} do
      assert {:error, :invalid_arguments} = TeleportCommandHandler.handle("not_a_number", session)
      assert {:error, :invalid_arguments} = TeleportCommandHandler.handle("1 2", session)
      assert {:error, :invalid_arguments} = TeleportCommandHandler.handle("", session)
    end
  end
end
