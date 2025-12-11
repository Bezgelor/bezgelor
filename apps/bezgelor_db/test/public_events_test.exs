defmodule BezgelorDb.PublicEventsTest do
  use ExUnit.Case

  alias BezgelorDb.{Accounts, Characters, PublicEvents, Repo}

  @moduletag :database

  setup do
    case Repo.start_link([]) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    email = "eventer#{System.unique_integer([:positive])}@test.com"
    {:ok, account} = Accounts.create_account(email, "password123")
    {:ok, character} = Characters.create_character(account.id, %{
      name: "EventHero#{System.unique_integer([:positive])}",
      sex: 0,
      race: 0,
      class: 0,
      faction_id: 166,
      world_id: 1,
      world_zone_id: 1
    })

    %{character: character}
  end

  describe "create_event_instance/3" do
    test "creates a new event instance" do
      assert {:ok, instance} = PublicEvents.create_event_instance(1, 100, 1)
      assert instance.event_id == 1
      assert instance.zone_id == 100
      assert instance.instance_id == 1
      assert instance.state == :pending
      assert instance.current_phase == 0
    end
  end

  describe "start_event/2" do
    test "starts a pending event" do
      {:ok, instance} = PublicEvents.create_event_instance(1, 100, 1)

      assert {:ok, started} = PublicEvents.start_event(instance.id, 300_000)
      assert started.state == :active
      assert started.started_at != nil
      assert started.ends_at != nil
    end

    test "cannot start non-pending event" do
      {:ok, instance} = PublicEvents.create_event_instance(1, 100, 1)
      {:ok, _} = PublicEvents.start_event(instance.id, 300_000)

      assert {:error, :invalid_state} = PublicEvents.start_event(instance.id, 300_000)
    end
  end

  describe "get_active_events/2" do
    test "returns only active events in zone" do
      {:ok, _pending} = PublicEvents.create_event_instance(1, 100, 1)
      {:ok, active_instance} = PublicEvents.create_event_instance(2, 100, 1)
      {:ok, _} = PublicEvents.start_event(active_instance.id, 300_000)
      {:ok, other_zone} = PublicEvents.create_event_instance(3, 200, 1)
      {:ok, _} = PublicEvents.start_event(other_zone.id, 300_000)

      active = PublicEvents.get_active_events(100, 1)
      assert length(active) == 1
      assert hd(active).event_id == 2
    end
  end

  describe "complete_event/1" do
    test "marks active event as completed" do
      {:ok, instance} = PublicEvents.create_event_instance(1, 100, 1)
      {:ok, _} = PublicEvents.start_event(instance.id, 300_000)

      assert {:ok, completed} = PublicEvents.complete_event(instance.id)
      assert completed.state == :completed
      assert completed.completed_at != nil
    end
  end

  describe "fail_event/1" do
    test "marks active event as failed" do
      {:ok, instance} = PublicEvents.create_event_instance(1, 100, 1)
      {:ok, _} = PublicEvents.start_event(instance.id, 300_000)

      assert {:ok, failed} = PublicEvents.fail_event(instance.id)
      assert failed.state == :failed
    end
  end

  describe "advance_phase/3" do
    test "advances to next phase" do
      {:ok, instance} = PublicEvents.create_event_instance(1, 100, 1)
      {:ok, _} = PublicEvents.start_event(instance.id, 300_000)

      assert {:ok, advanced} = PublicEvents.advance_phase(instance.id, 1, %{"objectives" => []})
      assert advanced.current_phase == 1
    end
  end

  describe "update_progress/2" do
    test "updates phase progress" do
      {:ok, instance} = PublicEvents.create_event_instance(1, 100, 1)
      {:ok, _} = PublicEvents.start_event(instance.id, 300_000)

      progress = %{"objectives" => [%{"index" => 0, "current" => 5, "target" => 10}]}
      assert {:ok, updated} = PublicEvents.update_progress(instance.id, progress)
      assert updated.phase_progress == progress
    end
  end
end
