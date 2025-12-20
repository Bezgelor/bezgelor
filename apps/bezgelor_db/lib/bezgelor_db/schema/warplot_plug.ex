defmodule BezgelorDb.Schema.WarplotPlug do
  @moduledoc """
  Schema for warplot plug installations.

  Plugs are strategic structures that can be installed in warplot sockets.
  They provide various combat advantages during warplot battles.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BezgelorDb.Schema.Warplot

  @type t :: %__MODULE__{
          id: integer() | nil,
          warplot_id: integer(),
          plug_id: integer(),
          socket_id: integer(),
          tier: integer(),
          health_percent: integer(),
          installed_at: DateTime.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @max_tier 3
  @socket_count 8

  schema "warplot_plugs" do
    belongs_to(:warplot, Warplot)

    field(:plug_id, :integer)
    field(:socket_id, :integer)
    field(:tier, :integer, default: 1)
    field(:health_percent, :integer, default: 100)
    field(:installed_at, :utc_datetime)

    timestamps()
  end

  @required_fields [:warplot_id, :plug_id, :socket_id, :installed_at]
  @optional_fields [:tier, :health_percent]

  @doc """
  Creates a changeset for a warplot plug.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(plug, attrs) do
    plug
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_number(:socket_id,
      greater_than_or_equal_to: 1,
      less_than_or_equal_to: @socket_count
    )
    |> validate_number(:tier, greater_than_or_equal_to: 1, less_than_or_equal_to: @max_tier)
    |> validate_number(:health_percent, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> unique_constraint([:warplot_id, :socket_id])
    |> foreign_key_constraint(:warplot_id)
  end

  @doc """
  Upgrades the plug tier.
  """
  @spec upgrade(t()) :: {:ok, Ecto.Changeset.t()} | {:error, :max_tier}
  def upgrade(%__MODULE__{tier: tier}) when tier >= @max_tier do
    {:error, :max_tier}
  end

  def upgrade(plug) do
    {:ok, change(plug, tier: plug.tier + 1)}
  end

  @doc """
  Applies damage to the plug.
  """
  @spec apply_damage(t(), integer()) :: Ecto.Changeset.t()
  def apply_damage(plug, damage_percent) do
    new_health = max(0, plug.health_percent - damage_percent)
    change(plug, health_percent: new_health)
  end

  @doc """
  Repairs the plug.
  """
  @spec repair(t(), integer()) :: Ecto.Changeset.t()
  def repair(plug, repair_percent) do
    new_health = min(100, plug.health_percent + repair_percent)
    change(plug, health_percent: new_health)
  end

  @doc """
  Fully repairs the plug.
  """
  @spec full_repair(t()) :: Ecto.Changeset.t()
  def full_repair(plug) do
    change(plug, health_percent: 100)
  end

  @doc """
  Checks if plug is destroyed.
  """
  @spec destroyed?(t()) :: boolean()
  def destroyed?(%__MODULE__{health_percent: 0}), do: true
  def destroyed?(%__MODULE__{}), do: false

  @doc """
  Checks if plug is damaged.
  """
  @spec damaged?(t()) :: boolean()
  def damaged?(%__MODULE__{health_percent: hp}) when hp < 100, do: true
  def damaged?(%__MODULE__{}), do: false

  @doc """
  Returns max tier constant.
  """
  @spec max_tier() :: integer()
  def max_tier, do: @max_tier

  @doc """
  Returns socket count constant.
  """
  @spec socket_count() :: integer()
  def socket_count, do: @socket_count
end
