defmodule BezgelorDb.Schema.WorkOrder do
  @moduledoc """
  Schema for tradeskill work orders (daily crafting quests).

  Work orders are generated daily and expire after 24 hours.
  Players complete them by crafting the required items.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BezgelorDb.Schema.Character

  @type t :: %__MODULE__{}

  schema "work_orders" do
    belongs_to(:character, Character)

    field(:work_order_id, :integer)
    field(:profession_id, :integer)
    field(:quantity_required, :integer)
    field(:quantity_completed, :integer, default: 0)
    field(:status, Ecto.Enum, values: [:active, :completed, :expired], default: :active)
    field(:expires_at, :utc_datetime)
    field(:accepted_at, :utc_datetime)

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(character_id work_order_id profession_id quantity_required expires_at)a
  @optional_fields ~w(quantity_completed status accepted_at)a

  @doc """
  Build a changeset for creating a work order.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(work_order, attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    work_order
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_number(:quantity_required, greater_than: 0)
    |> validate_number(:quantity_completed, greater_than_or_equal_to: 0)
    |> put_default_accepted_at(now)
    |> foreign_key_constraint(:character_id)
  end

  defp put_default_accepted_at(changeset, now) do
    if get_field(changeset, :accepted_at) do
      changeset
    else
      put_change(changeset, :accepted_at, now)
    end
  end

  @doc """
  Changeset for updating progress.
  """
  @spec progress_changeset(t(), integer()) :: Ecto.Changeset.t()
  def progress_changeset(work_order, quantity_completed) do
    change(work_order, quantity_completed: quantity_completed)
  end

  @doc """
  Changeset for marking as completed.
  """
  @spec complete_changeset(t()) :: Ecto.Changeset.t()
  def complete_changeset(work_order) do
    change(work_order, status: :completed)
  end

  @doc """
  Changeset for marking as expired.
  """
  @spec expire_changeset(t()) :: Ecto.Changeset.t()
  def expire_changeset(work_order) do
    change(work_order, status: :expired)
  end
end
