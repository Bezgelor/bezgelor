defmodule BezgelorDb.ActionSets do
  @moduledoc """
  Action set persistence for Limited Action Set shortcuts.
  """

  import Ecto.Query

  alias BezgelorDb.Repo
  alias BezgelorDb.Schema.CharacterActionSetShortcut

  @type shortcut_attrs :: %{
          character_id: integer(),
          spec_index: non_neg_integer(),
          slot: non_neg_integer(),
          shortcut_type: non_neg_integer(),
          object_id: non_neg_integer(),
          spell_id: non_neg_integer(),
          tier: non_neg_integer()
        }

  @spec list_shortcuts(integer()) :: [CharacterActionSetShortcut.t()]
  def list_shortcuts(character_id) do
    CharacterActionSetShortcut
    |> where([s], s.character_id == ^character_id)
    |> order_by([s], [s.spec_index, s.slot])
    |> Repo.all()
  end

  @spec list_shortcuts(integer(), non_neg_integer()) :: [CharacterActionSetShortcut.t()]
  def list_shortcuts(character_id, spec_index) do
    CharacterActionSetShortcut
    |> where([s], s.character_id == ^character_id and s.spec_index == ^spec_index)
    |> order_by([s], s.slot)
    |> Repo.all()
  end

  @spec upsert_shortcut(shortcut_attrs()) ::
          {:ok, CharacterActionSetShortcut.t()} | {:error, term()}
  def upsert_shortcut(attrs) do
    %CharacterActionSetShortcut{}
    |> CharacterActionSetShortcut.changeset(attrs)
    |> Repo.insert(
      on_conflict: [
        set: [
          shortcut_type: attrs.shortcut_type,
          object_id: attrs.object_id,
          spell_id: attrs.spell_id,
          tier: attrs.tier
        ]
      ],
      conflict_target: [:character_id, :spec_index, :slot]
    )
  end

  @spec delete_shortcut(integer(), non_neg_integer(), non_neg_integer()) :: :ok
  def delete_shortcut(character_id, spec_index, slot) do
    CharacterActionSetShortcut
    |> where(
      [s],
      s.character_id == ^character_id and s.spec_index == ^spec_index and s.slot == ^slot
    )
    |> Repo.delete_all()

    :ok
  end

  @spec apply_action_set_changes(integer(), non_neg_integer(), [non_neg_integer()], [map()]) ::
          [CharacterActionSetShortcut.t()]
  def apply_action_set_changes(character_id, spec_index, actions, action_tiers) do
    Repo.transaction(fn ->
      existing_shortcuts = list_shortcuts(character_id, spec_index)

      by_object =
        Enum.reduce(existing_shortcuts, %{}, fn shortcut, acc ->
          Map.put(acc, shortcut.object_id, shortcut)
        end)

      actions
      |> Enum.with_index()
      |> Enum.each(fn {action_id, slot} ->
        if action_id == 0 do
          delete_shortcut(character_id, spec_index, slot)
        else
          tier = Map.get(by_object, action_id, %{tier: 1}).tier

          _ =
            upsert_shortcut(%{
              character_id: character_id,
              spec_index: spec_index,
              slot: slot,
              shortcut_type: 4,
              object_id: action_id,
              spell_id: action_id,
              tier: tier
            })
        end
      end)

      Enum.each(action_tiers, fn %{action: action_id, tier: tier} ->
        CharacterActionSetShortcut
        |> where(
          [s],
          s.character_id == ^character_id and
            s.spec_index == ^spec_index and
            s.shortcut_type == 4 and
            s.object_id == ^action_id
        )
        |> Repo.update_all(set: [tier: tier])
      end)

      list_shortcuts(character_id, spec_index)
    end)
    |> case do
      {:ok, shortcuts} -> shortcuts
      {:error, _} -> list_shortcuts(character_id, spec_index)
    end
  end

  @spec ensure_default_shortcuts(integer(), [map()], non_neg_integer()) ::
          [CharacterActionSetShortcut.t()]
  def ensure_default_shortcuts(character_id, abilities, spec_index \\ 0) do
    existing =
      character_id
      |> list_shortcuts(spec_index)
      |> Enum.reduce(%{}, fn shortcut, acc -> Map.put(acc, shortcut.slot, shortcut) end)

    Enum.each(abilities, fn ability ->
      attrs = %{
        character_id: character_id,
        spec_index: spec_index,
        slot: ability.slot,
        shortcut_type: 4,
        object_id: ability.spell_id,
        spell_id: ability.spell_id,
        tier: ability.tier || 1
      }

      case Map.get(existing, ability.slot) do
        nil ->
          %CharacterActionSetShortcut{}
          |> CharacterActionSetShortcut.changeset(attrs)
          |> Repo.insert(
            on_conflict: :nothing,
            conflict_target: [:character_id, :spec_index, :slot]
          )

        shortcut when shortcut.shortcut_type == 0 or shortcut.object_id == 0 ->
          %CharacterActionSetShortcut{}
          |> CharacterActionSetShortcut.changeset(attrs)
          |> Repo.insert(
            on_conflict: [
              set: [
                shortcut_type: attrs.shortcut_type,
                object_id: attrs.object_id,
                spell_id: attrs.spell_id,
                tier: attrs.tier
              ]
            ],
            conflict_target: [:character_id, :spec_index, :slot]
          )

        _ ->
          :ok
      end
    end)

    list_shortcuts(character_id, spec_index)
  end

  @spec group_by_spec([CharacterActionSetShortcut.t()]) :: map()
  def group_by_spec(shortcuts) do
    Enum.group_by(shortcuts, & &1.spec_index)
  end

  @spec spell_index_by_spec([CharacterActionSetShortcut.t()]) :: map()
  def spell_index_by_spec(shortcuts) do
    shortcuts
    |> Enum.filter(&(&1.shortcut_type == 4))
    |> Enum.reduce(%{}, fn shortcut, acc ->
      spec_map = Map.get(acc, shortcut.spec_index, %{})
      Map.put(acc, shortcut.spec_index, Map.put(spec_map, shortcut.object_id, shortcut))
    end)
  end
end
