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

    {:ok, character} =
      Characters.create_character(account.id, %{
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

  describe "join_event/2" do
    test "player joins an active event", %{character: char} do
      {:ok, instance} = PublicEvents.create_event_instance(1, 100, 1)
      {:ok, _} = PublicEvents.start_event(instance.id, 300_000)

      assert {:ok, participation} = PublicEvents.join_event(instance.id, char.id)
      assert participation.character_id == char.id
      assert participation.contribution_score == 0
      assert participation.joined_at != nil
    end

    test "cannot join same event twice", %{character: char} do
      {:ok, instance} = PublicEvents.create_event_instance(1, 100, 1)
      {:ok, _} = PublicEvents.start_event(instance.id, 300_000)
      {:ok, _} = PublicEvents.join_event(instance.id, char.id)

      assert {:error, :already_joined} = PublicEvents.join_event(instance.id, char.id)
    end
  end

  describe "add_contribution/3" do
    test "adds contribution points", %{character: char} do
      {:ok, instance} = PublicEvents.create_event_instance(1, 100, 1)
      {:ok, _} = PublicEvents.start_event(instance.id, 300_000)
      {:ok, _} = PublicEvents.join_event(instance.id, char.id)

      assert {:ok, updated} = PublicEvents.add_contribution(instance.id, char.id, 50)
      assert updated.contribution_score == 50

      assert {:ok, again} = PublicEvents.add_contribution(instance.id, char.id, 30)
      assert again.contribution_score == 80
    end

    test "auto-joins player if not participating", %{character: char} do
      {:ok, instance} = PublicEvents.create_event_instance(1, 100, 1)
      {:ok, _} = PublicEvents.start_event(instance.id, 300_000)

      assert {:ok, participation} = PublicEvents.add_contribution(instance.id, char.id, 50)
      assert participation.contribution_score == 50
    end
  end

  describe "record_kill/3" do
    test "records kill and adds contribution", %{character: char} do
      {:ok, instance} = PublicEvents.create_event_instance(1, 100, 1)
      {:ok, _} = PublicEvents.start_event(instance.id, 300_000)
      {:ok, _} = PublicEvents.join_event(instance.id, char.id)

      assert {:ok, updated} = PublicEvents.record_kill(instance.id, char.id, 10)
      assert updated.kills == 1
      assert updated.contribution_score == 10
    end
  end

  describe "record_damage/3" do
    test "records damage dealt", %{character: char} do
      {:ok, instance} = PublicEvents.create_event_instance(1, 100, 1)
      {:ok, _} = PublicEvents.start_event(instance.id, 300_000)
      {:ok, _} = PublicEvents.join_event(instance.id, char.id)

      assert {:ok, updated} = PublicEvents.record_damage(instance.id, char.id, 1000, 5)
      assert updated.damage_dealt == 1000
      assert updated.contribution_score == 5
    end
  end

  describe "calculate_reward_tiers/1" do
    test "assigns tiers based on contribution", %{character: char} do
      {:ok, instance} = PublicEvents.create_event_instance(1, 100, 1)
      {:ok, _} = PublicEvents.start_event(instance.id, 300_000)
      {:ok, _} = PublicEvents.join_event(instance.id, char.id)
      {:ok, _} = PublicEvents.add_contribution(instance.id, char.id, 500)

      assert {:ok, participations} = PublicEvents.calculate_reward_tiers(instance.id)
      assert length(participations) == 1
      assert hd(participations).reward_tier == :gold
    end
  end

  describe "get_participations/1" do
    test "returns participations ordered by contribution", %{character: char} do
      {:ok, instance} = PublicEvents.create_event_instance(1, 100, 1)
      {:ok, _} = PublicEvents.start_event(instance.id, 300_000)
      {:ok, _} = PublicEvents.join_event(instance.id, char.id)
      {:ok, _} = PublicEvents.add_contribution(instance.id, char.id, 100)

      participations = PublicEvents.get_participations(instance.id)
      assert length(participations) == 1
      assert hd(participations).contribution_score == 100
    end
  end

  describe "record_completion/4" do
    test "records first completion", %{character: char} do
      {:ok, instance} = PublicEvents.create_event_instance(1, 100, 1)
      {:ok, _} = PublicEvents.start_event(instance.id, 300_000)
      {:ok, _} = PublicEvents.join_event(instance.id, char.id)
      {:ok, _} = PublicEvents.add_contribution(instance.id, char.id, 500)

      assert {:ok, completion} = PublicEvents.record_completion(char.id, 1, :gold, 500, 60000)
      assert completion.completion_count == 1
      assert completion.gold_count == 1
      assert completion.best_contribution == 500
    end

    test "increments completion count", %{character: char} do
      {:ok, _} = PublicEvents.record_completion(char.id, 1, :gold, 500, 60000)
      {:ok, completion} = PublicEvents.record_completion(char.id, 1, :silver, 300, 45000)

      assert completion.completion_count == 2
      assert completion.gold_count == 1
      assert completion.silver_count == 1
      assert completion.best_contribution == 500
      assert completion.fastest_completion_ms == 45000
    end
  end

  describe "get_completion_history/2" do
    test "returns completion record", %{character: char} do
      {:ok, _} = PublicEvents.record_completion(char.id, 1, :gold, 500, 60000)

      history = PublicEvents.get_completion_history(char.id, 1)
      assert history.completion_count == 1
      assert history.gold_count == 1
    end

    test "returns nil for no completions", %{character: char} do
      assert PublicEvents.get_completion_history(char.id, 999) == nil
    end
  end

  describe "create_schedule/4" do
    test "creates a timer schedule" do
      config = %{"interval_hours" => 2, "offset_minutes" => 30}
      assert {:ok, schedule} = PublicEvents.create_schedule(1, 100, :timer, config)
      assert schedule.trigger_type == :timer
      assert schedule.enabled == true
    end
  end

  describe "get_due_schedules/0" do
    test "returns schedules past their trigger time" do
      past = DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.truncate(:second)
      config = %{"interval_hours" => 2}

      {:ok, _} =
        PublicEvents.create_schedule(1, 100, :timer, config)
        |> then(fn {:ok, s} -> PublicEvents.set_next_trigger(s.id, past) end)

      schedules = PublicEvents.get_due_schedules()
      assert length(schedules) >= 1
    end
  end
end
