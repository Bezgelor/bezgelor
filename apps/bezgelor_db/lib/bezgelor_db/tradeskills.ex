defmodule BezgelorDb.Tradeskills do
  @moduledoc """
  Tradeskills database operations.

  Manages profession progress, schematic discovery, talent allocation,
  and work orders.
  """

  import Ecto.Query
  alias BezgelorDb.Repo
  alias BezgelorDb.Schema.{CharacterTradeskill, SchematicDiscovery, TradeskillTalent, WorkOrder}

  # =============================================================================
  # Profession Management
  # =============================================================================

  @doc """
  Learn a new profession for a character.
  """
  @spec learn_profession(integer(), integer(), :crafting | :gathering) ::
          {:ok, CharacterTradeskill.t()} | {:error, term()}
  def learn_profession(character_id, profession_id, profession_type) do
    %CharacterTradeskill{}
    |> CharacterTradeskill.changeset(%{
      character_id: character_id,
      profession_id: profession_id,
      profession_type: profession_type
    })
    |> Repo.insert()
  end

  @doc """
  Get all professions for a character.
  """
  @spec get_professions(integer()) :: [CharacterTradeskill.t()]
  def get_professions(character_id) do
    from(t in CharacterTradeskill,
      where: t.character_id == ^character_id,
      order_by: [desc: t.is_active, asc: t.profession_id]
    )
    |> Repo.all()
  end

  @doc """
  Get active professions of a specific type.
  """
  @spec get_active_professions(integer(), :crafting | :gathering) :: [CharacterTradeskill.t()]
  def get_active_professions(character_id, profession_type) do
    from(t in CharacterTradeskill,
      where:
        t.character_id == ^character_id and
          t.profession_type == ^profession_type and
          t.is_active == true
    )
    |> Repo.all()
  end

  @doc """
  Swap from one profession to another (for crafting professions with limits).
  """
  @spec swap_profession(integer(), integer(), integer()) ::
          {:ok, CharacterTradeskill.t()} | {:error, term()}
  def swap_profession(character_id, old_profession_id, new_profession_id) do
    Repo.transaction(fn ->
      # Deactivate old profession
      case get_profession(character_id, old_profession_id) do
        {:ok, old} ->
          old
          |> CharacterTradeskill.deactivate_changeset()
          |> Repo.update!()

        :error ->
          :ok
      end

      # Check if new profession was previously learned
      case get_profession(character_id, new_profession_id) do
        {:ok, existing} ->
          # Reactivate existing
          existing
          |> CharacterTradeskill.activate_changeset()
          |> Repo.update!()

        :error ->
          # Learn new profession
          %CharacterTradeskill{}
          |> CharacterTradeskill.changeset(%{
            character_id: character_id,
            profession_id: new_profession_id,
            profession_type: :crafting
          })
          |> Repo.insert!()
      end
    end)
  end

  @doc """
  Get a specific profession for a character.
  """
  @spec get_profession(integer(), integer()) :: {:ok, CharacterTradeskill.t()} | :error
  def get_profession(character_id, profession_id) do
    query =
      from(t in CharacterTradeskill,
        where: t.character_id == ^character_id and t.profession_id == ^profession_id
      )

    case Repo.one(query) do
      nil -> :error
      tradeskill -> {:ok, tradeskill}
    end
  end

  # =============================================================================
  # Progress Tracking
  # =============================================================================

  @doc """
  Add XP to a profession and handle level-ups.
  Returns the updated tradeskill with any level changes.
  """
  @spec add_xp(integer(), integer(), integer()) ::
          {:ok, CharacterTradeskill.t(), levels_gained :: integer()} | {:error, term()}
  def add_xp(character_id, profession_id, xp_amount) do
    case get_profession(character_id, profession_id) do
      {:ok, tradeskill} ->
        new_xp = tradeskill.skill_xp + xp_amount
        {new_level, remaining_xp, levels_gained} = calculate_level(tradeskill.skill_level, new_xp)

        result =
          tradeskill
          |> CharacterTradeskill.progress_changeset(%{
            skill_level: new_level,
            skill_xp: remaining_xp
          })
          |> Repo.update()

        case result do
          {:ok, updated} -> {:ok, updated, levels_gained}
          {:error, _} = err -> err
        end

      :error ->
        {:error, :profession_not_found}
    end
  end

  # Simplified level calculation - would use static data in real impl
  defp calculate_level(current_level, total_xp) do
    # Simplified; real values from static data
    xp_per_level = 1000
    max_level = 50

    levels_to_add = div(total_xp, xp_per_level)
    new_level = min(current_level + levels_to_add, max_level)
    remaining_xp = rem(total_xp, xp_per_level)
    levels_gained = new_level - current_level

    {new_level, remaining_xp, levels_gained}
  end

  # =============================================================================
  # Schematic Discovery
  # =============================================================================

  @doc """
  Record a schematic or variant discovery.
  """
  @spec discover_schematic(integer(), integer(), integer()) ::
          {:ok, SchematicDiscovery.t()} | {:error, term()}
  def discover_schematic(character_id, schematic_id, variant_id \\ 0) do
    %SchematicDiscovery{}
    |> SchematicDiscovery.changeset(%{
      character_id: character_id,
      schematic_id: schematic_id,
      variant_id: variant_id
    })
    |> Repo.insert(on_conflict: :nothing)
  end

  @doc """
  Record an account-wide schematic discovery.
  """
  @spec discover_schematic_account(integer(), integer(), integer()) ::
          {:ok, SchematicDiscovery.t()} | {:error, term()}
  def discover_schematic_account(account_id, schematic_id, variant_id \\ 0) do
    %SchematicDiscovery{}
    |> SchematicDiscovery.changeset(%{
      account_id: account_id,
      schematic_id: schematic_id,
      variant_id: variant_id
    })
    |> Repo.insert(on_conflict: :nothing)
  end

  @doc """
  Check if a schematic/variant has been discovered.
  """
  @spec is_discovered?(integer(), integer(), integer()) :: boolean()
  def is_discovered?(character_id, schematic_id, variant_id \\ 0) do
    query =
      from(d in SchematicDiscovery,
        where:
          d.character_id == ^character_id and
            d.schematic_id == ^schematic_id and
            d.variant_id == ^variant_id
      )

    Repo.exists?(query)
  end

  @doc """
  Get all discoveries for a character.
  """
  @spec get_discoveries(integer()) :: [SchematicDiscovery.t()]
  def get_discoveries(character_id) do
    from(d in SchematicDiscovery,
      where: d.character_id == ^character_id,
      order_by: [asc: d.schematic_id, asc: d.variant_id]
    )
    |> Repo.all()
  end

  # =============================================================================
  # Talent Management
  # =============================================================================

  @doc """
  Allocate a talent point.
  """
  @spec allocate_talent(integer(), integer(), integer()) ::
          {:ok, TradeskillTalent.t()} | {:error, term()}
  def allocate_talent(character_id, profession_id, talent_id) do
    case get_talent(character_id, profession_id, talent_id) do
      {:ok, existing} ->
        existing
        |> TradeskillTalent.add_point_changeset()
        |> Repo.update()

      :error ->
        %TradeskillTalent{}
        |> TradeskillTalent.changeset(%{
          character_id: character_id,
          profession_id: profession_id,
          talent_id: talent_id
        })
        |> Repo.insert()
    end
  end

  @doc """
  Get all allocated talents for a profession.
  """
  @spec get_talents(integer(), integer()) :: [TradeskillTalent.t()]
  def get_talents(character_id, profession_id) do
    from(t in TradeskillTalent,
      where: t.character_id == ^character_id and t.profession_id == ^profession_id
    )
    |> Repo.all()
  end

  @doc """
  Get a specific talent allocation.
  """
  @spec get_talent(integer(), integer(), integer()) :: {:ok, TradeskillTalent.t()} | :error
  def get_talent(character_id, profession_id, talent_id) do
    query =
      from(t in TradeskillTalent,
        where:
          t.character_id == ^character_id and
            t.profession_id == ^profession_id and
            t.talent_id == ^talent_id
      )

    case Repo.one(query) do
      nil -> :error
      talent -> {:ok, talent}
    end
  end

  @doc """
  Reset all talents for a profession.
  """
  @spec reset_talents(integer(), integer()) :: {integer(), nil}
  def reset_talents(character_id, profession_id) do
    from(t in TradeskillTalent,
      where: t.character_id == ^character_id and t.profession_id == ^profession_id
    )
    |> Repo.delete_all()
  end

  @doc """
  Count total talent points spent for a profession.
  """
  @spec count_talent_points(integer(), integer()) :: integer()
  def count_talent_points(character_id, profession_id) do
    from(t in TradeskillTalent,
      where: t.character_id == ^character_id and t.profession_id == ^profession_id,
      select: sum(t.points_spent)
    )
    |> Repo.one() || 0
  end

  # =============================================================================
  # Work Orders
  # =============================================================================

  @doc """
  Create a work order for a character.
  """
  @spec create_work_order(integer(), map()) :: {:ok, WorkOrder.t()} | {:error, term()}
  def create_work_order(character_id, attrs) do
    %WorkOrder{}
    |> WorkOrder.changeset(Map.put(attrs, :character_id, character_id))
    |> Repo.insert()
  end

  @doc """
  Get all active work orders for a character.
  """
  @spec get_active_work_orders(integer()) :: [WorkOrder.t()]
  def get_active_work_orders(character_id) do
    now = DateTime.utc_now()

    from(w in WorkOrder,
      where:
        w.character_id == ^character_id and
          w.status == :active and
          w.expires_at > ^now
    )
    |> Repo.all()
  end

  @doc """
  Update work order progress.
  """
  @spec update_work_order_progress(integer(), integer()) ::
          {:ok, WorkOrder.t()} | {:error, term()}
  def update_work_order_progress(work_order_id, quantity_completed) do
    case Repo.get(WorkOrder, work_order_id) do
      nil ->
        {:error, :not_found}

      order ->
        order
        |> WorkOrder.progress_changeset(quantity_completed)
        |> Repo.update()
    end
  end

  @doc """
  Complete a work order.
  """
  @spec complete_work_order(integer()) :: {:ok, WorkOrder.t()} | {:error, term()}
  def complete_work_order(work_order_id) do
    case Repo.get(WorkOrder, work_order_id) do
      nil ->
        {:error, :not_found}

      order ->
        order
        |> WorkOrder.complete_changeset()
        |> Repo.update()
    end
  end

  @doc """
  Expire old work orders.
  """
  @spec expire_work_orders() :: {integer(), nil}
  def expire_work_orders do
    now = DateTime.utc_now()

    from(w in WorkOrder,
      where: w.status == :active and w.expires_at <= ^now
    )
    |> Repo.update_all(set: [status: :expired])
  end
end
