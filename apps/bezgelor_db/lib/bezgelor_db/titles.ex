defmodule BezgelorDb.Titles do
  @moduledoc """
  Title management context.
  """
  import Ecto.Query

  alias BezgelorDb.Repo
  alias BezgelorDb.Schema.{Account, AccountTitle}

  @doc "Get all unlocked titles for an account."
  @spec get_titles(integer()) :: [AccountTitle.t()]
  def get_titles(account_id) do
    AccountTitle
    |> where([t], t.account_id == ^account_id)
    |> order_by([t], desc: t.unlocked_at)
    |> Repo.all()
  end

  @doc "Check if account has unlocked a title."
  @spec has_title?(integer(), integer()) :: boolean()
  def has_title?(account_id, title_id) do
    AccountTitle
    |> where([t], t.account_id == ^account_id and t.title_id == ^title_id)
    |> Repo.exists?()
  end

  @doc "Grant a title to an account. Returns {:already_owned, title} if already unlocked."
  @spec grant_title(integer(), integer()) ::
          {:ok, AccountTitle.t()} | {:already_owned, AccountTitle.t()} | {:error, term()}
  def grant_title(account_id, title_id) do
    case Repo.get_by(AccountTitle, account_id: account_id, title_id: title_id) do
      nil ->
        %AccountTitle{}
        |> AccountTitle.changeset(%{
          account_id: account_id,
          title_id: title_id,
          unlocked_at: DateTime.utc_now()
        })
        |> Repo.insert()

      existing ->
        {:already_owned, existing}
    end
  end

  @doc "Set the active displayed title. Pass nil to clear."
  @spec set_active_title(integer(), integer() | nil) ::
          {:ok, Account.t()} | {:error, :not_owned | term()}
  def set_active_title(account_id, nil) do
    Account
    |> Repo.get!(account_id)
    |> Ecto.Changeset.change(active_title_id: nil)
    |> Repo.update()
  end

  def set_active_title(account_id, title_id) do
    if has_title?(account_id, title_id) do
      Account
      |> Repo.get!(account_id)
      |> Ecto.Changeset.change(active_title_id: title_id)
      |> Repo.update()
    else
      {:error, :not_owned}
    end
  end

  @doc "Get the active title ID for an account."
  @spec get_active_title(integer()) :: integer() | nil
  def get_active_title(account_id) do
    Account
    |> where([a], a.id == ^account_id)
    |> select([a], a.active_title_id)
    |> Repo.one()
  end
end
