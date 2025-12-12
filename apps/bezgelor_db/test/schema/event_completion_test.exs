defmodule BezgelorDb.Schema.EventCompletionTest do
  use ExUnit.Case, async: true
  import BezgelorDb.TestHelpers

  alias BezgelorDb.Schema.EventCompletion

  @valid_attrs %{
    character_id: 1,
    event_id: 1001,
    completion_count: 1,
    gold_count: 0,
    silver_count: 0,
    bronze_count: 0,
    best_contribution: 0
  }

  describe "changeset/2" do
    test "valid changeset with required fields" do
      changeset = EventCompletion.changeset(%EventCompletion{}, @valid_attrs)
      assert changeset.valid?
    end

    test "valid with minimal required fields" do
      attrs = %{character_id: 1, event_id: 1001}
      changeset = EventCompletion.changeset(%EventCompletion{}, attrs)
      assert changeset.valid?
    end

    test "invalid without character_id" do
      attrs = Map.delete(@valid_attrs, :character_id)
      changeset = EventCompletion.changeset(%EventCompletion{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).character_id
    end

    test "invalid without event_id" do
      attrs = Map.delete(@valid_attrs, :event_id)
      changeset = EventCompletion.changeset(%EventCompletion{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).event_id
    end

    test "invalid with zero completion_count" do
      attrs = Map.put(@valid_attrs, :completion_count, 0)
      changeset = EventCompletion.changeset(%EventCompletion{}, attrs)
      refute changeset.valid?
    end

    test "invalid with negative completion_count" do
      attrs = Map.put(@valid_attrs, :completion_count, -1)
      changeset = EventCompletion.changeset(%EventCompletion{}, attrs)
      refute changeset.valid?
    end

    test "invalid with negative gold_count" do
      attrs = Map.put(@valid_attrs, :gold_count, -1)
      changeset = EventCompletion.changeset(%EventCompletion{}, attrs)
      refute changeset.valid?
    end

    test "invalid with negative silver_count" do
      attrs = Map.put(@valid_attrs, :silver_count, -1)
      changeset = EventCompletion.changeset(%EventCompletion{}, attrs)
      refute changeset.valid?
    end

    test "invalid with negative bronze_count" do
      attrs = Map.put(@valid_attrs, :bronze_count, -1)
      changeset = EventCompletion.changeset(%EventCompletion{}, attrs)
      refute changeset.valid?
    end

    test "invalid with negative best_contribution" do
      attrs = Map.put(@valid_attrs, :best_contribution, -1)
      changeset = EventCompletion.changeset(%EventCompletion{}, attrs)
      refute changeset.valid?
    end

    test "defaults completion_count to 1" do
      changeset = EventCompletion.changeset(%EventCompletion{}, %{character_id: 1, event_id: 1})
      assert Ecto.Changeset.get_field(changeset, :completion_count) == 1
    end

    test "defaults gold_count to 0" do
      changeset = EventCompletion.changeset(%EventCompletion{}, %{character_id: 1, event_id: 1})
      assert Ecto.Changeset.get_field(changeset, :gold_count) == 0
    end

    test "defaults silver_count to 0" do
      changeset = EventCompletion.changeset(%EventCompletion{}, %{character_id: 1, event_id: 1})
      assert Ecto.Changeset.get_field(changeset, :silver_count) == 0
    end

    test "defaults bronze_count to 0" do
      changeset = EventCompletion.changeset(%EventCompletion{}, %{character_id: 1, event_id: 1})
      assert Ecto.Changeset.get_field(changeset, :bronze_count) == 0
    end

    test "defaults best_contribution to 0" do
      changeset = EventCompletion.changeset(%EventCompletion{}, %{character_id: 1, event_id: 1})
      assert Ecto.Changeset.get_field(changeset, :best_contribution) == 0
    end
  end

  describe "increment_changeset/5" do
    test "increments gold count for gold tier" do
      completion = %EventCompletion{
        completion_count: 5,
        gold_count: 2,
        silver_count: 2,
        bronze_count: 1,
        best_contribution: 500,
        fastest_completion_ms: 300_000
      }
      completed_at = DateTime.utc_now() |> DateTime.truncate(:second)

      changeset = EventCompletion.increment_changeset(completion, :gold, 600, 250_000, completed_at)

      assert Ecto.Changeset.get_field(changeset, :completion_count) == 6
      assert Ecto.Changeset.get_field(changeset, :gold_count) == 3
      assert Ecto.Changeset.get_field(changeset, :silver_count) == 2
      assert Ecto.Changeset.get_field(changeset, :bronze_count) == 1
      assert Ecto.Changeset.get_field(changeset, :best_contribution) == 600
      assert Ecto.Changeset.get_field(changeset, :fastest_completion_ms) == 250_000
    end

    test "increments silver count for silver tier" do
      completion = %EventCompletion{
        completion_count: 3,
        gold_count: 1,
        silver_count: 1,
        bronze_count: 1,
        best_contribution: 400,
        fastest_completion_ms: nil
      }
      completed_at = DateTime.utc_now() |> DateTime.truncate(:second)

      changeset = EventCompletion.increment_changeset(completion, :silver, 300, 350_000, completed_at)

      assert Ecto.Changeset.get_field(changeset, :completion_count) == 4
      assert Ecto.Changeset.get_field(changeset, :gold_count) == 1
      assert Ecto.Changeset.get_field(changeset, :silver_count) == 2
      assert Ecto.Changeset.get_field(changeset, :bronze_count) == 1
      assert Ecto.Changeset.get_field(changeset, :best_contribution) == 400
      assert Ecto.Changeset.get_field(changeset, :fastest_completion_ms) == 350_000
    end

    test "increments bronze count for bronze tier" do
      completion = %EventCompletion{
        completion_count: 2,
        gold_count: 0,
        silver_count: 1,
        bronze_count: 1,
        best_contribution: 200,
        fastest_completion_ms: 400_000
      }
      completed_at = DateTime.utc_now() |> DateTime.truncate(:second)

      changeset = EventCompletion.increment_changeset(completion, :bronze, 150, 500_000, completed_at)

      assert Ecto.Changeset.get_field(changeset, :completion_count) == 3
      assert Ecto.Changeset.get_field(changeset, :gold_count) == 0
      assert Ecto.Changeset.get_field(changeset, :silver_count) == 1
      assert Ecto.Changeset.get_field(changeset, :bronze_count) == 2
      assert Ecto.Changeset.get_field(changeset, :best_contribution) == 200
      assert Ecto.Changeset.get_field(changeset, :fastest_completion_ms) == 400_000
    end

    test "does not increment tier for participation" do
      completion = %EventCompletion{
        completion_count: 1,
        gold_count: 0,
        silver_count: 0,
        bronze_count: 0,
        best_contribution: 50,
        fastest_completion_ms: nil
      }
      completed_at = DateTime.utc_now() |> DateTime.truncate(:second)

      changeset = EventCompletion.increment_changeset(completion, :participation, 60, 600_000, completed_at)

      assert Ecto.Changeset.get_field(changeset, :completion_count) == 2
      assert Ecto.Changeset.get_field(changeset, :gold_count) == 0
      assert Ecto.Changeset.get_field(changeset, :silver_count) == 0
      assert Ecto.Changeset.get_field(changeset, :bronze_count) == 0
    end

    test "updates best_contribution when new is higher" do
      completion = %EventCompletion{
        completion_count: 1,
        gold_count: 0,
        silver_count: 0,
        bronze_count: 0,
        best_contribution: 100,
        fastest_completion_ms: 300_000
      }
      completed_at = DateTime.utc_now() |> DateTime.truncate(:second)

      changeset = EventCompletion.increment_changeset(completion, :gold, 200, 400_000, completed_at)

      assert Ecto.Changeset.get_field(changeset, :best_contribution) == 200
    end

    test "keeps best_contribution when existing is higher" do
      completion = %EventCompletion{
        completion_count: 1,
        gold_count: 0,
        silver_count: 0,
        bronze_count: 0,
        best_contribution: 300,
        fastest_completion_ms: 300_000
      }
      completed_at = DateTime.utc_now() |> DateTime.truncate(:second)

      changeset = EventCompletion.increment_changeset(completion, :silver, 200, 400_000, completed_at)

      assert Ecto.Changeset.get_field(changeset, :best_contribution) == 300
    end

    test "updates fastest_completion when new is faster" do
      completion = %EventCompletion{
        completion_count: 1,
        gold_count: 0,
        silver_count: 0,
        bronze_count: 0,
        best_contribution: 100,
        fastest_completion_ms: 300_000
      }
      completed_at = DateTime.utc_now() |> DateTime.truncate(:second)

      changeset = EventCompletion.increment_changeset(completion, :gold, 100, 200_000, completed_at)

      assert Ecto.Changeset.get_field(changeset, :fastest_completion_ms) == 200_000
    end

    test "keeps fastest_completion when existing is faster" do
      completion = %EventCompletion{
        completion_count: 1,
        gold_count: 0,
        silver_count: 0,
        bronze_count: 0,
        best_contribution: 100,
        fastest_completion_ms: 200_000
      }
      completed_at = DateTime.utc_now() |> DateTime.truncate(:second)

      changeset = EventCompletion.increment_changeset(completion, :gold, 100, 300_000, completed_at)

      assert Ecto.Changeset.get_field(changeset, :fastest_completion_ms) == 200_000
    end

    test "sets fastest_completion when nil" do
      completion = %EventCompletion{
        completion_count: 1,
        gold_count: 0,
        silver_count: 0,
        bronze_count: 0,
        best_contribution: 100,
        fastest_completion_ms: nil
      }
      completed_at = DateTime.utc_now() |> DateTime.truncate(:second)

      changeset = EventCompletion.increment_changeset(completion, :gold, 100, 300_000, completed_at)

      assert Ecto.Changeset.get_change(changeset, :fastest_completion_ms) == 300_000
    end

    test "updates last_completed_at" do
      completion = %EventCompletion{
        completion_count: 1,
        gold_count: 0,
        silver_count: 0,
        bronze_count: 0,
        best_contribution: 100,
        fastest_completion_ms: nil
      }
      completed_at = DateTime.utc_now() |> DateTime.truncate(:second)

      changeset = EventCompletion.increment_changeset(completion, :gold, 100, 300_000, completed_at)

      assert Ecto.Changeset.get_change(changeset, :last_completed_at) == completed_at
    end
  end
end
