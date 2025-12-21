defmodule BezgelorDb.Mounts do
  @moduledoc """
  Active mount management with customization.
  """

  alias BezgelorDb.Repo
  alias BezgelorDb.Schema.ActiveMount
  alias BezgelorDb.Collections

  @spec get_active_mount(integer()) :: ActiveMount.t() | nil
  def get_active_mount(character_id) do
    Repo.get_by(ActiveMount, character_id: character_id)
  end

  @spec set_active_mount(integer(), integer(), integer()) ::
          {:ok, ActiveMount.t()} | {:error, :not_owned | term()}
  def set_active_mount(character_id, account_id, mount_id) do
    if Collections.owns_mount?(account_id, character_id, mount_id) do
      case get_active_mount(character_id) do
        nil ->
          %ActiveMount{}
          |> ActiveMount.changeset(%{character_id: character_id, mount_id: mount_id})
          |> Repo.insert()

        existing ->
          existing
          |> ActiveMount.changeset(%{mount_id: mount_id, customization: %{}})
          |> Repo.update()
      end
    else
      {:error, :not_owned}
    end
  end

  @spec clear_active_mount(integer()) :: :ok
  def clear_active_mount(character_id) do
    case get_active_mount(character_id) do
      nil ->
        :ok

      mount ->
        Repo.delete(mount)
        :ok
    end
  end

  @spec update_customization(integer(), map()) ::
          {:ok, ActiveMount.t()} | {:error, :no_active_mount | term()}
  def update_customization(character_id, customization) do
    case get_active_mount(character_id) do
      nil ->
        {:error, :no_active_mount}

      mount ->
        new_customization = Map.merge(mount.customization, customization)

        mount
        |> ActiveMount.customization_changeset(new_customization)
        |> Repo.update()
    end
  end
end
