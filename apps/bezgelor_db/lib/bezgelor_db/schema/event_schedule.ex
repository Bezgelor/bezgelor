defmodule BezgelorDb.Schema.EventSchedule do
  @moduledoc """
  Event scheduling configuration.

  Defines when and how events are triggered: by timer, random window,
  player count, or chain from another event.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @trigger_types [:timer, :random_window, :player_count, :chain, :manual]

  schema "event_schedules" do
    field(:event_id, :integer)
    field(:zone_id, :integer)
    field(:enabled, :boolean, default: true)

    field(:trigger_type, Ecto.Enum, values: @trigger_types)
    field(:trigger_config, :map, default: %{})
    # timer: %{"interval_hours" => 2, "offset_minutes" => 30}
    # random_window: %{"start_hour" => 18, "end_hour" => 22, "min_gap_hours" => 4}
    # player_count: %{"min_players" => 10, "check_interval_ms" => 60000}
    # chain: %{"after_event_id" => 1001, "delay_ms" => 30000}

    field(:last_triggered_at, :utc_datetime)
    field(:next_trigger_at, :utc_datetime)

    timestamps(type: :utc_datetime)
  end

  def changeset(schedule, attrs) do
    schedule
    |> cast(attrs, [
      :event_id,
      :zone_id,
      :enabled,
      :trigger_type,
      :trigger_config,
      :last_triggered_at,
      :next_trigger_at
    ])
    |> validate_required([:event_id, :zone_id, :trigger_type])
  end

  def enable_changeset(schedule) do
    schedule
    |> change(enabled: true)
  end

  def disable_changeset(schedule) do
    schedule
    |> change(enabled: false)
  end

  def trigger_changeset(schedule, triggered_at, next_trigger_at) do
    schedule
    |> change(last_triggered_at: triggered_at, next_trigger_at: next_trigger_at)
  end

  def update_next_trigger_changeset(schedule, next_trigger_at) do
    schedule
    |> change(next_trigger_at: next_trigger_at)
  end

  def valid_trigger_types, do: @trigger_types
end
