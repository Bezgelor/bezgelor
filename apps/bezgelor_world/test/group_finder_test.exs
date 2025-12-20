defmodule BezgelorWorld.GroupFinderTest do
  use ExUnit.Case, async: true

  alias BezgelorWorld.GroupFinder.{GroupFinder, Matcher}

  describe "Matcher.find_dungeon_match/2" do
    test "finds match when roles are satisfied (1 tank, 1 healer, 3 dps)" do
      queue = [
        %{
          character_id: 1,
          roles: [:tank],
          queued_at: 0,
          instance_ids: [100],
          gear_score: 500,
          language: "en"
        },
        %{
          character_id: 2,
          roles: [:healer],
          queued_at: 1,
          instance_ids: [100],
          gear_score: 500,
          language: "en"
        },
        %{
          character_id: 3,
          roles: [:dps],
          queued_at: 2,
          instance_ids: [100],
          gear_score: 500,
          language: "en"
        },
        %{
          character_id: 4,
          roles: [:dps],
          queued_at: 3,
          instance_ids: [100],
          gear_score: 500,
          language: "en"
        },
        %{
          character_id: 5,
          roles: [:dps],
          queued_at: 4,
          instance_ids: [100],
          gear_score: 500,
          language: "en"
        }
      ]

      assert {:ok, match} = Matcher.find_dungeon_match(:normal, queue)
      assert match.instance_id == 100
      assert length(match.members) == 5

      # Verify role distribution
      roles = Enum.map(match.members, & &1.role)
      assert Enum.count(roles, &(&1 == :tank)) == 1
      assert Enum.count(roles, &(&1 == :healer)) == 1
      assert Enum.count(roles, &(&1 == :dps)) == 3
    end

    test "returns no_match when not enough tanks" do
      queue = [
        %{
          character_id: 1,
          roles: [:healer],
          queued_at: 0,
          instance_ids: [100],
          gear_score: 500,
          language: "en"
        },
        %{
          character_id: 2,
          roles: [:healer],
          queued_at: 1,
          instance_ids: [100],
          gear_score: 500,
          language: "en"
        },
        %{
          character_id: 3,
          roles: [:dps],
          queued_at: 2,
          instance_ids: [100],
          gear_score: 500,
          language: "en"
        },
        %{
          character_id: 4,
          roles: [:dps],
          queued_at: 3,
          instance_ids: [100],
          gear_score: 500,
          language: "en"
        },
        %{
          character_id: 5,
          roles: [:dps],
          queued_at: 4,
          instance_ids: [100],
          gear_score: 500,
          language: "en"
        }
      ]

      assert :no_match = Matcher.find_dungeon_match(:normal, queue)
    end

    test "returns no_match when not enough healers" do
      queue = [
        %{
          character_id: 1,
          roles: [:tank],
          queued_at: 0,
          instance_ids: [100],
          gear_score: 500,
          language: "en"
        },
        %{
          character_id: 2,
          roles: [:tank],
          queued_at: 1,
          instance_ids: [100],
          gear_score: 500,
          language: "en"
        },
        %{
          character_id: 3,
          roles: [:dps],
          queued_at: 2,
          instance_ids: [100],
          gear_score: 500,
          language: "en"
        },
        %{
          character_id: 4,
          roles: [:dps],
          queued_at: 3,
          instance_ids: [100],
          gear_score: 500,
          language: "en"
        },
        %{
          character_id: 5,
          roles: [:dps],
          queued_at: 4,
          instance_ids: [100],
          gear_score: 500,
          language: "en"
        }
      ]

      assert :no_match = Matcher.find_dungeon_match(:normal, queue)
    end

    test "players with multiple roles can fill needed positions" do
      queue = [
        %{
          character_id: 1,
          roles: [:tank, :dps],
          queued_at: 0,
          instance_ids: [100],
          gear_score: 500,
          language: "en"
        },
        %{
          character_id: 2,
          roles: [:healer, :dps],
          queued_at: 1,
          instance_ids: [100],
          gear_score: 500,
          language: "en"
        },
        %{
          character_id: 3,
          roles: [:dps],
          queued_at: 2,
          instance_ids: [100],
          gear_score: 500,
          language: "en"
        },
        %{
          character_id: 4,
          roles: [:dps],
          queued_at: 3,
          instance_ids: [100],
          gear_score: 500,
          language: "en"
        },
        %{
          character_id: 5,
          roles: [:dps],
          queued_at: 4,
          instance_ids: [100],
          gear_score: 500,
          language: "en"
        }
      ]

      assert {:ok, match} = Matcher.find_dungeon_match(:normal, queue)
      assert length(match.members) == 5
    end
  end

  describe "Matcher.find_expedition_match/2" do
    test "finds match with any 5 players (flexible composition)" do
      queue = [
        %{character_id: 1, roles: [:dps], queued_at: 0, instance_ids: [200]},
        %{character_id: 2, roles: [:dps], queued_at: 1, instance_ids: [200]},
        %{character_id: 3, roles: [:dps], queued_at: 2, instance_ids: [200]},
        %{character_id: 4, roles: [:dps], queued_at: 3, instance_ids: [200]},
        %{character_id: 5, roles: [:dps], queued_at: 4, instance_ids: [200]}
      ]

      assert {:ok, match} = Matcher.find_expedition_match(:normal, queue)
      assert match.instance_id == 200
      assert length(match.members) == 5
    end

    test "returns no_match with fewer than 5 players" do
      queue = [
        %{character_id: 1, roles: [:dps], queued_at: 0, instance_ids: [200]},
        %{character_id: 2, roles: [:dps], queued_at: 1, instance_ids: [200]}
      ]

      assert :no_match = Matcher.find_expedition_match(:normal, queue)
    end
  end

  describe "Matcher.find_raid_match/2" do
    test "finds match when raid composition is satisfied" do
      # 2 tanks, 5 healers, 13 dps = 20 players
      queue =
        [
          %{
            character_id: 1,
            roles: [:tank],
            queued_at: 0,
            instance_ids: [300],
            gear_score: 500,
            language: "en"
          },
          %{
            character_id: 2,
            roles: [:tank],
            queued_at: 1,
            instance_ids: [300],
            gear_score: 500,
            language: "en"
          }
        ] ++
          for i <- 3..7 do
            %{
              character_id: i,
              roles: [:healer],
              queued_at: i,
              instance_ids: [300],
              gear_score: 500,
              language: "en"
            }
          end ++
          for i <- 8..20 do
            %{
              character_id: i,
              roles: [:dps],
              queued_at: i,
              instance_ids: [300],
              gear_score: 500,
              language: "en"
            }
          end

      assert {:ok, match} = Matcher.find_raid_match(:normal, queue)
      assert match.instance_id == 300
      assert length(match.members) == 20

      # Verify role distribution
      roles = Enum.map(match.members, & &1.role)
      assert Enum.count(roles, &(&1 == :tank)) == 2
      assert Enum.count(roles, &(&1 == :healer)) == 5
      assert Enum.count(roles, &(&1 == :dps)) == 13
    end
  end

  describe "common_instance_preference" do
    test "selects most popular instance" do
      queue = [
        %{
          character_id: 1,
          roles: [:tank],
          queued_at: 0,
          instance_ids: [100, 101],
          gear_score: 500,
          language: "en"
        },
        %{
          character_id: 2,
          roles: [:healer],
          queued_at: 1,
          instance_ids: [101, 102],
          gear_score: 500,
          language: "en"
        },
        %{
          character_id: 3,
          roles: [:dps],
          queued_at: 2,
          instance_ids: [100, 101],
          gear_score: 500,
          language: "en"
        },
        %{
          character_id: 4,
          roles: [:dps],
          queued_at: 3,
          instance_ids: [101],
          gear_score: 500,
          language: "en"
        },
        %{
          character_id: 5,
          roles: [:dps],
          queued_at: 4,
          instance_ids: [101, 103],
          gear_score: 500,
          language: "en"
        }
      ]

      assert {:ok, match} = Matcher.find_dungeon_match(:normal, queue)
      # Instance 101 appears 5 times, should be selected
      assert match.instance_id == 101
    end
  end
end
