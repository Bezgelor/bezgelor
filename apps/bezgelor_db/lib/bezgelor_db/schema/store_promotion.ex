defmodule BezgelorDb.Schema.StorePromotion do
  @moduledoc """
  Store promotion schema for time-limited sales, bundles, and bonus currency events.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @promotion_types ~w(sale bundle bonus_currency)

  schema "store_promotions" do
    field(:name, :string)
    field(:description, :string)
    field(:promotion_type, :string)
    field(:discount_percent, :integer)
    field(:discount_amount, :integer)
    field(:bonus_amount, :integer)
    field(:starts_at, :utc_datetime)
    field(:ends_at, :utc_datetime)
    field(:is_active, :boolean, default: true)
    field(:banner_image, :string)
    field(:applies_to, :map, default: %{})

    timestamps(type: :utc_datetime)
  end

  def changeset(promotion, attrs) do
    promotion
    |> cast(attrs, [
      :name,
      :description,
      :promotion_type,
      :discount_percent,
      :discount_amount,
      :bonus_amount,
      :starts_at,
      :ends_at,
      :is_active,
      :banner_image,
      :applies_to
    ])
    |> validate_required([:name, :promotion_type, :starts_at, :ends_at])
    |> validate_inclusion(:promotion_type, @promotion_types)
    |> validate_number(:discount_percent, greater_than: 0, less_than_or_equal_to: 100)
    |> validate_number(:discount_amount, greater_than: 0)
    |> validate_number(:bonus_amount, greater_than: 0)
    |> validate_dates()
    |> validate_promotion_value()
  end

  defp validate_dates(changeset) do
    starts_at = get_field(changeset, :starts_at)
    ends_at = get_field(changeset, :ends_at)

    if starts_at && ends_at && DateTime.compare(ends_at, starts_at) != :gt do
      add_error(changeset, :ends_at, "must be after starts_at")
    else
      changeset
    end
  end

  defp validate_promotion_value(changeset) do
    promotion_type = get_field(changeset, :promotion_type)
    discount_percent = get_field(changeset, :discount_percent)
    discount_amount = get_field(changeset, :discount_amount)
    bonus_amount = get_field(changeset, :bonus_amount)

    case promotion_type do
      "sale" when is_nil(discount_percent) and is_nil(discount_amount) ->
        add_error(
          changeset,
          :discount_percent,
          "sale promotions require discount_percent or discount_amount"
        )

      "bonus_currency" when is_nil(bonus_amount) ->
        add_error(changeset, :bonus_amount, "bonus_currency promotions require bonus_amount")

      _ ->
        changeset
    end
  end

  def promotion_types, do: @promotion_types

  @doc "Check if promotion is currently active."
  def active?(%__MODULE__{is_active: false}), do: false

  def active?(%__MODULE__{starts_at: starts_at, ends_at: ends_at}) do
    now = DateTime.utc_now()
    DateTime.compare(now, starts_at) != :lt and DateTime.compare(now, ends_at) != :gt
  end
end
