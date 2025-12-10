defmodule BezgelorDb.Schema.AccountSuspension do
  @moduledoc """
  Database schema for account suspensions and bans.

  ## Overview

  Suspensions track temporary or permanent restrictions on accounts.
  A permanent ban has `end_time = nil`.

  ## Fields

  - `account_id` - Reference to the suspended account
  - `reason` - Human-readable reason for suspension
  - `start_time` - When the suspension began
  - `end_time` - When the suspension ends (nil = permanent ban)

  ## Example

      # Temporary suspension
      %AccountSuspension{
        account_id: 123,
        reason: "Terms of service violation",
        start_time: ~U[2024-01-01 00:00:00Z],
        end_time: ~U[2024-01-08 00:00:00Z]  # 7-day suspension
      }

      # Permanent ban
      %AccountSuspension{
        account_id: 456,
        reason: "Cheating",
        start_time: ~U[2024-01-01 00:00:00Z],
        end_time: nil  # Permanent
      }
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BezgelorDb.Schema.Account

  @type t :: %__MODULE__{
          id: integer() | nil,
          account_id: integer() | nil,
          account: Account.t() | Ecto.Association.NotLoaded.t() | nil,
          reason: String.t() | nil,
          start_time: DateTime.t() | nil,
          end_time: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "account_suspensions" do
    belongs_to :account, Account
    field :reason, :string
    field :start_time, :utc_datetime
    field :end_time, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc """
  Build a changeset for creating or updating a suspension.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(suspension, attrs) do
    suspension
    |> cast(attrs, [:account_id, :reason, :start_time, :end_time])
    |> validate_required([:account_id, :start_time])
    |> foreign_key_constraint(:account_id)
  end

  @doc """
  Check if this suspension is currently active.
  """
  @spec active?(t()) :: boolean()
  def active?(%__MODULE__{end_time: nil}), do: true  # Permanent ban

  def active?(%__MODULE__{start_time: start_time, end_time: end_time}) do
    now = DateTime.utc_now()
    DateTime.compare(start_time, now) != :gt and DateTime.compare(end_time, now) == :gt
  end

  @doc """
  Check if this is a permanent ban.
  """
  @spec permanent?(t()) :: boolean()
  def permanent?(%__MODULE__{end_time: nil}), do: true
  def permanent?(_), do: false

  @doc """
  Calculate remaining days for a temporary suspension.
  Returns 0 for permanent bans or expired suspensions.
  """
  @spec remaining_days(t()) :: float()
  def remaining_days(%__MODULE__{end_time: nil}), do: 0.0

  def remaining_days(%__MODULE__{end_time: end_time}) do
    now = DateTime.utc_now()
    diff_seconds = DateTime.diff(end_time, now, :second)
    if diff_seconds > 0, do: diff_seconds / 86400.0, else: 0.0
  end
end
