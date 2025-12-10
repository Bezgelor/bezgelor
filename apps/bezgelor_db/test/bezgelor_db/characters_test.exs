defmodule BezgelorDb.CharactersTest do
  use ExUnit.Case

  alias BezgelorDb.{Accounts, Characters, Repo}
  alias BezgelorDb.Schema.CharacterAppearance

  @moduletag :database

  setup do
    # Start the repo for testing if not already started
    case Repo.start_link([]) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    # Use a transaction for each test and roll back at the end
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    email = "char_test#{System.unique_integer([:positive])}@test.com"
    {:ok, account} = Accounts.create_account(email, "password123")
    %{account: account}
  end

  describe "create_character/3" do
    test "creates character with valid attributes", %{account: account} do
      attrs = %{
        name: "TestHero",
        sex: 0,
        race: 0,
        class: 0,
        faction_id: 166,
        world_id: 1,
        world_zone_id: 1
      }

      appearance_attrs = %{
        hair_style: 5,
        hair_color: 3,
        skin_color: 2
      }

      assert {:ok, character} = Characters.create_character(account.id, attrs, appearance_attrs)
      assert character.name == "TestHero"
      assert character.sex == 0
      assert character.race == 0
      assert character.faction_id == 166
      assert character.appearance != nil
      assert character.appearance.hair_style == 5
      assert character.appearance.hair_color == 3
    end

    test "creates character without appearance attrs", %{account: account} do
      attrs = %{
        name: "NoAppearance",
        sex: 1,
        race: 4,
        class: 1,
        faction_id: 166,
        world_id: 1,
        world_zone_id: 1
      }

      assert {:ok, character} = Characters.create_character(account.id, attrs)
      assert character.name == "NoAppearance"
      assert character.appearance != nil
      assert character.appearance.hair_style == 0
    end

    test "rejects duplicate name", %{account: account} do
      attrs = %{
        name: "DuplicateName",
        sex: 0,
        race: 0,
        class: 0,
        faction_id: 166,
        world_id: 1,
        world_zone_id: 1
      }

      assert {:ok, _} = Characters.create_character(account.id, attrs)
      assert {:error, :name_taken} = Characters.create_character(account.id, attrs)
    end

    test "rejects name too short", %{account: account} do
      attrs = %{
        name: "AB",
        sex: 0,
        race: 0,
        class: 0,
        faction_id: 166,
        world_id: 1,
        world_zone_id: 1
      }

      assert {:error, :invalid_name} = Characters.create_character(account.id, attrs)
    end

    test "rejects name too long", %{account: account} do
      attrs = %{
        name: String.duplicate("a", 25),
        sex: 0,
        race: 0,
        class: 0,
        faction_id: 166,
        world_id: 1,
        world_zone_id: 1
      }

      assert {:error, :invalid_name} = Characters.create_character(account.id, attrs)
    end

    test "rejects invalid name characters", %{account: account} do
      attrs = %{
        name: "Invalid@Name",
        sex: 0,
        race: 0,
        class: 0,
        faction_id: 166,
        world_id: 1,
        world_zone_id: 1
      }

      assert {:error, :invalid_name} = Characters.create_character(account.id, attrs)
    end

    test "rejects wrong faction for race", %{account: account} do
      attrs = %{
        name: "WrongFaction",
        sex: 0,
        race: 0,
        class: 0,
        faction_id: 167,
        world_id: 1,
        world_zone_id: 1
      }

      assert {:error, :invalid_faction} = Characters.create_character(account.id, attrs)
    end

    test "allows dominion race with dominion faction", %{account: account} do
      attrs = %{
        name: "DominionChar",
        sex: 0,
        race: 13,
        class: 0,
        faction_id: 167,
        world_id: 1,
        world_zone_id: 1
      }

      assert {:ok, character} = Characters.create_character(account.id, attrs)
      assert character.faction_id == 167
    end
  end

  describe "list_characters/1" do
    test "returns empty list for new account", %{account: account} do
      assert [] == Characters.list_characters(account.id)
    end

    test "returns characters for account", %{account: account} do
      {:ok, _} =
        Characters.create_character(account.id, %{
          name: "Char1",
          sex: 0,
          race: 0,
          class: 0,
          faction_id: 166,
          world_id: 1,
          world_zone_id: 1
        })

      {:ok, _} =
        Characters.create_character(account.id, %{
          name: "Char2",
          sex: 1,
          race: 4,
          class: 1,
          faction_id: 166,
          world_id: 1,
          world_zone_id: 1
        })

      characters = Characters.list_characters(account.id)
      assert length(characters) == 2
      names = Enum.map(characters, & &1.name)
      assert "Char1" in names
      assert "Char2" in names
    end

    test "excludes deleted characters", %{account: account} do
      {:ok, char} =
        Characters.create_character(account.id, %{
          name: "ToDelete",
          sex: 0,
          race: 0,
          class: 0,
          faction_id: 166,
          world_id: 1,
          world_zone_id: 1
        })

      assert length(Characters.list_characters(account.id)) == 1

      {:ok, _} = Characters.delete_character(account.id, char.id)

      assert [] == Characters.list_characters(account.id)
    end

    test "preloads appearance", %{account: account} do
      {:ok, _} =
        Characters.create_character(
          account.id,
          %{
            name: "WithAppearance",
            sex: 0,
            race: 0,
            class: 0,
            faction_id: 166,
            world_id: 1,
            world_zone_id: 1
          },
          %{hair_style: 10}
        )

      [character] = Characters.list_characters(account.id)
      assert %CharacterAppearance{} = character.appearance
      assert character.appearance.hair_style == 10
    end
  end

  describe "get_character/2" do
    test "returns character by id", %{account: account} do
      {:ok, created} =
        Characters.create_character(account.id, %{
          name: "GetMe",
          sex: 0,
          race: 0,
          class: 0,
          faction_id: 166,
          world_id: 1,
          world_zone_id: 1
        })

      character = Characters.get_character(account.id, created.id)
      assert character.id == created.id
      assert character.name == "GetMe"
    end

    test "returns nil for wrong account", %{account: account} do
      {:ok, other_account} = Accounts.create_account("other@test.com", "password123")

      {:ok, created} =
        Characters.create_character(account.id, %{
          name: "NotYours",
          sex: 0,
          race: 0,
          class: 0,
          faction_id: 166,
          world_id: 1,
          world_zone_id: 1
        })

      assert nil == Characters.get_character(other_account.id, created.id)
    end

    test "returns nil for deleted character", %{account: account} do
      {:ok, created} =
        Characters.create_character(account.id, %{
          name: "Deleted",
          sex: 0,
          race: 0,
          class: 0,
          faction_id: 166,
          world_id: 1,
          world_zone_id: 1
        })

      {:ok, _} = Characters.delete_character(account.id, created.id)

      assert nil == Characters.get_character(account.id, created.id)
    end
  end

  describe "delete_character/2" do
    test "soft deletes character", %{account: account} do
      {:ok, created} =
        Characters.create_character(account.id, %{
          name: "ToDelete",
          sex: 0,
          race: 0,
          class: 0,
          faction_id: 166,
          world_id: 1,
          world_zone_id: 1
        })

      assert {:ok, deleted} = Characters.delete_character(account.id, created.id)
      assert deleted.deleted_at != nil
      assert deleted.original_name == "ToDelete"
    end

    test "returns error for non-existent character", %{account: account} do
      assert {:error, :not_found} = Characters.delete_character(account.id, 999_999)
    end

    test "returns error for wrong account", %{account: account} do
      {:ok, other_account} = Accounts.create_account("other2@test.com", "password123")

      {:ok, created} =
        Characters.create_character(account.id, %{
          name: "WrongOwner",
          sex: 0,
          race: 0,
          class: 0,
          faction_id: 166,
          world_id: 1,
          world_zone_id: 1
        })

      assert {:error, :not_found} = Characters.delete_character(other_account.id, created.id)
    end
  end

  describe "count_characters/1" do
    test "returns 0 for new account", %{account: account} do
      assert 0 == Characters.count_characters(account.id)
    end

    test "counts non-deleted characters", %{account: account} do
      for i <- 1..3 do
        {:ok, _} =
          Characters.create_character(account.id, %{
            name: "Char#{i}",
            sex: 0,
            race: 0,
            class: 0,
            faction_id: 166,
            world_id: 1,
            world_zone_id: 1
          })
      end

      assert 3 == Characters.count_characters(account.id)
    end
  end

  describe "name_available?/1" do
    test "returns true for available name", %{account: _account} do
      assert Characters.name_available?("UnusedName")
    end

    test "returns false for taken name", %{account: account} do
      {:ok, _} =
        Characters.create_character(account.id, %{
          name: "TakenName",
          sex: 0,
          race: 0,
          class: 0,
          faction_id: 166,
          world_id: 1,
          world_zone_id: 1
        })

      refute Characters.name_available?("TakenName")
    end

    test "is case insensitive", %{account: account} do
      {:ok, _} =
        Characters.create_character(account.id, %{
          name: "CaseName",
          sex: 0,
          race: 0,
          class: 0,
          faction_id: 166,
          world_id: 1,
          world_zone_id: 1
        })

      refute Characters.name_available?("casename")
      refute Characters.name_available?("CASENAME")
      refute Characters.name_available?("CaSeName")
    end
  end

  describe "max_characters/0" do
    test "returns character limit" do
      assert Characters.max_characters() == 12
    end
  end

  describe "valid_race_faction?/2" do
    test "exile races with exile faction" do
      assert Characters.valid_race_faction?(0, 166)
      assert Characters.valid_race_faction?(1, 166)
      assert Characters.valid_race_faction?(3, 166)
      assert Characters.valid_race_faction?(4, 166)
    end

    test "dominion races with dominion faction" do
      assert Characters.valid_race_faction?(2, 167)
      assert Characters.valid_race_faction?(5, 167)
      assert Characters.valid_race_faction?(12, 167)
      assert Characters.valid_race_faction?(13, 167)
    end

    test "exile races with dominion faction invalid" do
      refute Characters.valid_race_faction?(0, 167)
      refute Characters.valid_race_faction?(4, 167)
    end

    test "dominion races with exile faction invalid" do
      refute Characters.valid_race_faction?(2, 166)
      refute Characters.valid_race_faction?(13, 166)
    end
  end
end
