defmodule BezgelorDb.Schema.Account do
  @moduledoc """
  Database schema for user accounts.

  ## Overview

  Accounts represent registered users. Each account can have multiple
  characters. Authentication uses SRP6 - the password is never stored,
  only a verifier derived from it.

  ## Fields

  - `email` - Unique email address (lowercased)
  - `salt` - SRP6 salt (hex string)
  - `verifier` - SRP6 password verifier (hex string)
  - `game_token` - Current game session token
  - `session_key` - Current session key for packet encryption

  ## Example

      # Creating a new account
      {salt, verifier} = BezgelorCrypto.Password.generate_salt_and_verifier(email, password)

      %Account{}
      |> Account.changeset(%{email: email, salt: salt, verifier: verifier})
      |> Repo.insert()
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          email: String.t() | nil,
          salt: String.t() | nil,
          verifier: String.t() | nil,
          game_token: String.t() | nil,
          session_key: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "accounts" do
    field :email, :string
    field :salt, :string
    field :verifier, :string
    field :game_token, :string
    field :session_key, :string

    has_many :suspensions, BezgelorDb.Schema.AccountSuspension

    timestamps(type: :utc_datetime)
  end

  @doc """
  Build a changeset for creating or updating an account.

  ## Validations

  - Email is required and must be valid format
  - Email is lowercased for consistency
  - Salt and verifier are required for new accounts
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(account, attrs) do
    account
    |> cast(attrs, [:email, :salt, :verifier, :game_token, :session_key])
    |> validate_required([:email, :salt, :verifier])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/, message: "has invalid format")
    |> update_change(:email, &String.downcase/1)
    |> unique_constraint(:email)
  end

  @doc """
  Changeset for updating session information only.
  """
  @spec session_changeset(t(), map()) :: Ecto.Changeset.t()
  def session_changeset(account, attrs) do
    account
    |> cast(attrs, [:game_token, :session_key])
  end
end
