defmodule BezgelorWorld.TutorialTeleportsTest do
  use ExUnit.Case, async: true

  alias BezgelorWorld.TutorialTeleports

  describe "get_teleport_for_quest/1" do
    test "returns :none for unconfigured quest" do
      assert TutorialTeleports.get_teleport_for_quest(999_999) == :none
    end
  end

  describe "has_teleport_reward?/1" do
    test "returns false for unconfigured quest" do
      refute TutorialTeleports.has_teleport_reward?(999_999)
    end
  end

  describe "execute_quest_teleport/2" do
    test "returns :no_teleport for unconfigured quest" do
      session_data = %{active_quests: %{}}
      assert TutorialTeleports.execute_quest_teleport(session_data, 999_999) == :no_teleport
    end
  end

  describe "get_all_teleports/0" do
    test "returns a list of configured teleports" do
      teleports = TutorialTeleports.get_all_teleports()
      assert is_list(teleports)
    end
  end
end
