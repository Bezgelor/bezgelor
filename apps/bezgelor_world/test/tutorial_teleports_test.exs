defmodule BezgelorWorld.TutorialTeleportsTest do
  use ExUnit.Case, async: true

  alias BezgelorWorld.TutorialTeleports

  describe "check_teleport/2" do
    test "returns :no_teleport for unknown trigger" do
      session_data = %{active_quests: %{}}
      assert TutorialTeleports.check_teleport(session_data, 999_999) == :no_teleport
    end

    test "get_all_teleports returns the configured teleports" do
      teleports = TutorialTeleports.get_all_teleports()
      assert is_list(teleports)
    end

    test "is_teleport_trigger? returns false for unknown trigger" do
      refute TutorialTeleports.is_teleport_trigger?(999_999)
    end
  end

  describe "maybe_teleport/2" do
    test "returns unchanged session for non-teleport trigger" do
      session_data = %{active_quests: %{}}
      {result_session, packets} = TutorialTeleports.maybe_teleport(session_data, 999_999)

      assert result_session == session_data
      assert packets == []
    end
  end
end
