defmodule BezgelorDb.Schema.SchematicDiscovery do
  @moduledoc """
  Schema for tracking discovered schematics and variants.

  Supports both character-scoped and account-scoped discovery based on
  server configuration. The variant_id of 0 indicates the base schematic,
  while higher values represent discovered variants.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BezgelorDb.Schema.Character

  @type t :: %__MODULE__{}

  schema "schematic_discoveries" do
    belongs_to(:character, Character)

    field(:account_id, :integer)
    field(:schematic_id, :integer)
    field(:variant_id, :integer, default: 0)
    field(:discovered_at, :utc_datetime)

    timestamps(type: :utc_datetime)
  end

  @doc """
  Build a changeset for creating a discovery record.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(discovery, attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    discovery
    |> cast(attrs, [:character_id, :account_id, :schematic_id, :variant_id, :discovered_at])
    |> validate_required([:schematic_id])
    |> put_default(:discovered_at, now)
    |> put_default(:variant_id, 0)
    |> validate_scope()
    |> foreign_key_constraint(:character_id)
  end

  defp put_default(changeset, field, value) do
    if get_field(changeset, field) do
      changeset
    else
      put_change(changeset, field, value)
    end
  end

  defp validate_scope(changeset) do
    character_id = get_field(changeset, :character_id)
    account_id = get_field(changeset, :account_id)

    cond do
      character_id != nil -> changeset
      account_id != nil -> changeset
      true -> add_error(changeset, :base, "must have either character_id or account_id")
    end
  end
end
