defmodule BezgelorWorld.Handler.SpellHandlerStatsTest do
  use ExUnit.Case, async: false

  alias BezgelorCore.CharacterStats

  describe "get_caster_stats/1" do
    test "retrieves stats from session data" do
      session_data = %{
        character: %{level: 10, class: 1, race: 0},
        entity_guid: 12345
      }

      stats = CharacterStats.compute_combat_stats(session_data.character)

      # Stats should be computed from character, not hardcoded
      assert stats.power > 50
      assert is_integer(stats.crit_chance)
    end
  end
end
