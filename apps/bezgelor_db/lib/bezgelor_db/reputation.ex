defmodule BezgelorDb.Reputation do
  @moduledoc """
  Reputation management context.
  """
  import Ecto.Query
  alias BezgelorDb.Repo
  alias BezgelorDb.Schema.Reputation, as: RepSchema
  alias BezgelorCore.Reputation, as: RepCore

  @spec get_reputations(integer()) :: [RepSchema.t()]
  def get_reputations(character_id) do
    RepSchema
    |> where([r], r.character_id == ^character_id)
    |> Repo.all()
  end

  @spec get_reputation(integer(), integer()) :: RepSchema.t() | nil
  def get_reputation(character_id, faction_id) do
    Repo.get_by(RepSchema, character_id: character_id, faction_id: faction_id)
  end

  @spec get_standing(integer(), integer()) :: integer()
  def get_standing(character_id, faction_id) do
    case get_reputation(character_id, faction_id) do
      nil -> 0
      rep -> rep.standing
    end
  end

  @spec get_level(integer(), integer()) :: RepCore.level()
  def get_level(character_id, faction_id) do
    character_id
    |> get_standing(faction_id)
    |> RepCore.standing_to_level()
  end

  @spec modify_reputation(integer(), integer(), integer()) :: {:ok, RepSchema.t()} | {:error, term()}
  def modify_reputation(character_id, faction_id, delta) do
    case get_reputation(character_id, faction_id) do
      nil ->
        %RepSchema{}
        |> RepSchema.changeset(%{
          character_id: character_id,
          faction_id: faction_id,
          standing: clamp(delta)
        })
        |> Repo.insert()

      rep ->
        new_standing = clamp(rep.standing + delta)
        rep |> RepSchema.changeset(%{standing: new_standing}) |> Repo.update()
    end
  end

  @spec set_reputation(integer(), integer(), integer()) :: {:ok, RepSchema.t()} | {:error, term()}
  def set_reputation(character_id, faction_id, standing) do
    case get_reputation(character_id, faction_id) do
      nil ->
        %RepSchema{}
        |> RepSchema.changeset(%{
          character_id: character_id,
          faction_id: faction_id,
          standing: clamp(standing)
        })
        |> Repo.insert()

      rep ->
        rep |> RepSchema.changeset(%{standing: clamp(standing)}) |> Repo.update()
    end
  end

  @doc "Check if character meets reputation requirement for a faction."
  @spec meets_requirement?(integer(), integer(), RepCore.level()) :: boolean()
  def meets_requirement?(character_id, faction_id, required_level) do
    standing = get_standing(character_id, faction_id)
    RepCore.meets_requirement?(standing, required_level)
  end

  @doc "Get vendor discount for character with faction."
  @spec get_vendor_discount(integer(), integer()) :: float()
  def get_vendor_discount(character_id, faction_id) do
    standing = get_standing(character_id, faction_id)
    RepCore.vendor_discount_for_standing(standing)
  end

  @doc "Check if character can purchase from faction vendor."
  @spec can_purchase?(integer(), integer()) :: boolean()
  def can_purchase?(character_id, faction_id) do
    level = get_level(character_id, faction_id)
    RepCore.can_purchase?(level)
  end

  @doc "Check if character can interact with faction NPCs."
  @spec can_interact?(integer(), integer()) :: boolean()
  def can_interact?(character_id, faction_id) do
    level = get_level(character_id, faction_id)
    RepCore.can_interact?(level)
  end

  defp clamp(value) do
    value
    |> max(RepCore.min_standing())
    |> min(RepCore.max_standing())
  end
end
