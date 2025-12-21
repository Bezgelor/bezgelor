defmodule BezgelorDb.Schema.Friend do
  @moduledoc """
  Friend relationship between characters.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias BezgelorDb.Schema.Character

  schema "friends" do
    belongs_to(:character, Character)
    belongs_to(:friend_character, Character)
    field(:note, :string, default: "")
    field(:group_name, :string, default: "Friends")
    timestamps()
  end

  def changeset(friend, attrs) do
    friend
    |> cast(attrs, [:character_id, :friend_character_id, :note, :group_name])
    |> validate_required([:character_id, :friend_character_id])
    |> unique_constraint([:character_id, :friend_character_id])
  end
end
