defmodule BezgelorDb.Schema.EventCompletion do
  @moduledoc """
  Historical record of event completions per character.

  Tracks completion count by tier, best contribution score,
  and fastest completion time.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias BezgelorDb.Schema.Character

  schema "event_completions" do
    belongs_to(:character, Character)
    field(:event_id, :integer)

    field(:completion_count, :integer, default: 1)
    field(:gold_count, :integer, default: 0)
    field(:silver_count, :integer, default: 0)
    field(:bronze_count, :integer, default: 0)
    field(:best_contribution, :integer, default: 0)
    field(:fastest_completion_ms, :integer)
    field(:last_completed_at, :utc_datetime)

    timestamps(type: :utc_datetime)
  end

  def changeset(completion, attrs) do
    completion
    |> cast(attrs, [
      :character_id,
      :event_id,
      :completion_count,
      :gold_count,
      :silver_count,
      :bronze_count,
      :best_contribution,
      :fastest_completion_ms,
      :last_completed_at
    ])
    |> validate_required([:character_id, :event_id])
    |> validate_number(:completion_count, greater_than: 0)
    |> validate_number(:gold_count, greater_than_or_equal_to: 0)
    |> validate_number(:silver_count, greater_than_or_equal_to: 0)
    |> validate_number(:bronze_count, greater_than_or_equal_to: 0)
    |> validate_number(:best_contribution, greater_than_or_equal_to: 0)
    |> unique_constraint([:character_id, :event_id])
    |> foreign_key_constraint(:character_id)
  end

  def increment_changeset(completion, tier, contribution, duration_ms, completed_at) do
    tier_updates = tier_increment(tier)
    best = max(completion.best_contribution, contribution)

    fastest =
      case completion.fastest_completion_ms do
        nil -> duration_ms
        existing -> min(existing, duration_ms)
      end

    completion
    |> change(
      completion_count: completion.completion_count + 1,
      gold_count: completion.gold_count + tier_updates.gold,
      silver_count: completion.silver_count + tier_updates.silver,
      bronze_count: completion.bronze_count + tier_updates.bronze,
      best_contribution: best,
      fastest_completion_ms: fastest,
      last_completed_at: completed_at
    )
  end

  defp tier_increment(:gold), do: %{gold: 1, silver: 0, bronze: 0}
  defp tier_increment(:silver), do: %{gold: 0, silver: 1, bronze: 0}
  defp tier_increment(:bronze), do: %{gold: 0, silver: 0, bronze: 1}
  defp tier_increment(_), do: %{gold: 0, silver: 0, bronze: 0}
end
