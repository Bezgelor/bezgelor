defmodule BezgelorDb.Characters do
  @moduledoc """
  Character management context.

  ## Overview

  Provides functions for managing player characters including:
  - Listing characters for an account
  - Creating new characters with appearance
  - Selecting characters for play
  - Soft-deleting characters

  ## Character Limits

  Accounts can have a configurable maximum number of characters.
  The default is 12 characters per account.

  ## Soft Delete

  Characters are not permanently deleted - they are marked with a
  `deleted_at` timestamp and can potentially be restored. The character
  name is preserved in `original_name` and a new unique suffix is added
  to the `name` field to free up the name for other characters.
  """

  import Ecto.Query
  alias BezgelorDb.Repo
  alias BezgelorDb.Schema.{Character, CharacterAppearance}

  @max_characters 12
  @min_name_length 3
  @max_name_length 24

  # WildStar race/faction mapping
  @exile_races [:human, :granok, :aurin, :mordesh]
  @dominion_races [:cassian, :draken, :mechari, :chua]

  @doc """
  List all characters for an account.

  Returns characters ordered by most recently logged in.
  Excludes soft-deleted characters.
  """
  @spec list_characters(integer()) :: [Character.t()]
  def list_characters(account_id) do
    Character
    |> where([c], c.account_id == ^account_id)
    |> where([c], is_nil(c.deleted_at))
    |> preload(:appearance)
    |> order_by([c], desc: c.last_online)
    |> Repo.all()
  end

  @doc """
  Get a character by ID, ensuring it belongs to the account.

  Returns nil if character doesn't exist, belongs to a different
  account, or has been deleted.
  """
  @spec get_character(integer(), integer()) :: Character.t() | nil
  def get_character(account_id, character_id) do
    Character
    |> where([c], c.id == ^character_id and c.account_id == ^account_id)
    |> where([c], is_nil(c.deleted_at))
    |> preload(:appearance)
    |> Repo.one()
  end

  @doc """
  Get a character by ID without account verification.

  Used internally when account ownership has already been verified.
  """
  @spec get_character(integer()) :: Character.t() | nil
  def get_character(character_id) do
    Character
    |> where([c], c.id == ^character_id)
    |> where([c], is_nil(c.deleted_at))
    |> preload(:appearance)
    |> Repo.one()
  end

  @doc """
  Create a new character with appearance.

  ## Options

  Character attributes:
  - `:name` - Character name (required, 3-24 chars)
  - `:sex` - 0 (male) or 1 (female)
  - `:race` - Race ID
  - `:class` - Class ID
  - `:faction_id` - Faction (must match race)
  - `:world_id` - Starting world ID
  - `:world_zone_id` - Starting zone ID

  Appearance attributes are passed separately.

  ## Returns

  - `{:ok, character}` - Character created successfully
  - `{:error, :max_characters}` - Account has max characters
  - `{:error, :name_taken}` - Character name already in use
  - `{:error, :invalid_name}` - Name doesn't meet requirements
  - `{:error, :invalid_faction}` - Race doesn't match faction
  - `{:error, changeset}` - Other validation error
  """
  @spec create_character(integer(), map(), map()) ::
          {:ok, Character.t()} | {:error, atom() | Ecto.Changeset.t()}
  def create_character(account_id, attrs, appearance_attrs \\ %{}) do
    with :ok <- check_character_limit(account_id),
         :ok <- validate_name_format(attrs[:name] || attrs["name"]),
         :ok <- check_name_available(attrs[:name] || attrs["name"]),
         :ok <- validate_race_faction(attrs) do
      do_create_character(account_id, attrs, appearance_attrs)
    end
  end

  @doc """
  Soft delete a character.

  The character is marked with `deleted_at` timestamp and the name
  is modified to free it up for new characters.

  Returns `{:error, :not_found}` if character doesn't exist or
  doesn't belong to the account.
  """
  @spec delete_character(integer(), integer()) ::
          {:ok, Character.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def delete_character(account_id, character_id) do
    case get_character(account_id, character_id) do
      nil ->
        {:error, :not_found}

      character ->
        character
        |> Character.delete_changeset()
        |> Repo.update()
    end
  end

  @doc """
  Count non-deleted characters for an account.
  """
  @spec count_characters(integer()) :: integer()
  def count_characters(account_id) do
    Character
    |> where([c], c.account_id == ^account_id)
    |> where([c], is_nil(c.deleted_at))
    |> Repo.aggregate(:count)
  end

  @doc """
  Check if a character name is available.

  Names are case-insensitive. Returns false if the name is taken
  by a non-deleted character.
  """
  @spec name_available?(String.t()) :: boolean()
  def name_available?(name) when is_binary(name) do
    not name_taken?(name)
  end

  @doc """
  Check if a character name is taken.
  """
  @spec name_taken?(String.t()) :: boolean()
  def name_taken?(name) when is_binary(name) do
    Character
    |> where([c], fragment("lower(?)", c.name) == ^String.downcase(name))
    |> where([c], is_nil(c.deleted_at))
    |> Repo.exists?()
  end

  @doc """
  Update character's last online timestamp.
  """
  @spec update_last_online(Character.t()) :: {:ok, Character.t()} | {:error, Ecto.Changeset.t()}
  def update_last_online(character) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    character
    |> Ecto.Changeset.change(last_online: now)
    |> Repo.update()
  end

  @doc """
  Update character position.
  """
  @spec update_position(Character.t(), map()) ::
          {:ok, Character.t()} | {:error, Ecto.Changeset.t()}
  def update_position(character, attrs) do
    character
    |> Character.position_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Get the maximum number of characters allowed per account.
  """
  @spec max_characters() :: integer()
  def max_characters, do: @max_characters

  @doc """
  Validate that a race is valid for a faction.

  WildStar has faction-locked races:
  - Exile: Human, Granok, Aurin, Mordesh
  - Dominion: Cassian, Draken, Mechari, Chua
  """
  @spec valid_race_faction?(integer(), integer()) :: boolean()
  def valid_race_faction?(race, faction_id) when is_integer(race) and is_integer(faction_id) do
    race_atom = race_id_to_atom(race)
    valid_race_faction_atom?(race_atom, faction_id)
  end

  # Private functions

  defp check_character_limit(account_id) do
    if count_characters(account_id) >= @max_characters do
      {:error, :max_characters}
    else
      :ok
    end
  end

  defp validate_name_format(nil), do: {:error, :invalid_name}

  defp validate_name_format(name) when is_binary(name) do
    cond do
      String.length(name) < @min_name_length -> {:error, :invalid_name}
      String.length(name) > @max_name_length -> {:error, :invalid_name}
      not valid_name_chars?(name) -> {:error, :invalid_name}
      true -> :ok
    end
  end

  defp valid_name_chars?(name) do
    # Allow letters, numbers, and single spaces (not at start/end)
    Regex.match?(~r/^[a-zA-Z0-9]+(?:\s[a-zA-Z0-9]+)*$/, name)
  end

  defp check_name_available(name) do
    if name_available?(name) do
      :ok
    else
      {:error, :name_taken}
    end
  end

  defp validate_race_faction(attrs) do
    race = attrs[:race] || attrs["race"]
    faction_id = attrs[:faction_id] || attrs["faction_id"]

    cond do
      is_nil(race) or is_nil(faction_id) -> :ok
      valid_race_faction?(race, faction_id) -> :ok
      true -> {:error, :invalid_faction}
    end
  end

  defp do_create_character(account_id, attrs, appearance_attrs) do
    Repo.transaction(fn ->
      character_attrs = Map.put(attrs, :account_id, account_id)

      with {:ok, character} <- insert_character(character_attrs),
           {:ok, _appearance} <- insert_appearance(character.id, appearance_attrs) do
        Repo.preload(character, :appearance)
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp insert_character(attrs) do
    %Character{}
    |> Character.changeset(attrs)
    |> Repo.insert()
  end

  defp insert_appearance(character_id, attrs) do
    appearance_attrs = Map.put(attrs, :character_id, character_id)

    %CharacterAppearance{}
    |> CharacterAppearance.changeset(appearance_attrs)
    |> Repo.insert()
  end

  # Race ID to atom mapping (matches NexusForever)
  defp race_id_to_atom(0), do: :human
  defp race_id_to_atom(1), do: :mordesh
  defp race_id_to_atom(2), do: :draken
  defp race_id_to_atom(3), do: :granok
  defp race_id_to_atom(4), do: :aurin
  defp race_id_to_atom(5), do: :chua
  defp race_id_to_atom(12), do: :mechari
  defp race_id_to_atom(13), do: :cassian
  defp race_id_to_atom(_), do: :unknown

  # Faction IDs: 166 = Exile, 167 = Dominion
  defp valid_race_faction_atom?(race, 166) when race in @exile_races, do: true
  defp valid_race_faction_atom?(race, 167) when race in @dominion_races, do: true
  defp valid_race_faction_atom?(_, _), do: false
end
