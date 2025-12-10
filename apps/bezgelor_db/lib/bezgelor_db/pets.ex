defmodule BezgelorDb.Pets do
  @moduledoc """
  Active pet management with XP and leveling.
  """

  alias BezgelorDb.Repo
  alias BezgelorDb.Schema.ActivePet
  alias BezgelorDb.Collections

  @xp_per_level 100

  @spec get_active_pet(integer()) :: ActivePet.t() | nil
  def get_active_pet(character_id) do
    Repo.get_by(ActivePet, character_id: character_id)
  end

  @spec set_active_pet(integer(), integer(), integer()) ::
          {:ok, ActivePet.t()} | {:error, :not_owned | term()}
  def set_active_pet(character_id, account_id, pet_id) do
    if Collections.owns_pet?(account_id, character_id, pet_id) do
      case get_active_pet(character_id) do
        nil ->
          %ActivePet{}
          |> ActivePet.changeset(%{character_id: character_id, pet_id: pet_id})
          |> Repo.insert()

        existing ->
          existing
          |> ActivePet.changeset(%{pet_id: pet_id, level: 1, xp: 0, nickname: nil})
          |> Repo.update()
      end
    else
      {:error, :not_owned}
    end
  end

  @spec clear_active_pet(integer()) :: :ok
  def clear_active_pet(character_id) do
    case get_active_pet(character_id) do
      nil -> :ok
      pet ->
        Repo.delete(pet)
        :ok
    end
  end

  @spec award_pet_xp(integer(), integer()) ::
          {:ok, ActivePet.t(), :xp_gained | :level_up} | {:error, :no_active_pet | term()}
  def award_pet_xp(character_id, xp_amount) do
    case get_active_pet(character_id) do
      nil ->
        {:error, :no_active_pet}

      pet ->
        new_xp = pet.xp + xp_amount
        {new_level, final_xp, leveled_up} = calculate_level_up(pet.level, new_xp)

        result =
          pet
          |> ActivePet.xp_changeset(final_xp, new_level)
          |> Repo.update()

        case result do
          {:ok, updated_pet} ->
            event = if leveled_up, do: :level_up, else: :xp_gained
            {:ok, updated_pet, event}

          {:error, _} = error ->
            error
        end
    end
  end

  @spec set_nickname(integer(), String.t() | nil) ::
          {:ok, ActivePet.t()} | {:error, :no_active_pet | term()}
  def set_nickname(character_id, nickname) do
    case get_active_pet(character_id) do
      nil ->
        {:error, :no_active_pet}

      pet ->
        pet
        |> ActivePet.nickname_changeset(nickname)
        |> Repo.update()
    end
  end

  defp calculate_level_up(level, xp) do
    do_calculate_level_up(level, xp, false)
  end

  defp do_calculate_level_up(level, xp, _leveled_up) when xp >= @xp_per_level do
    do_calculate_level_up(level + 1, xp - @xp_per_level, true)
  end

  defp do_calculate_level_up(level, xp, leveled_up) do
    {level, xp, leveled_up}
  end
end
