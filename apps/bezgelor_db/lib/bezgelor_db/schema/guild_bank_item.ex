defmodule BezgelorDb.Schema.GuildBankItem do
  @moduledoc """
  Schema for guild bank item storage.

  ## Bank Tabs

  Each guild can have up to 6 bank tabs, each with 98 slots.
  Tabs must be unlocked with influence.

  ## Item Tracking

  Items in the guild bank track who deposited them for logging.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @slots_per_tab 98

  schema "guild_bank_items" do
    belongs_to :guild, BezgelorDb.Schema.Guild

    # Position
    field :tab_index, :integer  # 0-5
    field :slot_index, :integer  # 0-97

    # Item data (references BezgelorData)
    field :item_id, :integer
    field :stack_count, :integer, default: 1

    # Extended item data
    field :item_data, :map, default: %{}

    # Who deposited this item
    field :depositor_id, :integer

    timestamps(type: :utc_datetime)
  end

  def changeset(item, attrs) do
    item
    |> cast(attrs, [:guild_id, :tab_index, :slot_index, :item_id, :stack_count, :item_data, :depositor_id])
    |> validate_required([:guild_id, :tab_index, :slot_index, :item_id])
    |> validate_number(:tab_index, greater_than_or_equal_to: 0, less_than: 6)
    |> validate_number(:slot_index, greater_than_or_equal_to: 0, less_than: @slots_per_tab)
    |> validate_number(:stack_count, greater_than: 0)
    |> foreign_key_constraint(:guild_id)
    |> unique_constraint([:guild_id, :tab_index, :slot_index], name: :guild_bank_items_guild_id_tab_index_slot_index_index)
  end

  def stack_changeset(item, new_count) do
    item
    |> cast(%{stack_count: new_count}, [:stack_count])
    |> validate_number(:stack_count, greater_than: 0)
  end

  def move_changeset(item, new_tab, new_slot) do
    item
    |> cast(%{tab_index: new_tab, slot_index: new_slot}, [:tab_index, :slot_index])
    |> validate_number(:tab_index, greater_than_or_equal_to: 0, less_than: 6)
    |> validate_number(:slot_index, greater_than_or_equal_to: 0, less_than: @slots_per_tab)
  end

  def slots_per_tab, do: @slots_per_tab
end
