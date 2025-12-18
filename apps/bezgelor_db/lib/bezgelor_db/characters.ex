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
  alias BezgelorDb.Schema.{Character, CharacterAppearance, CharacterCurrency}

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
  List characters for an account on a specific realm.

  Returns characters ordered by most recently logged in.
  Excludes soft-deleted characters.
  """
  @spec list_characters(integer(), integer()) :: [Character.t()]
  def list_characters(account_id, realm_id) do
    Character
    |> where([c], c.account_id == ^account_id)
    |> where([c], c.realm_id == ^realm_id)
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
  Get a character by name (case-insensitive).

  Used for social features like friend/ignore lookups.
  """
  @spec get_character_by_name(String.t()) :: Character.t() | nil
  def get_character_by_name(name) when is_binary(name) do
    Character
    |> where([c], fragment("lower(?)", c.name) == ^String.downcase(name))
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
  Count non-deleted characters for an account on a specific realm.
  """
  @spec count_characters(integer(), integer()) :: integer()
  def count_characters(account_id, realm_id) do
    Character
    |> where([c], c.account_id == ^account_id)
    |> where([c], c.realm_id == ^realm_id)
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
  Add experience points to a character.

  ## Returns

  - `{:ok, character}` - XP added, no level up
  - `{:ok, character, level_up: true}` - XP added and character leveled up
  - `{:error, changeset}` - Update failed
  """
  @spec add_experience(Character.t(), non_neg_integer()) ::
          {:ok, Character.t()} | {:ok, Character.t(), keyword()} | {:error, Ecto.Changeset.t()}
  def add_experience(%Character{} = character, xp_amount) when xp_amount >= 0 do
    new_total = character.total_xp + xp_amount
    current_level = character.level

    # Calculate if level up occurred
    {new_level, leveled_up} = calculate_level(new_total, current_level)

    changes = %{
      total_xp: new_total,
      level: new_level
    }

    case character
         |> Ecto.Changeset.change(changes)
         |> Repo.update() do
      {:ok, updated} ->
        if leveled_up do
          {:ok, updated, level_up: true}
        else
          {:ok, updated}
        end

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Get XP required for a given level.

  WildStar XP curve: level * 1000 base, with exponential growth.
  """
  @spec xp_for_level(non_neg_integer()) :: non_neg_integer()
  def xp_for_level(level) when level >= 1 do
    # Simplified WildStar XP curve
    round(level * 1000 * :math.pow(1.1, level - 1))
  end

  @doc """
  Get total XP required to reach a level (cumulative).
  """
  @spec total_xp_for_level(non_neg_integer()) :: non_neg_integer()
  def total_xp_for_level(1), do: 0
  def total_xp_for_level(level) when level > 1 do
    1..(level - 1)
    |> Enum.map(&xp_for_level/1)
    |> Enum.sum()
  end

  # ============================================================================
  # Currency Functions
  # ============================================================================

  @doc """
  Add currency to a character.

  ## Parameters

  - `character_id` - The character ID
  - `currency_type` - Atom like :gold, :elder_gems, :prestige, etc.
  - `amount` - Amount to add (must be positive)

  ## Returns

  - `{:ok, updated_currency}` on success
  - `{:error, :character_not_found}` if character doesn't exist
  - `{:error, changeset}` on database error
  """
  @spec add_currency(integer(), atom(), non_neg_integer()) ::
          {:ok, CharacterCurrency.t()} | {:error, :character_not_found | Ecto.Changeset.t()}
  def add_currency(character_id, currency_type, amount)
      when is_integer(character_id) and is_atom(currency_type) and amount >= 0 do
    # Get or create currency record for character
    case get_or_create_currency(character_id) do
      {:ok, currency} ->
        case CharacterCurrency.modify_changeset(currency, currency_type, amount) do
          {:ok, changeset} -> Repo.update(changeset)
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get currency record for a character, creating if needed.
  """
  @spec get_or_create_currency(integer()) ::
          {:ok, CharacterCurrency.t()} | {:error, :character_not_found | Ecto.Changeset.t()}
  def get_or_create_currency(character_id) do
    case Repo.get_by(CharacterCurrency, character_id: character_id) do
      nil ->
        # Check if character exists
        if Repo.exists?(from c in Character, where: c.id == ^character_id) do
          %CharacterCurrency{}
          |> CharacterCurrency.changeset(%{character_id: character_id})
          |> Repo.insert()
        else
          {:error, :character_not_found}
        end

      currency ->
        {:ok, currency}
    end
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

  # Calculate new level based on total XP
  defp calculate_level(total_xp, current_level) do
    max_level = 50

    new_level =
      Enum.reduce_while(current_level..max_level, current_level, fn level, _acc ->
        if total_xp >= total_xp_for_level(level + 1) do
          {:cont, level + 1}
        else
          {:halt, level}
        end
      end)

    {min(new_level, max_level), new_level > current_level}
  end

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

  # Race ID to atom mapping (matches NexusForever Race enum)
  # See: NexusForever/Source/NexusForever.Game.Static/Entity/Race.cs
  defp race_id_to_atom(1), do: :human
  defp race_id_to_atom(2), do: :cassian     # Eshara in code, Cassian in lore
  defp race_id_to_atom(3), do: :granok
  defp race_id_to_atom(4), do: :aurin
  defp race_id_to_atom(5), do: :draken
  defp race_id_to_atom(12), do: :mechari
  defp race_id_to_atom(13), do: :chua
  defp race_id_to_atom(16), do: :mordesh
  defp race_id_to_atom(_), do: :unknown

  # Faction IDs (matches NexusForever Faction enum)
  # See: NexusForever/Source/NexusForever.Game.Static/Reputation/Faction.cs
  # 166 = Dominion, 167 = Exile
  # Note: Race 1 (Human/Cassian) can be either faction - same model, different lore names
  defp valid_race_faction_atom?(:human, _faction), do: true  # Human model used by both factions
  defp valid_race_faction_atom?(race, 166) when race in @dominion_races, do: true
  defp valid_race_faction_atom?(race, 167) when race in @exile_races, do: true
  defp valid_race_faction_atom?(_, _), do: false

  # ============================================================================
  # Admin Functions
  # ============================================================================

  @doc """
  Search characters by name (admin).

  ## Options

  - `:search` - Partial name search
  - `:account_id` - Filter by account
  - `:include_deleted` - Include deleted characters
  - `:limit` - Max results (default 50)
  - `:offset` - Pagination offset
  """
  @spec search_characters(keyword()) :: [map()]
  def search_characters(opts \\ []) do
    search = Keyword.get(opts, :search)
    account_id = Keyword.get(opts, :account_id)
    include_deleted = Keyword.get(opts, :include_deleted, false)
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    query =
      from(c in Character,
        join: a in assoc(c, :account),
        order_by: [asc: c.name],
        limit: ^limit,
        offset: ^offset,
        select: %{
          id: c.id,
          name: c.name,
          level: c.level,
          race: c.race,
          class: c.class,
          faction_id: c.faction_id,
          last_online: c.last_online,
          deleted_at: c.deleted_at,
          account_id: a.id,
          account_email: a.email
        }
      )

    query =
      if include_deleted do
        query
      else
        from([c, a] in query, where: is_nil(c.deleted_at))
      end

    query =
      if search && search != "" do
        search_term = "%#{search}%"
        from([c, a] in query, where: ilike(c.name, ^search_term))
      else
        query
      end

    query =
      if account_id do
        from([c, a] in query, where: c.account_id == ^account_id)
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Get a character for admin view (includes deleted, no account check).
  """
  @spec get_character_for_admin(integer()) :: Character.t() | nil
  def get_character_for_admin(character_id) do
    Character
    |> where([c], c.id == ^character_id)
    |> preload([:appearance, :account])
    |> Repo.one()
  end

  @doc """
  Admin rename a character.

  Bypasses account ownership check.
  """
  @spec admin_rename(Character.t(), String.t()) ::
          {:ok, Character.t()} | {:error, :name_taken | :invalid_name | Ecto.Changeset.t()}
  def admin_rename(character, new_name) do
    with :ok <- validate_name_format(new_name),
         :ok <- check_name_available_except(new_name, character.id) do
      character
      |> Ecto.Changeset.change(name: new_name)
      |> Repo.update()
    end
  end

  defp check_name_available_except(name, character_id) do
    exists =
      Character
      |> where([c], fragment("lower(?)", c.name) == ^String.downcase(name))
      |> where([c], c.id != ^character_id)
      |> where([c], is_nil(c.deleted_at))
      |> Repo.exists?()

    if exists, do: {:error, :name_taken}, else: :ok
  end

  @doc """
  Admin set character level.
  """
  @spec admin_set_level(Character.t(), integer()) ::
          {:ok, Character.t()} | {:error, Ecto.Changeset.t()}
  def admin_set_level(character, level) when level >= 1 and level <= 50 do
    character
    |> Ecto.Changeset.change(level: level)
    |> Repo.update()
  end

  def admin_set_level(_character, _level), do: {:error, :invalid_level}

  @doc """
  Admin teleport a character.
  """
  @spec admin_teleport(Character.t(), map()) ::
          {:ok, Character.t()} | {:error, Ecto.Changeset.t()}
  def admin_teleport(character, attrs) do
    character
    |> Character.position_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Admin delete a character (bypasses account check).
  """
  @spec admin_delete_character(Character.t()) ::
          {:ok, Character.t()} | {:error, Ecto.Changeset.t()}
  def admin_delete_character(character) do
    character
    |> Character.delete_changeset()
    |> Repo.update()
  end

  @doc """
  Admin restore a deleted character.
  """
  @spec admin_restore_character(Character.t()) ::
          {:ok, Character.t()} | {:error, :name_taken | Ecto.Changeset.t()}
  def admin_restore_character(character) do
    # Check if original name is available
    original_name = character.original_name || character.name

    if name_taken?(original_name) do
      {:error, :name_taken}
    else
      character
      |> Ecto.Changeset.change(
        deleted_at: nil,
        name: original_name,
        original_name: nil
      )
      |> Repo.update()
    end
  end
end
