defmodule BezgelorDb.Schema.GuildMember do
  @moduledoc """
  Schema for guild membership.

  Tracks which characters are in which guilds and their rank.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "guild_members" do
    belongs_to :guild, BezgelorDb.Schema.Guild
    belongs_to :character, BezgelorDb.Schema.Character

    # Rank index (0 = Guild Master, higher = lower rank)
    field :rank_index, :integer, default: 4

    # Notes (officer/public)
    field :officer_note, :string, default: ""
    field :public_note, :string, default: ""

    # Contribution tracking
    field :total_influence, :integer, default: 0  # Total influence contributed

    timestamps(type: :utc_datetime)
  end

  def changeset(member, attrs) do
    member
    |> cast(attrs, [:guild_id, :character_id, :rank_index, :officer_note, :public_note, :total_influence])
    |> validate_required([:guild_id, :character_id])
    |> validate_number(:rank_index, greater_than_or_equal_to: 0, less_than_or_equal_to: 9)
    |> validate_length(:officer_note, max: 200)
    |> validate_length(:public_note, max: 200)
    |> foreign_key_constraint(:guild_id)
    |> foreign_key_constraint(:character_id)
    |> unique_constraint([:character_id], name: :guild_members_character_id_index)
  end

  def rank_changeset(member, rank_index) do
    member
    |> cast(%{rank_index: rank_index}, [:rank_index])
    |> validate_number(:rank_index, greater_than_or_equal_to: 0, less_than_or_equal_to: 9)
  end

  def notes_changeset(member, officer_note, public_note) do
    member
    |> cast(%{officer_note: officer_note, public_note: public_note}, [:officer_note, :public_note])
    |> validate_length(:officer_note, max: 200)
    |> validate_length(:public_note, max: 200)
  end

  def influence_changeset(member, amount) do
    new_total = member.total_influence + amount

    member
    |> change(total_influence: new_total)
  end
end
