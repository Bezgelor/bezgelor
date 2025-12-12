defmodule BezgelorDb.Schema.CharacterCurrency do
  @moduledoc """
  Schema for character currencies.

  WildStar has various currency types:
  - Gold: Primary in-game currency
  - Elder Gems: Earned at max level
  - Renown: Group content reward
  - Prestige: PvP reward currency
  - Glory: Arena/Rated PvP currency
  - Crafting Vouchers: Tradeskill currency
  - War Coins: Warplot currency
  - Shade Silver: Shade's Eve event
  - Protostar Promissory Notes: Protostar event
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BezgelorDb.Schema.Character

  @type t :: %__MODULE__{}

  @currency_fields [
    :gold,
    :elder_gems,
    :renown,
    :prestige,
    :glory,
    :crafting_vouchers,
    :war_coins,
    :shade_silver,
    :protostar_promissory_notes
  ]

  @currency_info %{
    gold: %{name: "Gold", icon: "hero-currency-dollar", max: nil},
    elder_gems: %{name: "Elder Gems", icon: "hero-sparkles", max: 140},
    renown: %{name: "Renown", icon: "hero-star", max: nil},
    prestige: %{name: "Prestige", icon: "hero-trophy", max: nil},
    glory: %{name: "Glory", icon: "hero-fire", max: nil},
    crafting_vouchers: %{name: "Crafting Vouchers", icon: "hero-wrench", max: nil},
    war_coins: %{name: "War Coins", icon: "hero-shield-exclamation", max: nil},
    shade_silver: %{name: "Shade Silver", icon: "hero-moon", max: nil},
    protostar_promissory_notes: %{name: "Protostar Notes", icon: "hero-document-text", max: nil}
  }

  schema "character_currencies" do
    belongs_to :character, Character

    field :gold, :integer, default: 0
    field :elder_gems, :integer, default: 0
    field :renown, :integer, default: 0
    field :prestige, :integer, default: 0
    field :glory, :integer, default: 0
    field :crafting_vouchers, :integer, default: 0
    field :war_coins, :integer, default: 0
    field :shade_silver, :integer, default: 0
    field :protostar_promissory_notes, :integer, default: 0

    timestamps(type: :utc_datetime)
  end

  @doc "Returns list of all currency field atoms"
  def currency_fields, do: @currency_fields

  @doc "Returns info (name, icon, max) for a currency type"
  def currency_info(type) when is_atom(type), do: Map.get(@currency_info, type)
  def currency_info, do: @currency_info

  def changeset(currency, attrs) do
    currency
    |> cast(attrs, [:character_id | @currency_fields])
    |> validate_required([:character_id])
    |> validate_currencies()
    |> foreign_key_constraint(:character_id)
    |> unique_constraint(:character_id)
  end

  def modify_changeset(currency, currency_type, amount) when is_atom(currency_type) do
    current = Map.get(currency, currency_type, 0)
    new_amount = current + amount

    if new_amount < 0 do
      {:error, :insufficient_funds}
    else
      info = currency_info(currency_type)
      # Check max cap if applicable
      capped_amount = if info[:max], do: min(new_amount, info[:max]), else: new_amount
      {:ok, change(currency, [{currency_type, capped_amount}])}
    end
  end

  defp validate_currencies(changeset) do
    Enum.reduce(@currency_fields, changeset, fn field, cs ->
      validate_number(cs, field, greater_than_or_equal_to: 0)
    end)
  end
end
