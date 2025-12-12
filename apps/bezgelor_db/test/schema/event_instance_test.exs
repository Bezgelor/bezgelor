defmodule BezgelorDb.Schema.EventInstanceTest do
  use ExUnit.Case, async: true
  import BezgelorDb.TestHelpers

  alias BezgelorDb.Schema.EventInstance

  @valid_attrs %{
    event_id: 1001,
    zone_id: 100,
    instance_id: 1,
    state: :pending,
    current_phase: 0,
    current_wave: 0,
    participant_count: 0,
    difficulty_multiplier: 1.0
  }

  describe "changeset/2" do
    test "valid changeset with required fields" do
      changeset = EventInstance.changeset(%EventInstance{}, @valid_attrs)
      assert changeset.valid?
    end

    test "valid with minimal required fields" do
      attrs = %{event_id: 1001, zone_id: 100}
      changeset = EventInstance.changeset(%EventInstance{}, attrs)
      assert changeset.valid?
    end

    test "invalid without event_id" do
      attrs = Map.delete(@valid_attrs, :event_id)
      changeset = EventInstance.changeset(%EventInstance{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).event_id
    end

    test "invalid without zone_id" do
      attrs = Map.delete(@valid_attrs, :zone_id)
      changeset = EventInstance.changeset(%EventInstance{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).zone_id
    end

    test "invalid with negative current_phase" do
      attrs = Map.put(@valid_attrs, :current_phase, -1)
      changeset = EventInstance.changeset(%EventInstance{}, attrs)
      refute changeset.valid?
    end

    test "invalid with negative current_wave" do
      attrs = Map.put(@valid_attrs, :current_wave, -1)
      changeset = EventInstance.changeset(%EventInstance{}, attrs)
      refute changeset.valid?
    end

    test "invalid with negative participant_count" do
      attrs = Map.put(@valid_attrs, :participant_count, -1)
      changeset = EventInstance.changeset(%EventInstance{}, attrs)
      refute changeset.valid?
    end

    test "invalid with zero difficulty_multiplier" do
      attrs = Map.put(@valid_attrs, :difficulty_multiplier, 0.0)
      changeset = EventInstance.changeset(%EventInstance{}, attrs)
      refute changeset.valid?
    end

    test "invalid with negative difficulty_multiplier" do
      attrs = Map.put(@valid_attrs, :difficulty_multiplier, -1.0)
      changeset = EventInstance.changeset(%EventInstance{}, attrs)
      refute changeset.valid?
    end

    test "accepts all valid states" do
      for state <- EventInstance.valid_states() do
        attrs = Map.put(@valid_attrs, :state, state)
        changeset = EventInstance.changeset(%EventInstance{}, attrs)
        assert changeset.valid?, "Expected state #{state} to be valid"
      end
    end

    test "defaults state to pending" do
      changeset = EventInstance.changeset(%EventInstance{}, %{event_id: 1, zone_id: 1})
      assert Ecto.Changeset.get_field(changeset, :state) == :pending
    end

    test "defaults current_phase to 0" do
      changeset = EventInstance.changeset(%EventInstance{}, %{event_id: 1, zone_id: 1})
      assert Ecto.Changeset.get_field(changeset, :current_phase) == 0
    end

    test "defaults current_wave to 0" do
      changeset = EventInstance.changeset(%EventInstance{}, %{event_id: 1, zone_id: 1})
      assert Ecto.Changeset.get_field(changeset, :current_wave) == 0
    end

    test "defaults phase_progress to empty map" do
      changeset = EventInstance.changeset(%EventInstance{}, %{event_id: 1, zone_id: 1})
      assert Ecto.Changeset.get_field(changeset, :phase_progress) == %{}
    end
  end

  describe "start_changeset/3" do
    test "sets state to active and timestamps" do
      instance = %EventInstance{state: :pending}
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      ends_at = DateTime.add(now, 600, :second)

      changeset = EventInstance.start_changeset(instance, now, ends_at)

      assert Ecto.Changeset.get_change(changeset, :state) == :active
      assert Ecto.Changeset.get_change(changeset, :started_at) == now
      assert Ecto.Changeset.get_change(changeset, :ends_at) == ends_at
    end
  end

  describe "progress_changeset/2" do
    test "updates phase_progress" do
      instance = %EventInstance{phase_progress: %{}}
      progress = %{"objective_0" => 15, "objective_1" => 5}

      changeset = EventInstance.progress_changeset(instance, progress)

      assert Ecto.Changeset.get_change(changeset, :phase_progress) == progress
    end
  end

  describe "advance_phase_changeset/3" do
    test "updates phase and resets progress" do
      instance = %EventInstance{current_phase: 0, phase_progress: %{"objective_0" => 30}}
      new_progress = %{}

      changeset = EventInstance.advance_phase_changeset(instance, 1, new_progress)

      assert Ecto.Changeset.get_change(changeset, :current_phase) == 1
      assert Ecto.Changeset.get_change(changeset, :phase_progress) == new_progress
    end
  end

  describe "advance_wave_changeset/2" do
    test "increments wave number" do
      instance = %EventInstance{current_wave: 2}

      changeset = EventInstance.advance_wave_changeset(instance, 3)

      assert Ecto.Changeset.get_change(changeset, :current_wave) == 3
    end
  end

  describe "participant_changeset/2" do
    test "updates participant count" do
      instance = %EventInstance{participant_count: 5}

      changeset = EventInstance.participant_changeset(instance, 10)

      assert Ecto.Changeset.get_change(changeset, :participant_count) == 10
    end
  end

  describe "difficulty_changeset/2" do
    test "updates difficulty multiplier" do
      instance = %EventInstance{difficulty_multiplier: 1.0}

      changeset = EventInstance.difficulty_changeset(instance, 1.5)

      assert Ecto.Changeset.get_change(changeset, :difficulty_multiplier) == 1.5
    end
  end

  describe "complete_changeset/2" do
    test "sets state to completed with timestamp" do
      instance = %EventInstance{state: :active}
      completed_at = DateTime.utc_now() |> DateTime.truncate(:second)

      changeset = EventInstance.complete_changeset(instance, completed_at)

      assert Ecto.Changeset.get_change(changeset, :state) == :completed
      assert Ecto.Changeset.get_change(changeset, :completed_at) == completed_at
    end
  end

  describe "fail_changeset/1" do
    test "sets state to failed with timestamp" do
      instance = %EventInstance{state: :active}

      changeset = EventInstance.fail_changeset(instance)

      assert Ecto.Changeset.get_change(changeset, :state) == :failed
      assert Ecto.Changeset.get_change(changeset, :completed_at) != nil
    end
  end

  describe "cancel_changeset/1" do
    test "sets state to cancelled" do
      instance = %EventInstance{state: :active}

      changeset = EventInstance.cancel_changeset(instance)

      assert Ecto.Changeset.get_change(changeset, :state) == :cancelled
    end
  end

  describe "valid_states/0" do
    test "returns list of valid states" do
      states = EventInstance.valid_states()
      assert :pending in states
      assert :active in states
      assert :completed in states
      assert :failed in states
      assert :cancelled in states
    end
  end
end
