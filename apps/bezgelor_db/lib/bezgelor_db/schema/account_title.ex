defmodule BezgelorDb.Schema.AccountTitle do
  @moduledoc """
  Tracks titles unlocked by an account.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias BezgelorDb.Schema.Account

  schema "account_titles" do
    belongs_to :account, Account
    field :title_id, :integer
    field :unlocked_at, :utc_datetime

    timestamps()
  end

  @doc "Changeset for creating a new account title."
  def changeset(account_title, attrs) do
    account_title
    |> cast(attrs, [:account_id, :title_id, :unlocked_at])
    |> validate_required([:account_id, :title_id, :unlocked_at])
    |> unique_constraint([:account_id, :title_id])
  end
end
