defmodule BezgelorDb.Schema.CurrencyTransaction do
  @moduledoc """
  Schema for tracking currency transactions.

  Provides an audit trail for all currency changes in the game for:
  - Debugging economy issues
  - Detecting exploits and suspicious activity
  - Analyzing economic flow and balance
  - Supporting customer service investigations
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BezgelorDb.Schema.Character

  @type t :: %__MODULE__{
          id: integer() | nil,
          character_id: integer() | nil,
          currency_type: integer(),
          amount: integer(),
          balance_after: integer(),
          source_type: String.t(),
          source_id: integer() | nil,
          metadata: map() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @source_types ~w(vendor quest trade mail loot auction craft repair)

  schema "currency_transactions" do
    belongs_to(:character, Character)

    field(:currency_type, :integer)
    field(:amount, :integer)
    field(:balance_after, :integer)
    field(:source_type, :string)
    field(:source_id, :integer)
    field(:metadata, :map)

    timestamps(type: :utc_datetime)
  end

  @required_fields [:character_id, :currency_type, :amount, :balance_after, :source_type]
  @optional_fields [:source_id, :metadata]

  @doc """
  Creates a changeset for a currency transaction.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(transaction, attrs) do
    transaction
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:source_type, @source_types)
    |> validate_number(:balance_after, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:character_id)
  end

  @doc """
  Creates a transaction record for the current time.
  """
  @spec record(map()) :: Ecto.Changeset.t()
  def record(attrs) do
    changeset(%__MODULE__{}, attrs)
  end

  @doc """
  Checks if this was a gain (positive amount).
  """
  @spec gain?(t()) :: boolean()
  def gain?(%__MODULE__{amount: amount}), do: amount > 0

  @doc """
  Checks if this was a loss (negative amount).
  """
  @spec loss?(t()) :: boolean()
  def loss?(%__MODULE__{amount: amount}), do: amount < 0

  @doc """
  Checks if this transaction was from a vendor.
  """
  @spec from_vendor?(t()) :: boolean()
  def from_vendor?(%__MODULE__{source_type: source_type}), do: source_type == "vendor"

  @doc """
  Checks if this transaction was from a quest.
  """
  @spec from_quest?(t()) :: boolean()
  def from_quest?(%__MODULE__{source_type: source_type}), do: source_type == "quest"

  @doc """
  Checks if this transaction was from a trade.
  """
  @spec from_trade?(t()) :: boolean()
  def from_trade?(%__MODULE__{source_type: source_type}), do: source_type == "trade"

  @doc """
  Checks if this transaction was from mail.
  """
  @spec from_mail?(t()) :: boolean()
  def from_mail?(%__MODULE__{source_type: source_type}), do: source_type == "mail"

  @doc """
  Checks if this transaction was from loot.
  """
  @spec from_loot?(t()) :: boolean()
  def from_loot?(%__MODULE__{source_type: source_type}), do: source_type == "loot"

  @doc """
  Checks if this transaction was from auction.
  """
  @spec from_auction?(t()) :: boolean()
  def from_auction?(%__MODULE__{source_type: source_type}), do: source_type == "auction"

  @doc """
  Checks if this transaction was from crafting.
  """
  @spec from_craft?(t()) :: boolean()
  def from_craft?(%__MODULE__{source_type: source_type}), do: source_type == "craft"

  @doc """
  Checks if this transaction was from repair.
  """
  @spec from_repair?(t()) :: boolean()
  def from_repair?(%__MODULE__{source_type: source_type}), do: source_type == "repair"

  @doc """
  Returns the list of valid source types.
  """
  @spec source_types() :: [String.t()]
  def source_types, do: @source_types
end
