defmodule BezgelorDb.Schema.PvpSeason do
  @moduledoc """
  Schema for PvP seasons.

  Seasons track competitive PvP periods with:
  - Start and end dates
  - Rating cutoffs for rewards
  - Title and mount rewards
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          season_number: integer(),
          name: String.t(),
          starts_at: DateTime.t(),
          ends_at: DateTime.t(),
          is_active: boolean(),
          gladiator_cutoff: integer(),
          duelist_cutoff: integer(),
          rival_cutoff: integer(),
          challenger_cutoff: integer(),
          gladiator_title_id: integer() | nil,
          gladiator_mount_id: integer() | nil,
          duelist_title_id: integer() | nil,
          rival_title_id: integer() | nil,
          challenger_title_id: integer() | nil,
          conquest_cap: integer(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  # Default rating cutoffs (top X%)
  # Top 0.5%
  @gladiator_cutoff 2400
  # Top 3%
  @duelist_cutoff 2100
  # Top 10%
  @rival_cutoff 1800
  # Top 35%
  @challenger_cutoff 1500

  schema "pvp_seasons" do
    field(:season_number, :integer)
    field(:name, :string)
    field(:starts_at, :utc_datetime)
    field(:ends_at, :utc_datetime)
    field(:is_active, :boolean, default: false)

    # Rating cutoffs for titles
    field(:gladiator_cutoff, :integer, default: @gladiator_cutoff)
    field(:duelist_cutoff, :integer, default: @duelist_cutoff)
    field(:rival_cutoff, :integer, default: @rival_cutoff)
    field(:challenger_cutoff, :integer, default: @challenger_cutoff)

    # Reward IDs
    field(:gladiator_title_id, :integer)
    field(:gladiator_mount_id, :integer)
    field(:duelist_title_id, :integer)
    field(:rival_title_id, :integer)
    field(:challenger_title_id, :integer)

    # Weekly caps
    field(:conquest_cap, :integer, default: 1800)

    timestamps()
  end

  @required_fields [:season_number, :name, :starts_at, :ends_at]
  @optional_fields [
    :is_active,
    :gladiator_cutoff,
    :duelist_cutoff,
    :rival_cutoff,
    :challenger_cutoff,
    :gladiator_title_id,
    :gladiator_mount_id,
    :duelist_title_id,
    :rival_title_id,
    :challenger_title_id,
    :conquest_cap
  ]

  @doc """
  Creates a changeset for a PvP season.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(season, attrs) do
    season
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_number(:season_number, greater_than: 0)
    |> validate_number(:gladiator_cutoff, greater_than: 0)
    |> validate_number(:duelist_cutoff, greater_than: 0)
    |> validate_number(:rival_cutoff, greater_than: 0)
    |> validate_number(:challenger_cutoff, greater_than: 0)
    |> validate_number(:conquest_cap, greater_than: 0)
    |> validate_date_order()
    |> unique_constraint(:season_number)
  end

  @doc """
  Activates the season.
  """
  @spec activate(t()) :: Ecto.Changeset.t()
  def activate(season) do
    change(season, is_active: true)
  end

  @doc """
  Deactivates the season.
  """
  @spec deactivate(t()) :: Ecto.Changeset.t()
  def deactivate(season) do
    change(season, is_active: false)
  end

  @doc """
  Determines reward tier for a rating.
  """
  @spec get_reward_tier(t(), integer()) :: atom()
  def get_reward_tier(season, rating) do
    cond do
      rating >= season.gladiator_cutoff -> :gladiator
      rating >= season.duelist_cutoff -> :duelist
      rating >= season.rival_cutoff -> :rival
      rating >= season.challenger_cutoff -> :challenger
      true -> :none
    end
  end

  @doc """
  Gets title ID for a reward tier.
  """
  @spec get_title_id(t(), atom()) :: integer() | nil
  def get_title_id(season, :gladiator), do: season.gladiator_title_id
  def get_title_id(season, :duelist), do: season.duelist_title_id
  def get_title_id(season, :rival), do: season.rival_title_id
  def get_title_id(season, :challenger), do: season.challenger_title_id
  def get_title_id(_season, _tier), do: nil

  @doc """
  Gets mount ID for gladiator tier.
  """
  @spec get_mount_id(t()) :: integer() | nil
  def get_mount_id(season), do: season.gladiator_mount_id

  @doc """
  Checks if season is currently active based on dates.
  """
  @spec current?(t()) :: boolean()
  def current?(season) do
    now = DateTime.utc_now()

    DateTime.compare(now, season.starts_at) != :lt and
      DateTime.compare(now, season.ends_at) == :lt
  end

  @doc """
  Checks if season has ended.
  """
  @spec ended?(t()) :: boolean()
  def ended?(season) do
    DateTime.compare(DateTime.utc_now(), season.ends_at) != :lt
  end

  @doc """
  Checks if season hasn't started yet.
  """
  @spec upcoming?(t()) :: boolean()
  def upcoming?(season) do
    DateTime.compare(DateTime.utc_now(), season.starts_at) == :lt
  end

  @doc """
  Returns days remaining in season.
  """
  @spec days_remaining(t()) :: integer()
  def days_remaining(season) do
    max(0, DateTime.diff(season.ends_at, DateTime.utc_now(), :day))
  end

  @doc """
  Returns default cutoffs.
  """
  @spec default_cutoffs() :: map()
  def default_cutoffs do
    %{
      gladiator: @gladiator_cutoff,
      duelist: @duelist_cutoff,
      rival: @rival_cutoff,
      challenger: @challenger_cutoff
    }
  end

  # Private validation

  defp validate_date_order(changeset) do
    starts_at = get_field(changeset, :starts_at)
    ends_at = get_field(changeset, :ends_at)

    if starts_at && ends_at && DateTime.compare(starts_at, ends_at) != :lt do
      add_error(changeset, :ends_at, "must be after start date")
    else
      changeset
    end
  end
end
