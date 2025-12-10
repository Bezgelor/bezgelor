defmodule BezgelorDb.Collections do
  @moduledoc """
  Collection management for mounts and pets.

  Supports both account-wide (purchases, achievements) and
  character-specific (quest rewards, drops) collections.
  """

  import Ecto.Query
  alias BezgelorDb.Repo
  alias BezgelorDb.Schema.{AccountCollection, CharacterCollection}

  # Account Mounts

  @spec get_account_mounts(integer()) :: [integer()]
  def get_account_mounts(account_id) do
    AccountCollection
    |> where([c], c.account_id == ^account_id and c.collectible_type == "mount")
    |> select([c], c.collectible_id)
    |> Repo.all()
  end

  @spec unlock_account_mount(integer(), integer(), String.t()) ::
          {:ok, AccountCollection.t()} | {:error, term()}
  def unlock_account_mount(account_id, mount_id, source) do
    %AccountCollection{}
    |> AccountCollection.changeset(%{
      account_id: account_id,
      collectible_type: "mount",
      collectible_id: mount_id,
      unlock_source: source
    })
    |> Repo.insert(on_conflict: :nothing)
  end

  # Character Mounts

  @spec get_character_mounts(integer()) :: [integer()]
  def get_character_mounts(character_id) do
    CharacterCollection
    |> where([c], c.character_id == ^character_id and c.collectible_type == "mount")
    |> select([c], c.collectible_id)
    |> Repo.all()
  end

  @spec unlock_character_mount(integer(), integer(), String.t()) ::
          {:ok, CharacterCollection.t()} | {:error, term()}
  def unlock_character_mount(character_id, mount_id, source) do
    %CharacterCollection{}
    |> CharacterCollection.changeset(%{
      character_id: character_id,
      collectible_type: "mount",
      collectible_id: mount_id,
      unlock_source: source
    })
    |> Repo.insert(on_conflict: :nothing)
  end

  # Merged Queries

  @spec get_all_mounts(integer(), integer()) :: [integer()]
  def get_all_mounts(account_id, character_id) do
    account_mounts = get_account_mounts(account_id)
    character_mounts = get_character_mounts(character_id)
    Enum.uniq(account_mounts ++ character_mounts)
  end

  @spec owns_mount?(integer(), integer(), integer()) :: boolean()
  def owns_mount?(account_id, character_id, mount_id) do
    mount_id in get_all_mounts(account_id, character_id)
  end

  # Account Pets

  @spec get_account_pets(integer()) :: [integer()]
  def get_account_pets(account_id) do
    AccountCollection
    |> where([c], c.account_id == ^account_id and c.collectible_type == "pet")
    |> select([c], c.collectible_id)
    |> Repo.all()
  end

  @spec unlock_account_pet(integer(), integer(), String.t()) ::
          {:ok, AccountCollection.t()} | {:error, term()}
  def unlock_account_pet(account_id, pet_id, source) do
    %AccountCollection{}
    |> AccountCollection.changeset(%{
      account_id: account_id,
      collectible_type: "pet",
      collectible_id: pet_id,
      unlock_source: source
    })
    |> Repo.insert(on_conflict: :nothing)
  end

  # Character Pets

  @spec get_character_pets(integer()) :: [integer()]
  def get_character_pets(character_id) do
    CharacterCollection
    |> where([c], c.character_id == ^character_id and c.collectible_type == "pet")
    |> select([c], c.collectible_id)
    |> Repo.all()
  end

  @spec unlock_character_pet(integer(), integer(), String.t()) ::
          {:ok, CharacterCollection.t()} | {:error, term()}
  def unlock_character_pet(character_id, pet_id, source) do
    %CharacterCollection{}
    |> CharacterCollection.changeset(%{
      character_id: character_id,
      collectible_type: "pet",
      collectible_id: pet_id,
      unlock_source: source
    })
    |> Repo.insert(on_conflict: :nothing)
  end

  # Merged Pet Queries

  @spec get_all_pets(integer(), integer()) :: [integer()]
  def get_all_pets(account_id, character_id) do
    account_pets = get_account_pets(account_id)
    character_pets = get_character_pets(character_id)
    Enum.uniq(account_pets ++ character_pets)
  end

  @spec owns_pet?(integer(), integer(), integer()) :: boolean()
  def owns_pet?(account_id, character_id, pet_id) do
    pet_id in get_all_pets(account_id, character_id)
  end
end
