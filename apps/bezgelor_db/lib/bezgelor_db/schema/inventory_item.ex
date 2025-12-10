defmodule BezgelorDb.Schema.InventoryItem do
  @moduledoc """
  Schema for character inventory items.

  ## Slot Types

  Items can be in different containers:
  - `:equipped` - Worn equipment (armor, weapons)
  - `:bag` - Main inventory bags
  - `:bank` - Bank storage
  - `:trade` - Trade window (temporary)

  ## Stacking

  Stackable items share the same slot but track quantity.
  The `item_id` references the item template from game data.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @container_types [:equipped, :bag, :bank, :trade]

  schema "inventory_items" do
    belongs_to :character, BezgelorDb.Schema.Character

    # Item template reference (from BezgelorData)
    field :item_id, :integer

    # Location
    field :container_type, Ecto.Enum, values: @container_types, default: :bag
    field :bag_index, :integer, default: 0  # Which bag (0 = backpack, 1-4 = equipped bags)
    field :slot, :integer                    # Slot within bag/container

    # Stack info
    field :quantity, :integer, default: 1
    field :max_stack, :integer, default: 1

    # Item state
    field :durability, :integer, default: 100
    field :max_durability, :integer, default: 100
    field :bound, :boolean, default: false

    # Random properties (for randomized gear)
    field :random_seed, :integer
    field :enchant_id, :integer
    field :gem_ids, {:array, :integer}, default: []

    # Charges for consumables
    field :charges, :integer

    timestamps(type: :utc_datetime)
  end

  def changeset(item, attrs) do
    item
    |> cast(attrs, [
      :character_id, :item_id, :container_type, :bag_index, :slot,
      :quantity, :max_stack, :durability, :max_durability, :bound,
      :random_seed, :enchant_id, :gem_ids, :charges
    ])
    |> validate_required([:character_id, :item_id, :slot])
    |> validate_number(:quantity, greater_than: 0)
    |> validate_number(:slot, greater_than_or_equal_to: 0)
    |> validate_inclusion(:container_type, @container_types)
    |> foreign_key_constraint(:character_id)
    |> unique_constraint([:character_id, :container_type, :bag_index, :slot],
        name: :inventory_items_location_index)
  end

  def move_changeset(item, attrs) do
    item
    |> cast(attrs, [:container_type, :bag_index, :slot])
    |> validate_required([:container_type, :bag_index, :slot])
  end

  def stack_changeset(item, attrs) do
    item
    |> cast(attrs, [:quantity])
    |> validate_required([:quantity])
    |> validate_number(:quantity, greater_than: 0)
  end

  @doc "Get valid container types."
  def container_types, do: @container_types
end
