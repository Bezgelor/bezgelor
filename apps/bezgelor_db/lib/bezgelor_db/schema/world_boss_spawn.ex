defmodule BezgelorDb.Schema.WorldBossSpawn do
  @moduledoc """
  World boss spawn tracking.

  Manages spawn windows, current state, and cooldowns for world bosses.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @states [:waiting, :spawned, :engaged, :killed]

  schema "world_boss_spawns" do
    field :boss_id, :integer
    field :zone_id, :integer

    field :state, Ecto.Enum, values: @states, default: :waiting
    field :spawn_window_start, :utc_datetime
    field :spawn_window_end, :utc_datetime
    field :spawned_at, :utc_datetime
    field :killed_at, :utc_datetime
    field :next_spawn_after, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(spawn, attrs) do
    spawn
    |> cast(attrs, [
      :boss_id, :zone_id, :state, :spawn_window_start, :spawn_window_end,
      :spawned_at, :killed_at, :next_spawn_after
    ])
    |> validate_required([:boss_id, :zone_id])
    |> unique_constraint([:boss_id])
  end

  def set_window_changeset(spawn, window_start, window_end) do
    spawn
    |> change(
      state: :waiting,
      spawn_window_start: window_start,
      spawn_window_end: window_end,
      spawned_at: nil,
      killed_at: nil
    )
  end

  def spawn_changeset(spawn) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    spawn
    |> change(state: :spawned, spawned_at: now)
  end

  def engage_changeset(spawn) do
    spawn
    |> change(state: :engaged)
  end

  def kill_changeset(spawn, next_spawn_after) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    spawn
    |> change(state: :killed, killed_at: now, next_spawn_after: next_spawn_after)
  end

  def reset_changeset(spawn) do
    spawn
    |> change(
      state: :waiting,
      spawn_window_start: nil,
      spawn_window_end: nil,
      spawned_at: nil,
      killed_at: nil
    )
  end

  def valid_states, do: @states
end
