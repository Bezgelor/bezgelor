defmodule BezgelorDb.Social do
  @moduledoc """
  Social features context - friends and ignore lists.
  """
  import Ecto.Query
  alias BezgelorDb.Repo
  alias BezgelorDb.Schema.{Friend, Ignore}

  @max_friends 100
  @max_ignores 50

  # Friends

  @spec list_friends(integer()) :: [Friend.t()]
  def list_friends(character_id) do
    Friend
    |> where([f], f.character_id == ^character_id)
    |> preload(:friend_character)
    |> Repo.all()
  end

  @spec add_friend(integer(), integer(), String.t()) :: {:ok, Friend.t()} | {:error, term()}
  def add_friend(character_id, friend_id, note \\ "") do
    count = Repo.aggregate(from(f in Friend, where: f.character_id == ^character_id), :count)

    cond do
      count >= @max_friends ->
        {:error, :friend_list_full}

      character_id == friend_id ->
        {:error, :cannot_friend_self}

      true ->
        %Friend{}
        |> Friend.changeset(%{
          character_id: character_id,
          friend_character_id: friend_id,
          note: note
        })
        |> Repo.insert()
    end
  end

  @spec remove_friend(integer(), integer()) :: {:ok, Friend.t()} | {:error, term()}
  def remove_friend(character_id, friend_id) do
    case Repo.get_by(Friend, character_id: character_id, friend_character_id: friend_id) do
      nil -> {:error, :not_found}
      friend -> Repo.delete(friend)
    end
  end

  @spec is_friend?(integer(), integer()) :: boolean()
  def is_friend?(character_id, friend_id) do
    Repo.exists?(
      from(f in Friend,
        where: f.character_id == ^character_id and f.friend_character_id == ^friend_id
      )
    )
  end

  @spec update_friend_note(integer(), integer(), String.t()) ::
          {:ok, Friend.t()} | {:error, term()}
  def update_friend_note(character_id, friend_id, note) do
    case Repo.get_by(Friend, character_id: character_id, friend_character_id: friend_id) do
      nil -> {:error, :not_found}
      friend -> friend |> Friend.changeset(%{note: note}) |> Repo.update()
    end
  end

  # Ignores

  @spec list_ignores(integer()) :: [Ignore.t()]
  def list_ignores(character_id) do
    Ignore
    |> where([i], i.character_id == ^character_id)
    |> preload(:ignored_character)
    |> Repo.all()
  end

  @spec add_ignore(integer(), integer()) :: {:ok, Ignore.t()} | {:error, term()}
  def add_ignore(character_id, ignored_id) do
    count = Repo.aggregate(from(i in Ignore, where: i.character_id == ^character_id), :count)

    cond do
      count >= @max_ignores ->
        {:error, :ignore_list_full}

      character_id == ignored_id ->
        {:error, :cannot_ignore_self}

      true ->
        %Ignore{}
        |> Ignore.changeset(%{character_id: character_id, ignored_character_id: ignored_id})
        |> Repo.insert()
    end
  end

  @spec remove_ignore(integer(), integer()) :: {:ok, Ignore.t()} | {:error, term()}
  def remove_ignore(character_id, ignored_id) do
    case Repo.get_by(Ignore, character_id: character_id, ignored_character_id: ignored_id) do
      nil -> {:error, :not_found}
      ignore -> Repo.delete(ignore)
    end
  end

  @spec is_ignored?(integer(), integer()) :: boolean()
  def is_ignored?(character_id, ignored_id) do
    Repo.exists?(
      from(i in Ignore,
        where: i.character_id == ^character_id and i.ignored_character_id == ^ignored_id
      )
    )
  end

  # Bidirectional ignore check (for chat filtering)
  @spec is_ignored_by_either?(integer(), integer()) :: boolean()
  def is_ignored_by_either?(character_a, character_b) do
    is_ignored?(character_a, character_b) or is_ignored?(character_b, character_a)
  end
end
