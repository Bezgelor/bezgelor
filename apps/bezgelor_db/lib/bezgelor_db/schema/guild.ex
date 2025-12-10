defmodule BezgelorDb.Schema.Guild do
  @moduledoc """
  Schema for guild information.

  ## Guild Features

  - Custom name and tag (4-character abbreviation)
  - Configurable ranks with permissions
  - Guild bank with access controls
  - Message of the day (MOTD)
  - Guild influence currency

  ## Permissions System

  Permissions are stored as a bitfield per rank:
  - Invite (1)
  - Kick (2)
  - Promote (4)
  - Demote (8)
  - Edit ranks (16)
  - Edit MOTD (32)
  - Guild bank deposit (64)
  - Guild bank withdraw (128)
  - Disband (256)
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "guilds" do
    field :name, :string
    field :tag, :string  # 4 character abbreviation
    field :motd, :string, default: ""  # Message of the day
    field :influence, :integer, default: 0  # Guild currency

    # Leader character ID
    field :leader_id, :integer

    # Bank tabs unlocked (0-5)
    field :bank_tabs_unlocked, :integer, default: 1

    timestamps(type: :utc_datetime)
  end

  def changeset(guild, attrs) do
    guild
    |> cast(attrs, [:name, :tag, :motd, :influence, :leader_id, :bank_tabs_unlocked])
    |> validate_required([:name, :tag, :leader_id])
    |> validate_length(:name, min: 2, max: 32)
    |> validate_length(:tag, is: 4)
    |> validate_format(:tag, ~r/^[A-Z0-9]+$/, message: "must be uppercase letters and numbers only")
    |> validate_number(:bank_tabs_unlocked, greater_than_or_equal_to: 1, less_than_or_equal_to: 6)
    |> unique_constraint(:name)
    |> unique_constraint(:tag)
  end

  def motd_changeset(guild, motd) do
    guild
    |> cast(%{motd: motd}, [:motd])
    |> validate_length(:motd, max: 500)
  end

  def influence_changeset(guild, amount) do
    guild
    |> cast(%{influence: amount}, [:influence])
    |> validate_number(:influence, greater_than_or_equal_to: 0)
  end

  def leader_changeset(guild, new_leader_id) do
    guild
    |> change(leader_id: new_leader_id)
  end

  def bank_tab_changeset(guild, tabs) do
    guild
    |> cast(%{bank_tabs_unlocked: tabs}, [:bank_tabs_unlocked])
    |> validate_number(:bank_tabs_unlocked, greater_than_or_equal_to: 1, less_than_or_equal_to: 6)
  end
end
