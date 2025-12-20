defmodule BezgelorDb.Schema.EventParticipation do
  @moduledoc """
  Player participation in a public event.

  Tracks contribution score, combat stats, completed objectives,
  and reward tier for each participant.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias BezgelorDb.Schema.{EventInstance, Character}

  @reward_tiers [:gold, :silver, :bronze, :participation]

  schema "event_participations" do
    belongs_to(:event_instance, EventInstance)
    belongs_to(:character, Character)

    field(:contribution_score, :integer, default: 0)
    field(:kills, :integer, default: 0)
    field(:damage_dealt, :integer, default: 0)
    field(:healing_done, :integer, default: 0)
    field(:objectives_completed, {:array, :integer}, default: [])

    field(:reward_tier, Ecto.Enum, values: @reward_tiers)
    field(:rewards_claimed, :boolean, default: false)
    field(:joined_at, :utc_datetime)
    field(:last_activity_at, :utc_datetime)

    timestamps(type: :utc_datetime)
  end

  def changeset(participation, attrs) do
    participation
    |> cast(attrs, [
      :event_instance_id,
      :character_id,
      :contribution_score,
      :kills,
      :damage_dealt,
      :healing_done,
      :objectives_completed,
      :reward_tier,
      :rewards_claimed,
      :joined_at,
      :last_activity_at
    ])
    |> validate_required([:event_instance_id, :character_id])
    |> validate_number(:contribution_score, greater_than_or_equal_to: 0)
    |> validate_number(:kills, greater_than_or_equal_to: 0)
    |> validate_number(:damage_dealt, greater_than_or_equal_to: 0)
    |> validate_number(:healing_done, greater_than_or_equal_to: 0)
    |> unique_constraint([:event_instance_id, :character_id])
    |> foreign_key_constraint(:event_instance_id)
    |> foreign_key_constraint(:character_id)
  end

  def contribute_changeset(participation, points) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    new_score = participation.contribution_score + points

    participation
    |> change(contribution_score: new_score, last_activity_at: now)
  end

  def kill_changeset(participation, contribution_points) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    participation
    |> change(
      kills: participation.kills + 1,
      contribution_score: participation.contribution_score + contribution_points,
      last_activity_at: now
    )
  end

  def damage_changeset(participation, damage, contribution_points) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    participation
    |> change(
      damage_dealt: participation.damage_dealt + damage,
      contribution_score: participation.contribution_score + contribution_points,
      last_activity_at: now
    )
  end

  def healing_changeset(participation, healing, contribution_points) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    participation
    |> change(
      healing_done: participation.healing_done + healing,
      contribution_score: participation.contribution_score + contribution_points,
      last_activity_at: now
    )
  end

  def complete_objective_changeset(participation, objective_index, contribution_points) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    objectives =
      if objective_index in participation.objectives_completed do
        participation.objectives_completed
      else
        [objective_index | participation.objectives_completed]
      end

    participation
    |> change(
      objectives_completed: objectives,
      contribution_score: participation.contribution_score + contribution_points,
      last_activity_at: now
    )
  end

  def set_tier_changeset(participation, tier) do
    participation
    |> change(reward_tier: tier)
  end

  def claim_rewards_changeset(participation) do
    participation
    |> change(rewards_claimed: true)
  end

  def valid_reward_tiers, do: @reward_tiers
end
