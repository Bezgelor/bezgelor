defmodule BezgelorDb.Schema.Bag do
  @moduledoc """
  Schema for character bags.

  ## Bag System

  Characters have:
  - Backpack (bag_index 0): Always present, size from character level
  - Bag slots 1-4: Equipped bags that add inventory space
  - Bank bags: Additional storage slots

  Each bag has a size determining how many items it can hold.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "bags" do
    belongs_to :character, BezgelorDb.Schema.Character

    # Bag position (0 = backpack, 1-4 = equipped bags, 10+ = bank bags)
    field :bag_index, :integer

    # Bag item template (nil for backpack)
    field :item_id, :integer

    # Bag capacity
    field :size, :integer, default: 12

    timestamps(type: :utc_datetime)
  end

  def changeset(bag, attrs) do
    bag
    |> cast(attrs, [:character_id, :bag_index, :item_id, :size])
    |> validate_required([:character_id, :bag_index, :size])
    |> validate_number(:bag_index, greater_than_or_equal_to: 0)
    |> validate_number(:size, greater_than: 0, less_than_or_equal_to: 100)
    |> foreign_key_constraint(:character_id)
    |> unique_constraint([:character_id, :bag_index], name: :bags_character_id_bag_index_index)
  end
end
