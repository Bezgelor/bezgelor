defmodule BezgelorDb.Schema.PromoCode do
  @moduledoc """
  Promo code schema for discount codes, item grants, and currency bonuses.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @code_types ~w(discount item currency)

  schema "promo_codes" do
    field(:code, :string)
    field(:description, :string)
    field(:code_type, :string)
    field(:discount_percent, :integer)
    field(:discount_amount, :integer)
    field(:granted_item_id, :integer)
    field(:granted_currency_amount, :integer)
    field(:granted_currency_type, :string)
    field(:max_uses, :integer)
    field(:uses_per_account, :integer, default: 1)
    field(:current_uses, :integer, default: 0)
    field(:starts_at, :utc_datetime)
    field(:ends_at, :utc_datetime)
    field(:is_active, :boolean, default: true)
    field(:min_purchase_amount, :integer)
    field(:applies_to, :map, default: %{})

    has_many(:redemptions, BezgelorDb.Schema.PromoRedemption)

    timestamps(type: :utc_datetime)
  end

  def changeset(promo_code, attrs) do
    promo_code
    |> cast(attrs, [
      :code,
      :description,
      :code_type,
      :discount_percent,
      :discount_amount,
      :granted_item_id,
      :granted_currency_amount,
      :granted_currency_type,
      :max_uses,
      :uses_per_account,
      :current_uses,
      :starts_at,
      :ends_at,
      :is_active,
      :min_purchase_amount,
      :applies_to
    ])
    |> validate_required([:code, :code_type])
    |> validate_inclusion(:code_type, @code_types)
    |> validate_inclusion(:granted_currency_type, ["premium", "bonus"], allow_nil: true)
    |> validate_number(:discount_percent, greater_than: 0, less_than_or_equal_to: 100)
    |> validate_number(:discount_amount, greater_than: 0)
    |> validate_number(:max_uses, greater_than: 0)
    |> validate_number(:uses_per_account, greater_than: 0)
    |> validate_number(:min_purchase_amount, greater_than_or_equal_to: 0)
    |> unique_constraint(:code)
    |> normalize_code()
    |> validate_code_type_fields()
  end

  defp normalize_code(changeset) do
    case get_change(changeset, :code) do
      nil -> changeset
      code -> put_change(changeset, :code, String.upcase(code))
    end
  end

  defp validate_code_type_fields(changeset) do
    code_type = get_field(changeset, :code_type)

    case code_type do
      "discount" ->
        if is_nil(get_field(changeset, :discount_percent)) and
             is_nil(get_field(changeset, :discount_amount)) do
          add_error(
            changeset,
            :discount_percent,
            "discount codes require discount_percent or discount_amount"
          )
        else
          changeset
        end

      "item" ->
        if is_nil(get_field(changeset, :granted_item_id)) do
          add_error(changeset, :granted_item_id, "item codes require granted_item_id")
        else
          changeset
        end

      "currency" ->
        cond do
          is_nil(get_field(changeset, :granted_currency_amount)) ->
            add_error(
              changeset,
              :granted_currency_amount,
              "currency codes require granted_currency_amount"
            )

          is_nil(get_field(changeset, :granted_currency_type)) ->
            add_error(
              changeset,
              :granted_currency_type,
              "currency codes require granted_currency_type"
            )

          true ->
            changeset
        end

      _ ->
        changeset
    end
  end

  def code_types, do: @code_types

  @doc "Check if promo code can be used."
  def usable?(%__MODULE__{is_active: false}), do: false

  def usable?(%__MODULE__{max_uses: max, current_uses: current})
      when not is_nil(max) and current >= max, do: false

  def usable?(%__MODULE__{starts_at: starts_at, ends_at: ends_at}) do
    now = DateTime.utc_now()
    within_start = is_nil(starts_at) or DateTime.compare(now, starts_at) != :lt
    within_end = is_nil(ends_at) or DateTime.compare(now, ends_at) != :gt
    within_start and within_end
  end
end
