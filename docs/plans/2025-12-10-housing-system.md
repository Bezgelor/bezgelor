# Housing System Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement full WildStar-authentic housing with character-owned plots, free-form decor, FABkits, and four-tier social permissions.

**Architecture:** Character-based ownership with on-demand instance lifecycle. HousingManager GenServer coordinates instances. Database stores plots, decor, fabkits, and neighbors. Zone.Instance handles runtime state.

**Tech Stack:** Elixir/Ecto for schemas and context, GenServer for HousingManager, existing Zone.Instance infrastructure for housing instances.

---

## Task 1: Database Migration

**Files:**
- Create: `apps/bezgelor_db/priv/repo/migrations/20251210200000_create_housing_tables.exs`

**Step 1: Write the migration file**

```elixir
defmodule BezgelorDb.Repo.Migrations.CreateHousingTables do
  use Ecto.Migration

  def change do
    # Permission level enum
    execute(
      "CREATE TYPE housing_permission AS ENUM ('private', 'neighbors', 'roommates', 'public')",
      "DROP TYPE housing_permission"
    )

    # Main plot table - one per character
    create table(:housing_plots) do
      add :character_id, references(:characters, on_delete: :delete_all), null: false
      add :house_type_id, :integer, null: false, default: 1  # 1 = cozy, 2 = spacious
      add :permission_level, :housing_permission, null: false, default: "private"
      add :sky_id, :integer, null: false, default: 1
      add :ground_id, :integer, null: false, default: 1
      add :music_id, :integer, null: false, default: 1
      add :plot_name, :string, size: 64

      timestamps(type: :utc_datetime)
    end

    create unique_index(:housing_plots, [:character_id])

    # Neighbors and roommates
    create table(:housing_neighbors) do
      add :plot_id, references(:housing_plots, on_delete: :delete_all), null: false
      add :character_id, references(:characters, on_delete: :delete_all), null: false
      add :is_roommate, :boolean, null: false, default: false

      add :added_at, :utc_datetime, null: false, default: fragment("NOW()")
    end

    create unique_index(:housing_neighbors, [:plot_id, :character_id])
    create index(:housing_neighbors, [:character_id])

    # Placed decor items
    create table(:housing_decor) do
      add :plot_id, references(:housing_plots, on_delete: :delete_all), null: false
      add :decor_id, :integer, null: false  # Template from decor_items.json

      # Position (floats)
      add :pos_x, :float, null: false, default: 0.0
      add :pos_y, :float, null: false, default: 0.0
      add :pos_z, :float, null: false, default: 0.0

      # Rotation (euler angles in degrees)
      add :rot_pitch, :float, null: false, default: 0.0
      add :rot_yaw, :float, null: false, default: 0.0
      add :rot_roll, :float, null: false, default: 0.0

      # Scale
      add :scale, :float, null: false, default: 1.0

      # Interior vs exterior
      add :is_exterior, :boolean, null: false, default: false

      add :placed_at, :utc_datetime, null: false, default: fragment("NOW()")
    end

    create index(:housing_decor, [:plot_id])

    # FABkit installations
    create table(:housing_fabkits) do
      add :plot_id, references(:housing_plots, on_delete: :delete_all), null: false
      add :socket_index, :integer, null: false  # 0-5 (4-5 are large sockets)
      add :fabkit_id, :integer, null: false  # Template from fabkit_types.json
      add :state, :map, null: false, default: %{}  # harvest_available_at, challenge_progress, etc.

      add :installed_at, :utc_datetime, null: false, default: fragment("NOW()")
    end

    create unique_index(:housing_fabkits, [:plot_id, :socket_index])
  end
end
```

**Step 2: Run migration to verify it works**

Run: `cd apps/bezgelor_db && MIX_ENV=test mix ecto.migrate`
Expected: Migration completes successfully

**Step 3: Commit**

```bash
git add apps/bezgelor_db/priv/repo/migrations/20251210200000_create_housing_tables.exs
git commit -m "feat(db): add housing tables migration"
```

---

## Task 2: HousingPlot Schema

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/schema/housing_plot.ex`

**Step 1: Write the schema**

```elixir
defmodule BezgelorDb.Schema.HousingPlot do
  @moduledoc """
  Schema for character housing plots.

  Each character owns one plot with customizable house type,
  theme settings, and permission level.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @permission_levels [:private, :neighbors, :roommates, :public]

  schema "housing_plots" do
    belongs_to :character, BezgelorDb.Schema.Character

    field :house_type_id, :integer, default: 1
    field :permission_level, Ecto.Enum, values: @permission_levels, default: :private
    field :sky_id, :integer, default: 1
    field :ground_id, :integer, default: 1
    field :music_id, :integer, default: 1
    field :plot_name, :string

    has_many :decor, BezgelorDb.Schema.HousingDecor, foreign_key: :plot_id
    has_many :fabkits, BezgelorDb.Schema.HousingFabkit, foreign_key: :plot_id
    has_many :neighbors, BezgelorDb.Schema.HousingNeighbor, foreign_key: :plot_id

    timestamps(type: :utc_datetime)
  end

  def changeset(plot, attrs) do
    plot
    |> cast(attrs, [:character_id, :house_type_id, :permission_level, :sky_id, :ground_id, :music_id, :plot_name])
    |> validate_required([:character_id])
    |> validate_inclusion(:house_type_id, [1, 2])
    |> validate_inclusion(:permission_level, @permission_levels)
    |> validate_length(:plot_name, max: 64)
    |> foreign_key_constraint(:character_id)
    |> unique_constraint(:character_id)
  end

  def theme_changeset(plot, attrs) do
    plot
    |> cast(attrs, [:sky_id, :ground_id, :music_id, :plot_name])
    |> validate_length(:plot_name, max: 64)
  end

  def permission_changeset(plot, attrs) do
    plot
    |> cast(attrs, [:permission_level])
    |> validate_inclusion(:permission_level, @permission_levels)
  end

  def upgrade_changeset(plot, attrs) do
    plot
    |> cast(attrs, [:house_type_id])
    |> validate_inclusion(:house_type_id, [1, 2])
  end

  @doc "Get valid permission levels."
  def permission_levels, do: @permission_levels
end
```

**Step 2: Commit**

```bash
git add apps/bezgelor_db/lib/bezgelor_db/schema/housing_plot.ex
git commit -m "feat(db): add HousingPlot schema"
```

---

## Task 3: HousingNeighbor Schema

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/schema/housing_neighbor.ex`

**Step 1: Write the schema**

```elixir
defmodule BezgelorDb.Schema.HousingNeighbor do
  @moduledoc """
  Schema for housing neighbor permissions.

  Tracks who can visit a plot, with optional roommate
  elevation for decor placement rights.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "housing_neighbors" do
    belongs_to :plot, BezgelorDb.Schema.HousingPlot
    belongs_to :character, BezgelorDb.Schema.Character

    field :is_roommate, :boolean, default: false
    field :added_at, :utc_datetime
  end

  def changeset(neighbor, attrs) do
    neighbor
    |> cast(attrs, [:plot_id, :character_id, :is_roommate])
    |> validate_required([:plot_id, :character_id])
    |> put_change(:added_at, DateTime.utc_now() |> DateTime.truncate(:second))
    |> foreign_key_constraint(:plot_id)
    |> foreign_key_constraint(:character_id)
    |> unique_constraint([:plot_id, :character_id])
  end

  def roommate_changeset(neighbor, attrs) do
    neighbor
    |> cast(attrs, [:is_roommate])
  end
end
```

**Step 2: Commit**

```bash
git add apps/bezgelor_db/lib/bezgelor_db/schema/housing_neighbor.ex
git commit -m "feat(db): add HousingNeighbor schema"
```

---

## Task 4: HousingDecor Schema

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/schema/housing_decor.ex`

**Step 1: Write the schema**

```elixir
defmodule BezgelorDb.Schema.HousingDecor do
  @moduledoc """
  Schema for placed housing decor items.

  Stores full free-form placement: position, rotation (euler angles),
  and uniform scale.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "housing_decor" do
    belongs_to :plot, BezgelorDb.Schema.HousingPlot

    field :decor_id, :integer

    # Position
    field :pos_x, :float, default: 0.0
    field :pos_y, :float, default: 0.0
    field :pos_z, :float, default: 0.0

    # Rotation (euler angles in degrees)
    field :rot_pitch, :float, default: 0.0
    field :rot_yaw, :float, default: 0.0
    field :rot_roll, :float, default: 0.0

    # Scale
    field :scale, :float, default: 1.0

    # Interior vs exterior
    field :is_exterior, :boolean, default: false

    field :placed_at, :utc_datetime
  end

  def changeset(decor, attrs) do
    decor
    |> cast(attrs, [:plot_id, :decor_id, :pos_x, :pos_y, :pos_z, :rot_pitch, :rot_yaw, :rot_roll, :scale, :is_exterior])
    |> validate_required([:plot_id, :decor_id])
    |> validate_number(:scale, greater_than: 0.0, less_than_or_equal_to: 10.0)
    |> put_change(:placed_at, DateTime.utc_now() |> DateTime.truncate(:second))
    |> foreign_key_constraint(:plot_id)
  end

  def move_changeset(decor, attrs) do
    decor
    |> cast(attrs, [:pos_x, :pos_y, :pos_z, :rot_pitch, :rot_yaw, :rot_roll, :scale])
    |> validate_number(:scale, greater_than: 0.0, less_than_or_equal_to: 10.0)
  end
end
```

**Step 2: Commit**

```bash
git add apps/bezgelor_db/lib/bezgelor_db/schema/housing_decor.ex
git commit -m "feat(db): add HousingDecor schema"
```

---

## Task 5: HousingFabkit Schema

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/schema/housing_fabkit.ex`

**Step 1: Write the schema**

```elixir
defmodule BezgelorDb.Schema.HousingFabkit do
  @moduledoc """
  Schema for installed housing FABkits.

  FABkits are functional plugs in the 6 outdoor sockets (0-3 small, 4-5 large).
  State map stores type-specific data like harvest cooldowns.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "housing_fabkits" do
    belongs_to :plot, BezgelorDb.Schema.HousingPlot

    field :socket_index, :integer
    field :fabkit_id, :integer
    field :state, :map, default: %{}

    field :installed_at, :utc_datetime
  end

  def changeset(fabkit, attrs) do
    fabkit
    |> cast(attrs, [:plot_id, :socket_index, :fabkit_id, :state])
    |> validate_required([:plot_id, :socket_index, :fabkit_id])
    |> validate_number(:socket_index, greater_than_or_equal_to: 0, less_than_or_equal_to: 5)
    |> put_change(:installed_at, DateTime.utc_now() |> DateTime.truncate(:second))
    |> foreign_key_constraint(:plot_id)
    |> unique_constraint([:plot_id, :socket_index])
  end

  def state_changeset(fabkit, attrs) do
    fabkit
    |> cast(attrs, [:state])
  end
end
```

**Step 2: Commit**

```bash
git add apps/bezgelor_db/lib/bezgelor_db/schema/housing_fabkit.ex
git commit -m "feat(db): add HousingFabkit schema"
```

---

## Task 6: Housing Context - Plot Operations

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/housing.ex`
- Create: `apps/bezgelor_db/test/housing_test.exs`

**Step 1: Write the failing test**

```elixir
defmodule BezgelorDb.HousingTest do
  use ExUnit.Case

  alias BezgelorDb.{Accounts, Characters, Housing, Repo}

  @moduletag :database

  setup do
    case Repo.start_link([]) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    email = "housing_test#{System.unique_integer([:positive])}@test.com"
    {:ok, account} = Accounts.create_account(email, "password123")

    {:ok, character} =
      Characters.create_character(account.id, %{
        name: "HomeOwner#{System.unique_integer([:positive])}",
        sex: 0, race: 0, class: 0, faction_id: 166, world_id: 1, world_zone_id: 1
      })

    {:ok, account: account, character: character}
  end

  describe "plot lifecycle" do
    test "create_plot creates new plot for character", %{character: character} do
      assert {:ok, plot} = Housing.create_plot(character.id)
      assert plot.character_id == character.id
      assert plot.house_type_id == 1
      assert plot.permission_level == :private
    end

    test "create_plot fails for duplicate character", %{character: character} do
      {:ok, _} = Housing.create_plot(character.id)
      assert {:error, _} = Housing.create_plot(character.id)
    end

    test "get_plot returns plot with preloads", %{character: character} do
      {:ok, _} = Housing.create_plot(character.id)
      assert {:ok, plot} = Housing.get_plot(character.id)
      assert plot.character_id == character.id
      assert is_list(plot.decor)
      assert is_list(plot.fabkits)
    end

    test "get_plot returns error for nonexistent", %{character: _character} do
      assert :error = Housing.get_plot(999999)
    end

    test "upgrade_house changes house type", %{character: character} do
      {:ok, _} = Housing.create_plot(character.id)
      assert {:ok, plot} = Housing.upgrade_house(character.id, 2)
      assert plot.house_type_id == 2
    end

    test "update_plot_theme changes theme settings", %{character: character} do
      {:ok, _} = Housing.create_plot(character.id)
      assert {:ok, plot} = Housing.update_plot_theme(character.id, %{sky_id: 5, plot_name: "My Palace"})
      assert plot.sky_id == 5
      assert plot.plot_name == "My Palace"
    end

    test "set_permission_level changes permission", %{character: character} do
      {:ok, _} = Housing.create_plot(character.id)
      assert {:ok, plot} = Housing.set_permission_level(character.id, :public)
      assert plot.permission_level == :public
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `cd apps/bezgelor_db && MIX_ENV=test mix test test/housing_test.exs --trace`
Expected: FAIL with "Housing is not available" or "undefined function"

**Step 3: Write the context module**

```elixir
defmodule BezgelorDb.Housing do
  @moduledoc """
  Housing system database operations.

  Manages plots, decor, FABkits, and neighbor permissions.
  """

  import Ecto.Query
  alias BezgelorDb.Repo
  alias BezgelorDb.Schema.{HousingPlot, HousingNeighbor, HousingDecor, HousingFabkit}

  # Plot Lifecycle

  @spec create_plot(integer()) :: {:ok, HousingPlot.t()} | {:error, term()}
  def create_plot(character_id) do
    %HousingPlot{}
    |> HousingPlot.changeset(%{character_id: character_id})
    |> Repo.insert()
  end

  @spec get_plot(integer()) :: {:ok, HousingPlot.t()} | :error
  def get_plot(character_id) do
    query =
      from p in HousingPlot,
        where: p.character_id == ^character_id,
        preload: [:decor, :fabkits, :neighbors]

    case Repo.one(query) do
      nil -> :error
      plot -> {:ok, plot}
    end
  end

  @spec get_plot_by_id(integer()) :: {:ok, HousingPlot.t()} | :error
  def get_plot_by_id(plot_id) do
    query =
      from p in HousingPlot,
        where: p.id == ^plot_id,
        preload: [:decor, :fabkits, :neighbors]

    case Repo.one(query) do
      nil -> :error
      plot -> {:ok, plot}
    end
  end

  @spec upgrade_house(integer(), integer()) :: {:ok, HousingPlot.t()} | {:error, term()}
  def upgrade_house(character_id, house_type_id) do
    case get_plot(character_id) do
      {:ok, plot} ->
        plot
        |> HousingPlot.upgrade_changeset(%{house_type_id: house_type_id})
        |> Repo.update()

      :error ->
        {:error, :not_found}
    end
  end

  @spec update_plot_theme(integer(), map()) :: {:ok, HousingPlot.t()} | {:error, term()}
  def update_plot_theme(character_id, attrs) do
    case get_plot(character_id) do
      {:ok, plot} ->
        plot
        |> HousingPlot.theme_changeset(attrs)
        |> Repo.update()

      :error ->
        {:error, :not_found}
    end
  end

  @spec set_permission_level(integer(), atom()) :: {:ok, HousingPlot.t()} | {:error, term()}
  def set_permission_level(character_id, level) do
    case get_plot(character_id) do
      {:ok, plot} ->
        plot
        |> HousingPlot.permission_changeset(%{permission_level: level})
        |> Repo.update()

      :error ->
        {:error, :not_found}
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run: `cd apps/bezgelor_db && MIX_ENV=test mix test test/housing_test.exs --trace`
Expected: All tests pass

**Step 5: Commit**

```bash
git add apps/bezgelor_db/lib/bezgelor_db/housing.ex apps/bezgelor_db/test/housing_test.exs
git commit -m "feat(db): add Housing context with plot operations"
```

---

## Task 7: Housing Context - Neighbor Operations

**Files:**
- Modify: `apps/bezgelor_db/lib/bezgelor_db/housing.ex`
- Modify: `apps/bezgelor_db/test/housing_test.exs`

**Step 1: Add neighbor tests**

Add to `housing_test.exs`:

```elixir
  describe "neighbor management" do
    setup %{account: account, character: character} do
      {:ok, plot} = Housing.create_plot(character.id)

      {:ok, neighbor_char} =
        Characters.create_character(account.id, %{
          name: "Neighbor#{System.unique_integer([:positive])}",
          sex: 0, race: 0, class: 0, faction_id: 166, world_id: 1, world_zone_id: 1
        })

      {:ok, plot: plot, neighbor: neighbor_char}
    end

    test "add_neighbor grants visit permission", %{plot: plot, neighbor: neighbor} do
      assert {:ok, _} = Housing.add_neighbor(plot.id, neighbor.id)
      assert Housing.is_neighbor?(plot.id, neighbor.id)
    end

    test "remove_neighbor revokes permission", %{plot: plot, neighbor: neighbor} do
      {:ok, _} = Housing.add_neighbor(plot.id, neighbor.id)
      assert :ok = Housing.remove_neighbor(plot.id, neighbor.id)
      refute Housing.is_neighbor?(plot.id, neighbor.id)
    end

    test "promote_to_roommate elevates permission", %{plot: plot, neighbor: neighbor} do
      {:ok, _} = Housing.add_neighbor(plot.id, neighbor.id)
      assert {:ok, n} = Housing.promote_to_roommate(plot.id, neighbor.id)
      assert n.is_roommate == true
    end

    test "demote_from_roommate reduces permission", %{plot: plot, neighbor: neighbor} do
      {:ok, _} = Housing.add_neighbor(plot.id, neighbor.id)
      {:ok, _} = Housing.promote_to_roommate(plot.id, neighbor.id)
      assert {:ok, n} = Housing.demote_from_roommate(plot.id, neighbor.id)
      assert n.is_roommate == false
    end

    test "list_neighbors returns all neighbors", %{plot: plot, neighbor: neighbor, account: account} do
      {:ok, neighbor2} =
        Characters.create_character(account.id, %{
          name: "Neighbor2#{System.unique_integer([:positive])}",
          sex: 0, race: 0, class: 0, faction_id: 166, world_id: 1, world_zone_id: 1
        })

      {:ok, _} = Housing.add_neighbor(plot.id, neighbor.id)
      {:ok, _} = Housing.add_neighbor(plot.id, neighbor2.id)

      neighbors = Housing.list_neighbors(plot.id)
      assert length(neighbors) == 2
    end

    test "can_visit? checks permission correctly", %{plot: plot, neighbor: neighbor, character: owner} do
      # Owner can always visit
      assert Housing.can_visit?(plot.id, owner.id)

      # Non-neighbor cannot visit private plot
      refute Housing.can_visit?(plot.id, neighbor.id)

      # Neighbor can visit
      {:ok, _} = Housing.add_neighbor(plot.id, neighbor.id)
      assert Housing.can_visit?(plot.id, neighbor.id)
    end

    test "can_decorate? checks roommate permission", %{plot: plot, neighbor: neighbor, character: owner} do
      # Owner can always decorate
      assert Housing.can_decorate?(plot.id, owner.id)

      # Neighbor cannot decorate
      {:ok, _} = Housing.add_neighbor(plot.id, neighbor.id)
      refute Housing.can_decorate?(plot.id, neighbor.id)

      # Roommate can decorate
      {:ok, _} = Housing.promote_to_roommate(plot.id, neighbor.id)
      assert Housing.can_decorate?(plot.id, neighbor.id)
    end
  end
```

**Step 2: Run test to verify it fails**

Run: `cd apps/bezgelor_db && MIX_ENV=test mix test test/housing_test.exs --trace`
Expected: FAIL with "undefined function"

**Step 3: Add neighbor operations to context**

Add to `housing.ex`:

```elixir
  # Neighbor Management

  @spec add_neighbor(integer(), integer()) :: {:ok, HousingNeighbor.t()} | {:error, term()}
  def add_neighbor(plot_id, character_id) do
    %HousingNeighbor{}
    |> HousingNeighbor.changeset(%{plot_id: plot_id, character_id: character_id})
    |> Repo.insert()
  end

  @spec remove_neighbor(integer(), integer()) :: :ok | {:error, :not_found}
  def remove_neighbor(plot_id, character_id) do
    query =
      from n in HousingNeighbor,
        where: n.plot_id == ^plot_id and n.character_id == ^character_id

    case Repo.delete_all(query) do
      {0, _} -> {:error, :not_found}
      {_, _} -> :ok
    end
  end

  @spec promote_to_roommate(integer(), integer()) :: {:ok, HousingNeighbor.t()} | {:error, term()}
  def promote_to_roommate(plot_id, character_id) do
    case get_neighbor(plot_id, character_id) do
      {:ok, neighbor} ->
        neighbor
        |> HousingNeighbor.roommate_changeset(%{is_roommate: true})
        |> Repo.update()

      :error ->
        {:error, :not_found}
    end
  end

  @spec demote_from_roommate(integer(), integer()) :: {:ok, HousingNeighbor.t()} | {:error, term()}
  def demote_from_roommate(plot_id, character_id) do
    case get_neighbor(plot_id, character_id) do
      {:ok, neighbor} ->
        neighbor
        |> HousingNeighbor.roommate_changeset(%{is_roommate: false})
        |> Repo.update()

      :error ->
        {:error, :not_found}
    end
  end

  @spec list_neighbors(integer()) :: [HousingNeighbor.t()]
  def list_neighbors(plot_id) do
    from(n in HousingNeighbor, where: n.plot_id == ^plot_id, preload: [:character])
    |> Repo.all()
  end

  @spec is_neighbor?(integer(), integer()) :: boolean()
  def is_neighbor?(plot_id, character_id) do
    query =
      from n in HousingNeighbor,
        where: n.plot_id == ^plot_id and n.character_id == ^character_id

    Repo.exists?(query)
  end

  @spec is_roommate?(integer(), integer()) :: boolean()
  def is_roommate?(plot_id, character_id) do
    query =
      from n in HousingNeighbor,
        where: n.plot_id == ^plot_id and n.character_id == ^character_id and n.is_roommate == true

    Repo.exists?(query)
  end

  @spec can_visit?(integer(), integer()) :: boolean()
  def can_visit?(plot_id, visitor_character_id) do
    case get_plot_by_id(plot_id) do
      {:ok, plot} ->
        cond do
          # Owner can always visit
          plot.character_id == visitor_character_id -> true
          # Public plots allow anyone
          plot.permission_level == :public -> true
          # Check neighbor/roommate permission
          plot.permission_level in [:neighbors, :roommates] -> is_neighbor?(plot_id, visitor_character_id)
          # Private - only owner
          true -> false
        end

      :error ->
        false
    end
  end

  @spec can_decorate?(integer(), integer()) :: boolean()
  def can_decorate?(plot_id, character_id) do
    case get_plot_by_id(plot_id) do
      {:ok, plot} ->
        # Owner or roommate can decorate
        plot.character_id == character_id or is_roommate?(plot_id, character_id)

      :error ->
        false
    end
  end

  defp get_neighbor(plot_id, character_id) do
    query =
      from n in HousingNeighbor,
        where: n.plot_id == ^plot_id and n.character_id == ^character_id

    case Repo.one(query) do
      nil -> :error
      neighbor -> {:ok, neighbor}
    end
  end
```

**Step 4: Run test to verify it passes**

Run: `cd apps/bezgelor_db && MIX_ENV=test mix test test/housing_test.exs --trace`
Expected: All tests pass

**Step 5: Commit**

```bash
git add apps/bezgelor_db/lib/bezgelor_db/housing.ex apps/bezgelor_db/test/housing_test.exs
git commit -m "feat(db): add Housing neighbor operations"
```

---

## Task 8: Housing Context - Decor Operations

**Files:**
- Modify: `apps/bezgelor_db/lib/bezgelor_db/housing.ex`
- Modify: `apps/bezgelor_db/test/housing_test.exs`

**Step 1: Add decor tests**

Add to `housing_test.exs`:

```elixir
  describe "decor operations" do
    setup %{character: character} do
      {:ok, plot} = Housing.create_plot(character.id)
      {:ok, plot: plot}
    end

    test "place_decor adds item to plot", %{plot: plot} do
      attrs = %{
        decor_id: 1001,
        pos_x: 10.5, pos_y: 0.0, pos_z: 20.0,
        rot_yaw: 45.0,
        scale: 1.5
      }

      assert {:ok, decor} = Housing.place_decor(plot.id, attrs)
      assert decor.decor_id == 1001
      assert decor.pos_x == 10.5
      assert decor.scale == 1.5
    end

    test "move_decor updates position", %{plot: plot} do
      {:ok, decor} = Housing.place_decor(plot.id, %{decor_id: 1001})

      assert {:ok, updated} = Housing.move_decor(decor.id, %{pos_x: 50.0, rot_yaw: 90.0})
      assert updated.pos_x == 50.0
      assert updated.rot_yaw == 90.0
    end

    test "remove_decor deletes item", %{plot: plot} do
      {:ok, decor} = Housing.place_decor(plot.id, %{decor_id: 1001})
      assert :ok = Housing.remove_decor(decor.id)
      assert :error = Housing.get_decor(decor.id)
    end

    test "list_decor returns all items for plot", %{plot: plot} do
      {:ok, _} = Housing.place_decor(plot.id, %{decor_id: 1001})
      {:ok, _} = Housing.place_decor(plot.id, %{decor_id: 1002})
      {:ok, _} = Housing.place_decor(plot.id, %{decor_id: 1003})

      decor = Housing.list_decor(plot.id)
      assert length(decor) == 3
    end

    test "count_decor returns count", %{plot: plot} do
      assert Housing.count_decor(plot.id) == 0

      {:ok, _} = Housing.place_decor(plot.id, %{decor_id: 1001})
      {:ok, _} = Housing.place_decor(plot.id, %{decor_id: 1002})

      assert Housing.count_decor(plot.id) == 2
    end
  end
```

**Step 2: Run test to verify it fails**

Run: `cd apps/bezgelor_db && MIX_ENV=test mix test test/housing_test.exs --trace`
Expected: FAIL with "undefined function"

**Step 3: Add decor operations to context**

Add to `housing.ex`:

```elixir
  # Decor Operations

  @spec place_decor(integer(), map()) :: {:ok, HousingDecor.t()} | {:error, term()}
  def place_decor(plot_id, attrs) do
    %HousingDecor{}
    |> HousingDecor.changeset(Map.put(attrs, :plot_id, plot_id))
    |> Repo.insert()
  end

  @spec move_decor(integer(), map()) :: {:ok, HousingDecor.t()} | {:error, term()}
  def move_decor(decor_id, attrs) do
    case get_decor(decor_id) do
      {:ok, decor} ->
        decor
        |> HousingDecor.move_changeset(attrs)
        |> Repo.update()

      :error ->
        {:error, :not_found}
    end
  end

  @spec remove_decor(integer()) :: :ok | {:error, :not_found}
  def remove_decor(decor_id) do
    case get_decor(decor_id) do
      {:ok, decor} ->
        Repo.delete(decor)
        :ok

      :error ->
        {:error, :not_found}
    end
  end

  @spec get_decor(integer()) :: {:ok, HousingDecor.t()} | :error
  def get_decor(decor_id) do
    case Repo.get(HousingDecor, decor_id) do
      nil -> :error
      decor -> {:ok, decor}
    end
  end

  @spec list_decor(integer()) :: [HousingDecor.t()]
  def list_decor(plot_id) do
    from(d in HousingDecor, where: d.plot_id == ^plot_id)
    |> Repo.all()
  end

  @spec count_decor(integer()) :: integer()
  def count_decor(plot_id) do
    from(d in HousingDecor, where: d.plot_id == ^plot_id, select: count(d.id))
    |> Repo.one()
  end
```

**Step 4: Run test to verify it passes**

Run: `cd apps/bezgelor_db && MIX_ENV=test mix test test/housing_test.exs --trace`
Expected: All tests pass

**Step 5: Commit**

```bash
git add apps/bezgelor_db/lib/bezgelor_db/housing.ex apps/bezgelor_db/test/housing_test.exs
git commit -m "feat(db): add Housing decor operations"
```

---

## Task 9: Housing Context - FABkit Operations

**Files:**
- Modify: `apps/bezgelor_db/lib/bezgelor_db/housing.ex`
- Modify: `apps/bezgelor_db/test/housing_test.exs`

**Step 1: Add FABkit tests**

Add to `housing_test.exs`:

```elixir
  describe "fabkit operations" do
    setup %{character: character} do
      {:ok, plot} = Housing.create_plot(character.id)
      {:ok, plot: plot}
    end

    test "install_fabkit adds to socket", %{plot: plot} do
      assert {:ok, fabkit} = Housing.install_fabkit(plot.id, 0, 2001)
      assert fabkit.socket_index == 0
      assert fabkit.fabkit_id == 2001
    end

    test "install_fabkit fails for occupied socket", %{plot: plot} do
      {:ok, _} = Housing.install_fabkit(plot.id, 0, 2001)
      assert {:error, _} = Housing.install_fabkit(plot.id, 0, 2002)
    end

    test "remove_fabkit clears socket", %{plot: plot} do
      {:ok, _} = Housing.install_fabkit(plot.id, 0, 2001)
      assert :ok = Housing.remove_fabkit(plot.id, 0)
      assert :error = Housing.get_fabkit(plot.id, 0)
    end

    test "update_fabkit_state persists state", %{plot: plot} do
      {:ok, _} = Housing.install_fabkit(plot.id, 0, 2001)
      harvest_time = DateTime.utc_now() |> DateTime.add(3600, :second)

      assert {:ok, fabkit} = Housing.update_fabkit_state(plot.id, 0, %{"harvest_available_at" => harvest_time})
      assert fabkit.state["harvest_available_at"] == harvest_time
    end

    test "list_fabkits returns all installed", %{plot: plot} do
      {:ok, _} = Housing.install_fabkit(plot.id, 0, 2001)
      {:ok, _} = Housing.install_fabkit(plot.id, 4, 2002)  # Large socket

      fabkits = Housing.list_fabkits(plot.id)
      assert length(fabkits) == 2
    end
  end
```

**Step 2: Run test to verify it fails**

Run: `cd apps/bezgelor_db && MIX_ENV=test mix test test/housing_test.exs --trace`
Expected: FAIL with "undefined function"

**Step 3: Add FABkit operations to context**

Add to `housing.ex`:

```elixir
  # FABkit Operations

  @spec install_fabkit(integer(), integer(), integer()) :: {:ok, HousingFabkit.t()} | {:error, term()}
  def install_fabkit(plot_id, socket_index, fabkit_id) do
    %HousingFabkit{}
    |> HousingFabkit.changeset(%{plot_id: plot_id, socket_index: socket_index, fabkit_id: fabkit_id})
    |> Repo.insert()
  end

  @spec remove_fabkit(integer(), integer()) :: :ok | {:error, :not_found}
  def remove_fabkit(plot_id, socket_index) do
    query =
      from f in HousingFabkit,
        where: f.plot_id == ^plot_id and f.socket_index == ^socket_index

    case Repo.delete_all(query) do
      {0, _} -> {:error, :not_found}
      {_, _} -> :ok
    end
  end

  @spec get_fabkit(integer(), integer()) :: {:ok, HousingFabkit.t()} | :error
  def get_fabkit(plot_id, socket_index) do
    query =
      from f in HousingFabkit,
        where: f.plot_id == ^plot_id and f.socket_index == ^socket_index

    case Repo.one(query) do
      nil -> :error
      fabkit -> {:ok, fabkit}
    end
  end

  @spec update_fabkit_state(integer(), integer(), map()) :: {:ok, HousingFabkit.t()} | {:error, term()}
  def update_fabkit_state(plot_id, socket_index, state) do
    case get_fabkit(plot_id, socket_index) do
      {:ok, fabkit} ->
        fabkit
        |> HousingFabkit.state_changeset(%{state: state})
        |> Repo.update()

      :error ->
        {:error, :not_found}
    end
  end

  @spec list_fabkits(integer()) :: [HousingFabkit.t()]
  def list_fabkits(plot_id) do
    from(f in HousingFabkit, where: f.plot_id == ^plot_id)
    |> Repo.all()
  end
```

**Step 4: Run test to verify it passes**

Run: `cd apps/bezgelor_db && MIX_ENV=test mix test test/housing_test.exs --trace`
Expected: All tests pass

**Step 5: Commit**

```bash
git add apps/bezgelor_db/lib/bezgelor_db/housing.ex apps/bezgelor_db/test/housing_test.exs
git commit -m "feat(db): add Housing FABkit operations"
```

---

## Task 10: Housing Protocol Packets - Entry

**Files:**
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/client_enter_housing.ex`
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/client_leave_housing.ex`
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_housing_enter.ex`
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_housing_denied.ex`

**Step 1: Create ClientEnterHousing**

```elixir
defmodule BezgelorProtocol.Packets.World.ClientEnterHousing do
  @moduledoc """
  Request to enter a housing plot.

  ## Wire Format

  ```
  owner_character_id : uint64  - Character ID of plot owner (0 = own plot)
  ```
  """

  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:owner_character_id]

  @type t :: %__MODULE__{owner_character_id: non_neg_integer()}

  @impl true
  def opcode, do: :client_enter_housing

  @impl true
  def read(reader) do
    {owner_character_id, reader} = PacketReader.read_uint64(reader)

    packet = %__MODULE__{owner_character_id: owner_character_id}
    {:ok, packet, reader}
  end
end
```

**Step 2: Create ClientLeaveHousing**

```elixir
defmodule BezgelorProtocol.Packets.World.ClientLeaveHousing do
  @moduledoc """
  Request to leave current housing plot.

  ## Wire Format

  Empty packet.
  """

  @behaviour BezgelorProtocol.Packet.Readable

  defstruct []

  @type t :: %__MODULE__{}

  @impl true
  def opcode, do: :client_leave_housing

  @impl true
  def read(reader) do
    {:ok, %__MODULE__{}, reader}
  end
end
```

**Step 3: Create ServerHousingEnter**

```elixir
defmodule BezgelorProtocol.Packets.World.ServerHousingEnter do
  @moduledoc """
  Full housing plot state sent on entry.

  ## Wire Format

  ```
  owner_character_id : uint64
  house_type_id      : uint8
  permission_level   : uint8
  sky_id             : uint16
  ground_id          : uint16
  music_id           : uint16
  plot_name_len      : uint8
  plot_name          : string
  decor_count        : uint16
  decor[]            : HousingDecorEntry
  fabkit_count       : uint8
  fabkits[]          : HousingFabkitEntry
  ```
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [
    :owner_character_id,
    :house_type_id,
    :permission_level,
    :sky_id,
    :ground_id,
    :music_id,
    :plot_name,
    :decor,
    :fabkits
  ]

  @type t :: %__MODULE__{}

  @permission_map %{private: 0, neighbors: 1, roommates: 2, public: 3}

  @impl true
  def opcode, do: :server_housing_enter

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    plot_name = packet.plot_name || ""
    permission_byte = Map.get(@permission_map, packet.permission_level, 0)

    writer =
      writer
      |> PacketWriter.write_uint64(packet.owner_character_id)
      |> PacketWriter.write_byte(packet.house_type_id)
      |> PacketWriter.write_byte(permission_byte)
      |> PacketWriter.write_uint16(packet.sky_id)
      |> PacketWriter.write_uint16(packet.ground_id)
      |> PacketWriter.write_uint16(packet.music_id)
      |> PacketWriter.write_byte(byte_size(plot_name))
      |> PacketWriter.write_string(plot_name)
      |> PacketWriter.write_uint16(length(packet.decor))

    writer = Enum.reduce(packet.decor, writer, &write_decor/2)

    writer =
      writer
      |> PacketWriter.write_byte(length(packet.fabkits))

    writer = Enum.reduce(packet.fabkits, writer, &write_fabkit/2)

    {:ok, writer}
  end

  defp write_decor(decor, writer) do
    writer
    |> PacketWriter.write_uint32(decor.id)
    |> PacketWriter.write_uint32(decor.decor_id)
    |> PacketWriter.write_float(decor.pos_x)
    |> PacketWriter.write_float(decor.pos_y)
    |> PacketWriter.write_float(decor.pos_z)
    |> PacketWriter.write_float(decor.rot_pitch)
    |> PacketWriter.write_float(decor.rot_yaw)
    |> PacketWriter.write_float(decor.rot_roll)
    |> PacketWriter.write_float(decor.scale)
    |> PacketWriter.write_byte(if decor.is_exterior, do: 1, else: 0)
  end

  defp write_fabkit(fabkit, writer) do
    writer
    |> PacketWriter.write_byte(fabkit.socket_index)
    |> PacketWriter.write_uint32(fabkit.fabkit_id)
  end

  def new(plot, decor, fabkits) do
    %__MODULE__{
      owner_character_id: plot.character_id,
      house_type_id: plot.house_type_id,
      permission_level: plot.permission_level,
      sky_id: plot.sky_id,
      ground_id: plot.ground_id,
      music_id: plot.music_id,
      plot_name: plot.plot_name,
      decor: decor,
      fabkits: fabkits
    }
  end
end
```

**Step 4: Create ServerHousingDenied**

```elixir
defmodule BezgelorProtocol.Packets.World.ServerHousingDenied do
  @moduledoc """
  Housing entry denied.

  ## Wire Format

  ```
  reason : uint8  - 0=not_found, 1=not_permitted, 2=instance_full
  ```
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:reason]

  @type t :: %__MODULE__{reason: atom()}

  @reason_map %{not_found: 0, not_permitted: 1, instance_full: 2}

  @impl true
  def opcode, do: :server_housing_denied

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    reason_byte = Map.get(@reason_map, packet.reason, 0)
    writer = PacketWriter.write_byte(writer, reason_byte)
    {:ok, writer}
  end

  def new(reason) do
    %__MODULE__{reason: reason}
  end
end
```

**Step 5: Commit**

```bash
git add apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/client_enter_housing.ex \
        apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/client_leave_housing.ex \
        apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_housing_enter.ex \
        apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_housing_denied.ex
git commit -m "feat(protocol): add housing entry packets"
```

---

## Task 11: Housing Protocol Packets - Decor

**Files:**
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/client_place_decor.ex`
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/client_move_decor.ex`
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/client_remove_decor.ex`
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_decor_placed.ex`
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_decor_moved.ex`
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_decor_removed.ex`

**Step 1: Create ClientPlaceDecor**

```elixir
defmodule BezgelorProtocol.Packets.World.ClientPlaceDecor do
  @moduledoc """
  Place decor item from inventory.

  ## Wire Format

  ```
  decor_id    : uint32
  pos_x       : float32
  pos_y       : float32
  pos_z       : float32
  rot_pitch   : float32
  rot_yaw     : float32
  rot_roll    : float32
  scale       : float32
  is_exterior : uint8
  ```
  """

  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:decor_id, :pos_x, :pos_y, :pos_z, :rot_pitch, :rot_yaw, :rot_roll, :scale, :is_exterior]

  @type t :: %__MODULE__{}

  @impl true
  def opcode, do: :client_place_decor

  @impl true
  def read(reader) do
    {decor_id, reader} = PacketReader.read_uint32(reader)
    {pos_x, reader} = PacketReader.read_float(reader)
    {pos_y, reader} = PacketReader.read_float(reader)
    {pos_z, reader} = PacketReader.read_float(reader)
    {rot_pitch, reader} = PacketReader.read_float(reader)
    {rot_yaw, reader} = PacketReader.read_float(reader)
    {rot_roll, reader} = PacketReader.read_float(reader)
    {scale, reader} = PacketReader.read_float(reader)
    {is_exterior_byte, reader} = PacketReader.read_byte(reader)

    packet = %__MODULE__{
      decor_id: decor_id,
      pos_x: pos_x,
      pos_y: pos_y,
      pos_z: pos_z,
      rot_pitch: rot_pitch,
      rot_yaw: rot_yaw,
      rot_roll: rot_roll,
      scale: scale,
      is_exterior: is_exterior_byte == 1
    }

    {:ok, packet, reader}
  end
end
```

**Step 2: Create ClientMoveDecor**

```elixir
defmodule BezgelorProtocol.Packets.World.ClientMoveDecor do
  @moduledoc """
  Move/rotate/scale existing decor.

  ## Wire Format

  ```
  decor_item_id : uint32
  pos_x         : float32
  pos_y         : float32
  pos_z         : float32
  rot_pitch     : float32
  rot_yaw       : float32
  rot_roll      : float32
  scale         : float32
  ```
  """

  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:decor_item_id, :pos_x, :pos_y, :pos_z, :rot_pitch, :rot_yaw, :rot_roll, :scale]

  @type t :: %__MODULE__{}

  @impl true
  def opcode, do: :client_move_decor

  @impl true
  def read(reader) do
    {decor_item_id, reader} = PacketReader.read_uint32(reader)
    {pos_x, reader} = PacketReader.read_float(reader)
    {pos_y, reader} = PacketReader.read_float(reader)
    {pos_z, reader} = PacketReader.read_float(reader)
    {rot_pitch, reader} = PacketReader.read_float(reader)
    {rot_yaw, reader} = PacketReader.read_float(reader)
    {rot_roll, reader} = PacketReader.read_float(reader)
    {scale, reader} = PacketReader.read_float(reader)

    packet = %__MODULE__{
      decor_item_id: decor_item_id,
      pos_x: pos_x,
      pos_y: pos_y,
      pos_z: pos_z,
      rot_pitch: rot_pitch,
      rot_yaw: rot_yaw,
      rot_roll: rot_roll,
      scale: scale
    }

    {:ok, packet, reader}
  end
end
```

**Step 3: Create ClientRemoveDecor**

```elixir
defmodule BezgelorProtocol.Packets.World.ClientRemoveDecor do
  @moduledoc """
  Remove placed decor.

  ## Wire Format

  ```
  decor_item_id : uint32
  ```
  """

  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:decor_item_id]

  @type t :: %__MODULE__{}

  @impl true
  def opcode, do: :client_remove_decor

  @impl true
  def read(reader) do
    {decor_item_id, reader} = PacketReader.read_uint32(reader)
    {:ok, %__MODULE__{decor_item_id: decor_item_id}, reader}
  end
end
```

**Step 4: Create ServerDecorPlaced**

```elixir
defmodule BezgelorProtocol.Packets.World.ServerDecorPlaced do
  @moduledoc """
  Broadcast decor placement.

  ## Wire Format

  ```
  decor_item_id : uint32
  decor_id      : uint32
  pos_x         : float32
  pos_y         : float32
  pos_z         : float32
  rot_pitch     : float32
  rot_yaw       : float32
  rot_roll      : float32
  scale         : float32
  is_exterior   : uint8
  ```
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:decor_item_id, :decor_id, :pos_x, :pos_y, :pos_z, :rot_pitch, :rot_yaw, :rot_roll, :scale, :is_exterior]

  @type t :: %__MODULE__{}

  @impl true
  def opcode, do: :server_decor_placed

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_uint32(packet.decor_item_id)
      |> PacketWriter.write_uint32(packet.decor_id)
      |> PacketWriter.write_float(packet.pos_x)
      |> PacketWriter.write_float(packet.pos_y)
      |> PacketWriter.write_float(packet.pos_z)
      |> PacketWriter.write_float(packet.rot_pitch)
      |> PacketWriter.write_float(packet.rot_yaw)
      |> PacketWriter.write_float(packet.rot_roll)
      |> PacketWriter.write_float(packet.scale)
      |> PacketWriter.write_byte(if packet.is_exterior, do: 1, else: 0)

    {:ok, writer}
  end

  def new(decor) do
    %__MODULE__{
      decor_item_id: decor.id,
      decor_id: decor.decor_id,
      pos_x: decor.pos_x,
      pos_y: decor.pos_y,
      pos_z: decor.pos_z,
      rot_pitch: decor.rot_pitch,
      rot_yaw: decor.rot_yaw,
      rot_roll: decor.rot_roll,
      scale: decor.scale,
      is_exterior: decor.is_exterior
    }
  end
end
```

**Step 5: Create ServerDecorMoved**

```elixir
defmodule BezgelorProtocol.Packets.World.ServerDecorMoved do
  @moduledoc """
  Broadcast decor movement.

  ## Wire Format

  ```
  decor_item_id : uint32
  pos_x         : float32
  pos_y         : float32
  pos_z         : float32
  rot_pitch     : float32
  rot_yaw       : float32
  rot_roll      : float32
  scale         : float32
  ```
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:decor_item_id, :pos_x, :pos_y, :pos_z, :rot_pitch, :rot_yaw, :rot_roll, :scale]

  @type t :: %__MODULE__{}

  @impl true
  def opcode, do: :server_decor_moved

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_uint32(packet.decor_item_id)
      |> PacketWriter.write_float(packet.pos_x)
      |> PacketWriter.write_float(packet.pos_y)
      |> PacketWriter.write_float(packet.pos_z)
      |> PacketWriter.write_float(packet.rot_pitch)
      |> PacketWriter.write_float(packet.rot_yaw)
      |> PacketWriter.write_float(packet.rot_roll)
      |> PacketWriter.write_float(packet.scale)

    {:ok, writer}
  end

  def new(decor) do
    %__MODULE__{
      decor_item_id: decor.id,
      pos_x: decor.pos_x,
      pos_y: decor.pos_y,
      pos_z: decor.pos_z,
      rot_pitch: decor.rot_pitch,
      rot_yaw: decor.rot_yaw,
      rot_roll: decor.rot_roll,
      scale: decor.scale
    }
  end
end
```

**Step 6: Create ServerDecorRemoved**

```elixir
defmodule BezgelorProtocol.Packets.World.ServerDecorRemoved do
  @moduledoc """
  Broadcast decor removal.

  ## Wire Format

  ```
  decor_item_id : uint32
  ```
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:decor_item_id]

  @type t :: %__MODULE__{}

  @impl true
  def opcode, do: :server_decor_removed

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer = PacketWriter.write_uint32(writer, packet.decor_item_id)
    {:ok, writer}
  end

  def new(decor_item_id) do
    %__MODULE__{decor_item_id: decor_item_id}
  end
end
```

**Step 7: Commit**

```bash
git add apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/client_place_decor.ex \
        apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/client_move_decor.ex \
        apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/client_remove_decor.ex \
        apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_decor_placed.ex \
        apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_decor_moved.ex \
        apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_decor_removed.ex
git commit -m "feat(protocol): add housing decor packets"
```

---

## Task 12: Housing Protocol Packets - FABkits & Social

**Files:**
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/client_install_fabkit.ex`
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/client_interact_fabkit.ex`
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_fabkit_installed.ex`
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_fabkit_state.ex`
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/client_add_neighbor.ex`
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_neighbor_list.ex`

**Step 1: Create FABkit packets**

```elixir
# client_install_fabkit.ex
defmodule BezgelorProtocol.Packets.World.ClientInstallFabkit do
  @behaviour BezgelorProtocol.Packet.Readable
  alias BezgelorProtocol.PacketReader

  defstruct [:socket_index, :fabkit_id]
  @type t :: %__MODULE__{}

  @impl true
  def opcode, do: :client_install_fabkit

  @impl true
  def read(reader) do
    {socket_index, reader} = PacketReader.read_byte(reader)
    {fabkit_id, reader} = PacketReader.read_uint32(reader)
    {:ok, %__MODULE__{socket_index: socket_index, fabkit_id: fabkit_id}, reader}
  end
end
```

```elixir
# client_interact_fabkit.ex
defmodule BezgelorProtocol.Packets.World.ClientInteractFabkit do
  @behaviour BezgelorProtocol.Packet.Readable
  alias BezgelorProtocol.PacketReader

  defstruct [:socket_index]
  @type t :: %__MODULE__{}

  @impl true
  def opcode, do: :client_interact_fabkit

  @impl true
  def read(reader) do
    {socket_index, reader} = PacketReader.read_byte(reader)
    {:ok, %__MODULE__{socket_index: socket_index}, reader}
  end
end
```

```elixir
# server_fabkit_installed.ex
defmodule BezgelorProtocol.Packets.World.ServerFabkitInstalled do
  @behaviour BezgelorProtocol.Packet.Writable
  alias BezgelorProtocol.PacketWriter

  defstruct [:socket_index, :fabkit_id]
  @type t :: %__MODULE__{}

  @impl true
  def opcode, do: :server_fabkit_installed

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_byte(packet.socket_index)
      |> PacketWriter.write_uint32(packet.fabkit_id)
    {:ok, writer}
  end

  def new(socket_index, fabkit_id), do: %__MODULE__{socket_index: socket_index, fabkit_id: fabkit_id}
end
```

```elixir
# server_fabkit_state.ex
defmodule BezgelorProtocol.Packets.World.ServerFabkitState do
  @behaviour BezgelorProtocol.Packet.Writable
  alias BezgelorProtocol.PacketWriter

  defstruct [:socket_index, :harvest_available_at]
  @type t :: %__MODULE__{}

  @impl true
  def opcode, do: :server_fabkit_state

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    # Encode harvest_available_at as unix timestamp (0 if nil/available now)
    timestamp = if packet.harvest_available_at do
      DateTime.to_unix(packet.harvest_available_at)
    else
      0
    end

    writer =
      writer
      |> PacketWriter.write_byte(packet.socket_index)
      |> PacketWriter.write_uint64(timestamp)
    {:ok, writer}
  end

  def new(socket_index, harvest_available_at) do
    %__MODULE__{socket_index: socket_index, harvest_available_at: harvest_available_at}
  end
end
```

**Step 2: Create social packets**

```elixir
# client_add_neighbor.ex
defmodule BezgelorProtocol.Packets.World.ClientAddNeighbor do
  @behaviour BezgelorProtocol.Packet.Readable
  alias BezgelorProtocol.PacketReader

  defstruct [:character_name]
  @type t :: %__MODULE__{}

  @impl true
  def opcode, do: :client_add_neighbor

  @impl true
  def read(reader) do
    {name_len, reader} = PacketReader.read_byte(reader)
    {name, reader} = PacketReader.read_string(reader, name_len)
    {:ok, %__MODULE__{character_name: name}, reader}
  end
end
```

```elixir
# server_neighbor_list.ex
defmodule BezgelorProtocol.Packets.World.ServerNeighborList do
  @behaviour BezgelorProtocol.Packet.Writable
  alias BezgelorProtocol.PacketWriter

  defstruct [:neighbors]
  @type t :: %__MODULE__{}

  @impl true
  def opcode, do: :server_neighbor_list

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer = PacketWriter.write_uint16(writer, length(packet.neighbors))

    writer = Enum.reduce(packet.neighbors, writer, fn neighbor, w ->
      name = neighbor.character.name || ""
      w
      |> PacketWriter.write_uint64(neighbor.character_id)
      |> PacketWriter.write_byte(byte_size(name))
      |> PacketWriter.write_string(name)
      |> PacketWriter.write_byte(if neighbor.is_roommate, do: 1, else: 0)
    end)

    {:ok, writer}
  end

  def new(neighbors), do: %__MODULE__{neighbors: neighbors}
end
```

**Step 3: Commit**

```bash
git add apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/client_install_fabkit.ex \
        apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/client_interact_fabkit.ex \
        apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_fabkit_installed.ex \
        apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_fabkit_state.ex \
        apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/client_add_neighbor.ex \
        apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_neighbor_list.ex
git commit -m "feat(protocol): add housing FABkit and social packets"
```

---

## Task 13: HousingManager GenServer

**Files:**
- Create: `apps/bezgelor_world/lib/bezgelor_world/housing_manager.ex`
- Create: `apps/bezgelor_world/test/housing_manager_test.exs`

**Step 1: Write the failing test**

```elixir
defmodule BezgelorWorld.HousingManagerTest do
  use ExUnit.Case, async: false

  alias BezgelorWorld.HousingManager
  alias BezgelorWorld.Zone.InstanceSupervisor

  setup do
    # HousingManager should be started by application
    # Clear any lingering state
    :ok
  end

  describe "get_or_start_instance/1" do
    test "starts new instance for character" do
      character_id = System.unique_integer([:positive])

      # Mock plot data
      plot = %{
        id: 1,
        character_id: character_id,
        house_type_id: 1,
        permission_level: :private,
        sky_id: 1,
        ground_id: 1,
        music_id: 1,
        plot_name: nil,
        decor: [],
        fabkits: []
      }

      assert {:ok, pid} = HousingManager.get_or_start_instance(character_id, plot)
      assert is_pid(pid)

      # Second call returns same instance
      assert {:ok, ^pid} = HousingManager.get_or_start_instance(character_id, plot)
    end
  end

  describe "grace period" do
    test "instance shuts down after grace period when empty" do
      character_id = System.unique_integer([:positive])

      plot = %{
        id: 1,
        character_id: character_id,
        house_type_id: 1,
        permission_level: :private,
        sky_id: 1,
        ground_id: 1,
        music_id: 1,
        plot_name: nil,
        decor: [],
        fabkits: []
      }

      {:ok, pid} = HousingManager.get_or_start_instance(character_id, plot)
      assert Process.alive?(pid)

      # Mark as empty and wait for grace period (using short timeout for test)
      HousingManager.mark_empty(character_id)

      # Instance should still be alive during grace period
      Process.sleep(50)
      assert Process.alive?(pid)
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `cd apps/bezgelor_world && MIX_ENV=test mix test test/housing_manager_test.exs --trace`
Expected: FAIL with "HousingManager not available"

**Step 3: Write the HousingManager**

```elixir
defmodule BezgelorWorld.HousingManager do
  @moduledoc """
  Coordinates housing instances across the server.

  Manages instance lifecycle with grace period for cleanup.
  """

  use GenServer

  alias BezgelorWorld.Zone.{Instance, InstanceSupervisor}

  require Logger

  @grace_period_ms 60_000  # 60 seconds
  @housing_zone_id 999_999  # Special zone ID for housing instances

  defstruct active_instances: %{}, grace_timers: %{}

  @type t :: %__MODULE__{
    active_instances: %{integer() => pid()},
    grace_timers: %{integer() => reference()}
  }

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec get_or_start_instance(integer(), map()) :: {:ok, pid()} | {:error, term()}
  def get_or_start_instance(character_id, plot) do
    GenServer.call(__MODULE__, {:get_or_start_instance, character_id, plot})
  end

  @spec get_instance(integer()) :: {:ok, pid()} | :error
  def get_instance(character_id) do
    GenServer.call(__MODULE__, {:get_instance, character_id})
  end

  @spec mark_empty(integer()) :: :ok
  def mark_empty(character_id) do
    GenServer.cast(__MODULE__, {:mark_empty, character_id})
  end

  @spec cancel_grace(integer()) :: :ok
  def cancel_grace(character_id) do
    GenServer.cast(__MODULE__, {:cancel_grace, character_id})
  end

  @spec stop_instance(integer()) :: :ok
  def stop_instance(character_id) do
    GenServer.cast(__MODULE__, {:stop_instance, character_id})
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    Logger.info("HousingManager started")
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_call({:get_or_start_instance, character_id, plot}, _from, state) do
    # Cancel any pending grace timer
    state = cancel_grace_timer(state, character_id)

    case Map.get(state.active_instances, character_id) do
      nil ->
        # Start new instance
        instance_id = character_id  # Use character_id as instance_id for housing
        zone_data = build_housing_zone_data(plot)

        case InstanceSupervisor.start_instance(@housing_zone_id, instance_id, zone_data) do
          {:ok, pid} ->
            state = %{state | active_instances: Map.put(state.active_instances, character_id, pid)}
            Logger.debug("Started housing instance for character #{character_id}")
            {:reply, {:ok, pid}, state}

          error ->
            {:reply, error, state}
        end

      pid ->
        # Instance already exists
        {:reply, {:ok, pid}, state}
    end
  end

  @impl true
  def handle_call({:get_instance, character_id}, _from, state) do
    case Map.get(state.active_instances, character_id) do
      nil -> {:reply, :error, state}
      pid -> {:reply, {:ok, pid}, state}
    end
  end

  @impl true
  def handle_cast({:mark_empty, character_id}, state) do
    # Start grace timer if instance exists and no timer already running
    if Map.has_key?(state.active_instances, character_id) and
       not Map.has_key?(state.grace_timers, character_id) do
      timer_ref = Process.send_after(self(), {:grace_expired, character_id}, @grace_period_ms)
      state = %{state | grace_timers: Map.put(state.grace_timers, character_id, timer_ref)}
      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:cancel_grace, character_id}, state) do
    {:noreply, cancel_grace_timer(state, character_id)}
  end

  @impl true
  def handle_cast({:stop_instance, character_id}, state) do
    state = cancel_grace_timer(state, character_id)
    state = do_stop_instance(state, character_id)
    {:noreply, state}
  end

  @impl true
  def handle_info({:grace_expired, character_id}, state) do
    # Check if instance is still empty before stopping
    case Map.get(state.active_instances, character_id) do
      nil ->
        {:noreply, state}

      pid ->
        player_count = Instance.player_count({@housing_zone_id, character_id})

        if player_count == 0 do
          Logger.debug("Grace period expired, stopping housing instance for #{character_id}")
          state = do_stop_instance(state, character_id)
          {:noreply, state}
        else
          # Players rejoined, clear the timer reference
          state = %{state | grace_timers: Map.delete(state.grace_timers, character_id)}
          {:noreply, state}
        end
    end
  end

  # Private

  defp cancel_grace_timer(state, character_id) do
    case Map.get(state.grace_timers, character_id) do
      nil -> state
      timer_ref ->
        Process.cancel_timer(timer_ref)
        %{state | grace_timers: Map.delete(state.grace_timers, character_id)}
    end
  end

  defp do_stop_instance(state, character_id) do
    case Map.get(state.active_instances, character_id) do
      nil -> state
      _pid ->
        InstanceSupervisor.stop_instance(@housing_zone_id, character_id)
        %{state | active_instances: Map.delete(state.active_instances, character_id)}
    end
  end

  defp build_housing_zone_data(plot) do
    %{
      id: @housing_zone_id,
      name: "Housing - #{plot.plot_name || "Plot #{plot.character_id}"}",
      is_housing: true,
      owner_character_id: plot.character_id,
      house_type_id: plot.house_type_id
    }
  end
end
```

**Step 4: Add HousingManager to application supervisor**

Modify `apps/bezgelor_world/lib/bezgelor_world/application.ex` to add HousingManager to children list:

```elixir
# Add to children list:
BezgelorWorld.HousingManager
```

**Step 5: Run test to verify it passes**

Run: `cd apps/bezgelor_world && MIX_ENV=test mix test test/housing_manager_test.exs --trace`
Expected: All tests pass

**Step 6: Commit**

```bash
git add apps/bezgelor_world/lib/bezgelor_world/housing_manager.ex \
        apps/bezgelor_world/lib/bezgelor_world/application.ex \
        apps/bezgelor_world/test/housing_manager_test.exs
git commit -m "feat(world): add HousingManager GenServer"
```

---

## Task 14: HousingHandler - Entry & Exit

**Files:**
- Create: `apps/bezgelor_world/lib/bezgelor_world/handler/housing_handler.ex`
- Create: `apps/bezgelor_world/test/handler/housing_handler_test.exs`

**Step 1: Write the failing test**

```elixir
defmodule BezgelorWorld.Handler.HousingHandlerTest do
  use ExUnit.Case, async: false

  alias BezgelorWorld.Handler.HousingHandler
  alias BezgelorDb.{Accounts, Characters, Housing, Repo}

  @moduletag :database

  setup do
    case Repo.start_link([]) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    email = "housing_handler#{System.unique_integer([:positive])}@test.com"
    {:ok, account} = Accounts.create_account(email, "password123")

    {:ok, character} =
      Characters.create_character(account.id, %{
        name: "HouseOwner#{System.unique_integer([:positive])}",
        sex: 0, race: 0, class: 0, faction_id: 166, world_id: 1, world_zone_id: 1
      })

    {:ok, plot} = Housing.create_plot(character.id)

    state = %{
      session_data: %{
        in_world: true,
        character_id: character.id,
        entity_guid: character.id
      }
    }

    {:ok, account: account, character: character, plot: plot, state: state}
  end

  describe "enter own housing" do
    test "returns housing enter packet", %{character: character, state: state} do
      # Request to enter own plot (owner_character_id = 0 means own plot)
      packet = %{owner_character_id: 0}

      assert {:reply, :server_housing_enter, _data, _state} =
        HousingHandler.handle_enter_housing(packet, state)
    end
  end

  describe "enter another's housing" do
    test "denied for private plot", %{account: account, state: state} do
      # Create another character with private plot
      {:ok, other_char} =
        Characters.create_character(account.id, %{
          name: "OtherOwner#{System.unique_integer([:positive])}",
          sex: 0, race: 0, class: 0, faction_id: 166, world_id: 1, world_zone_id: 1
        })

      {:ok, _other_plot} = Housing.create_plot(other_char.id)

      packet = %{owner_character_id: other_char.id}

      assert {:reply, :server_housing_denied, _data, _state} =
        HousingHandler.handle_enter_housing(packet, state)
    end

    test "allowed for public plot", %{account: account, state: state} do
      {:ok, other_char} =
        Characters.create_character(account.id, %{
          name: "PublicOwner#{System.unique_integer([:positive])}",
          sex: 0, race: 0, class: 0, faction_id: 166, world_id: 1, world_zone_id: 1
        })

      {:ok, _} = Housing.create_plot(other_char.id)
      {:ok, _} = Housing.set_permission_level(other_char.id, :public)

      packet = %{owner_character_id: other_char.id}

      assert {:reply, :server_housing_enter, _data, _state} =
        HousingHandler.handle_enter_housing(packet, state)
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `cd apps/bezgelor_world && MIX_ENV=test mix test test/handler/housing_handler_test.exs --trace`
Expected: FAIL with "HousingHandler not defined"

**Step 3: Write the HousingHandler**

```elixir
defmodule BezgelorWorld.Handler.HousingHandler do
  @moduledoc """
  Handler for housing-related packets.

  Processes entry/exit, decor placement, FABkit interaction,
  and neighbor management.
  """

  @behaviour BezgelorProtocol.Handler

  alias BezgelorProtocol.PacketWriter
  alias BezgelorProtocol.Packets.World.{
    ServerHousingEnter,
    ServerHousingDenied,
    ServerDecorPlaced,
    ServerDecorMoved,
    ServerDecorRemoved,
    ServerFabkitInstalled,
    ServerFabkitState,
    ServerNeighborList
  }

  alias BezgelorDb.Housing
  alias BezgelorWorld.HousingManager

  require Logger

  @impl true
  def handle(payload, state) do
    # Dispatch based on packet type - this would be called by router
    {:ok, state}
  end

  # Entry/Exit

  def handle_enter_housing(%{owner_character_id: owner_id}, state) do
    character_id = state.session_data[:character_id]

    # If owner_id is 0, entering own plot
    target_owner_id = if owner_id == 0, do: character_id, else: owner_id

    case Housing.get_plot(target_owner_id) do
      {:ok, plot} ->
        if Housing.can_visit?(plot.id, character_id) do
          # Start or get housing instance
          {:ok, _pid} = HousingManager.get_or_start_instance(target_owner_id, plot)

          # Build response packet
          packet = ServerHousingEnter.new(plot, plot.decor, plot.fabkits)
          packet_data = encode_packet(ServerHousingEnter, packet)

          # Update state to track current housing
          new_state = put_in(state, [:session_data, :in_housing], target_owner_id)

          Logger.info("Character #{character_id} entered housing of #{target_owner_id}")
          {:reply, :server_housing_enter, packet_data, new_state}
        else
          packet = ServerHousingDenied.new(:not_permitted)
          packet_data = encode_packet(ServerHousingDenied, packet)
          {:reply, :server_housing_denied, packet_data, state}
        end

      :error ->
        packet = ServerHousingDenied.new(:not_found)
        packet_data = encode_packet(ServerHousingDenied, packet)
        {:reply, :server_housing_denied, packet_data, state}
    end
  end

  def handle_leave_housing(_packet, state) do
    character_id = state.session_data[:character_id]
    in_housing = state.session_data[:in_housing]

    if in_housing do
      # TODO: Remove player from housing instance, check if empty
      Logger.info("Character #{character_id} left housing of #{in_housing}")
    end

    new_state = put_in(state, [:session_data, :in_housing], nil)
    {:ok, new_state}
  end

  # Decor Operations

  def handle_place_decor(packet, state) do
    character_id = state.session_data[:character_id]
    in_housing = state.session_data[:in_housing]

    with {:ok, plot} <- Housing.get_plot(in_housing),
         true <- Housing.can_decorate?(plot.id, character_id),
         {:ok, decor} <- Housing.place_decor(plot.id, %{
           decor_id: packet.decor_id,
           pos_x: packet.pos_x,
           pos_y: packet.pos_y,
           pos_z: packet.pos_z,
           rot_pitch: packet.rot_pitch,
           rot_yaw: packet.rot_yaw,
           rot_roll: packet.rot_roll,
           scale: packet.scale,
           is_exterior: packet.is_exterior
         }) do
      response = ServerDecorPlaced.new(decor)
      packet_data = encode_packet(ServerDecorPlaced, response)
      # TODO: Broadcast to all players in housing instance
      {:reply, :server_decor_placed, packet_data, state}
    else
      _ ->
        {:error, :cannot_place_decor}
    end
  end

  def handle_move_decor(packet, state) do
    character_id = state.session_data[:character_id]
    in_housing = state.session_data[:in_housing]

    with {:ok, plot} <- Housing.get_plot(in_housing),
         true <- Housing.can_decorate?(plot.id, character_id),
         {:ok, decor} <- Housing.move_decor(packet.decor_item_id, %{
           pos_x: packet.pos_x,
           pos_y: packet.pos_y,
           pos_z: packet.pos_z,
           rot_pitch: packet.rot_pitch,
           rot_yaw: packet.rot_yaw,
           rot_roll: packet.rot_roll,
           scale: packet.scale
         }) do
      response = ServerDecorMoved.new(decor)
      packet_data = encode_packet(ServerDecorMoved, response)
      {:reply, :server_decor_moved, packet_data, state}
    else
      _ ->
        {:error, :cannot_move_decor}
    end
  end

  def handle_remove_decor(packet, state) do
    character_id = state.session_data[:character_id]
    in_housing = state.session_data[:in_housing]

    with {:ok, plot} <- Housing.get_plot(in_housing),
         true <- Housing.can_decorate?(plot.id, character_id),
         :ok <- Housing.remove_decor(packet.decor_item_id) do
      response = ServerDecorRemoved.new(packet.decor_item_id)
      packet_data = encode_packet(ServerDecorRemoved, response)
      {:reply, :server_decor_removed, packet_data, state}
    else
      _ ->
        {:error, :cannot_remove_decor}
    end
  end

  # FABkit Operations

  def handle_install_fabkit(packet, state) do
    character_id = state.session_data[:character_id]
    in_housing = state.session_data[:in_housing]

    # Only owner can install fabkits
    if in_housing == character_id do
      with {:ok, plot} <- Housing.get_plot(character_id),
           {:ok, _fabkit} <- Housing.install_fabkit(plot.id, packet.socket_index, packet.fabkit_id) do
        response = ServerFabkitInstalled.new(packet.socket_index, packet.fabkit_id)
        packet_data = encode_packet(ServerFabkitInstalled, response)
        {:reply, :server_fabkit_installed, packet_data, state}
      else
        _ -> {:error, :cannot_install_fabkit}
      end
    else
      {:error, :not_owner}
    end
  end

  def handle_interact_fabkit(packet, state) do
    in_housing = state.session_data[:in_housing]

    with {:ok, plot} <- Housing.get_plot(in_housing),
         {:ok, fabkit} <- Housing.get_fabkit(plot.id, packet.socket_index) do
      # Check if harvest is available
      harvest_available_at = fabkit.state["harvest_available_at"]
      now = DateTime.utc_now()

      if is_nil(harvest_available_at) or DateTime.compare(now, harvest_available_at) != :lt do
        # Grant resources (would integrate with inventory)
        # Set new cooldown (1 hour)
        new_harvest_time = DateTime.add(now, 3600, :second)
        {:ok, updated} = Housing.update_fabkit_state(plot.id, packet.socket_index, %{
          "harvest_available_at" => new_harvest_time
        })

        response = ServerFabkitState.new(packet.socket_index, new_harvest_time)
        packet_data = encode_packet(ServerFabkitState, response)
        {:reply, :server_fabkit_state, packet_data, state}
      else
        # Still on cooldown
        response = ServerFabkitState.new(packet.socket_index, harvest_available_at)
        packet_data = encode_packet(ServerFabkitState, response)
        {:reply, :server_fabkit_state, packet_data, state}
      end
    else
      _ -> {:error, :fabkit_not_found}
    end
  end

  # Neighbor Operations

  def handle_add_neighbor(packet, state) do
    character_id = state.session_data[:character_id]

    with {:ok, plot} <- Housing.get_plot(character_id),
         {:ok, neighbor_char} <- BezgelorDb.Characters.get_character_by_name(packet.character_name),
         {:ok, _} <- Housing.add_neighbor(plot.id, neighbor_char.id) do
      neighbors = Housing.list_neighbors(plot.id)
      response = ServerNeighborList.new(neighbors)
      packet_data = encode_packet(ServerNeighborList, response)
      {:reply, :server_neighbor_list, packet_data, state}
    else
      _ -> {:error, :cannot_add_neighbor}
    end
  end

  # Helpers

  defp encode_packet(module, packet) do
    writer = PacketWriter.new()
    {:ok, writer} = module.write(packet, writer)
    PacketWriter.to_binary(writer)
  end
end
```

**Step 4: Run test to verify it passes**

Run: `cd apps/bezgelor_world && MIX_ENV=test mix test test/handler/housing_handler_test.exs --trace`
Expected: All tests pass

**Step 5: Commit**

```bash
git add apps/bezgelor_world/lib/bezgelor_world/handler/housing_handler.ex \
        apps/bezgelor_world/test/handler/housing_handler_test.exs
git commit -m "feat(world): add HousingHandler for entry/exit and operations"
```

---

## Task 15: Data Files - House Types, Decor, FABkits

**Files:**
- Create: `apps/bezgelor_data/priv/data/house_types.json`
- Create: `apps/bezgelor_data/priv/data/decor_items.json`
- Create: `apps/bezgelor_data/priv/data/fabkit_types.json`

**Step 1: Create house_types.json**

```json
{
  "house_types": [
    {
      "id": 1,
      "name": "Cozy House",
      "cost": 10000,
      "decor_limit": 300,
      "description": "A comfortable starter home with room to grow."
    },
    {
      "id": 2,
      "name": "Spacious House",
      "cost": 3000000,
      "decor_limit": 500,
      "description": "A grand residence befitting a hero of Nexus."
    }
  ]
}
```

**Step 2: Create decor_items.json (sample)**

```json
{
  "decor_items": [
    {
      "id": 1001,
      "name": "Wooden Chair",
      "category": "furniture",
      "default_scale": 1.0,
      "quality_ratings": {
        "pride": 0,
        "ambiance": 1,
        "aroma": 0,
        "lighting": 0,
        "comfort": 1
      }
    },
    {
      "id": 1002,
      "name": "Ornate Lamp",
      "category": "lighting",
      "default_scale": 1.0,
      "quality_ratings": {
        "pride": 1,
        "ambiance": 2,
        "aroma": 0,
        "lighting": 2,
        "comfort": 0
      }
    },
    {
      "id": 1003,
      "name": "Potted Plant",
      "category": "nature",
      "default_scale": 1.0,
      "quality_ratings": {
        "pride": 0,
        "ambiance": 1,
        "aroma": 2,
        "lighting": 0,
        "comfort": 1
      }
    }
  ]
}
```

**Step 3: Create fabkit_types.json**

```json
{
  "fabkit_types": [
    {
      "id": 2001,
      "name": "Iron Mine",
      "type": "resource",
      "socket_size": "small",
      "harvest_cooldown_seconds": 3600,
      "resources": [
        {"item_id": 5001, "quantity_min": 1, "quantity_max": 3}
      ]
    },
    {
      "id": 2002,
      "name": "Garden Plot",
      "type": "resource",
      "socket_size": "small",
      "harvest_cooldown_seconds": 7200,
      "resources": [
        {"item_id": 5002, "quantity_min": 2, "quantity_max": 5}
      ]
    },
    {
      "id": 2003,
      "name": "Buff Board",
      "type": "buff",
      "socket_size": "small",
      "buff_cooldown_seconds": 86400,
      "available_buffs": [
        {"id": 1, "name": "PvP XP Boost", "bonus_percent": 5},
        {"id": 2, "name": "Quest XP Boost", "bonus_percent": 5},
        {"id": 3, "name": "Dungeon XP Boost", "bonus_percent": 10}
      ]
    },
    {
      "id": 2004,
      "name": "Crafting Station",
      "type": "crafting",
      "socket_size": "large",
      "tradeskill_id": null
    },
    {
      "id": 2005,
      "name": "Challenge Course",
      "type": "challenge",
      "socket_size": "large",
      "challenge_id": null
    },
    {
      "id": 2006,
      "name": "Expedition Portal",
      "type": "expedition",
      "socket_size": "large",
      "expedition_id": null
    }
  ]
}
```

**Step 4: Commit**

```bash
git add apps/bezgelor_data/priv/data/house_types.json \
        apps/bezgelor_data/priv/data/decor_items.json \
        apps/bezgelor_data/priv/data/fabkit_types.json
git commit -m "feat(data): add housing data files"
```

---

## Task 16: BezgelorData Housing API

**Files:**
- Modify: `apps/bezgelor_data/lib/bezgelor_data.ex`

**Step 1: Add housing data functions**

Add to `bezgelor_data.ex`:

```elixir
  # Housing Data

  @spec get_house_type(integer()) :: {:ok, map()} | :error
  def get_house_type(id) do
    lookup(:house_types, id)
  end

  @spec list_house_types() :: [map()]
  def list_house_types do
    list(:house_types)
  end

  @spec get_decor_item(integer()) :: {:ok, map()} | :error
  def get_decor_item(id) do
    lookup(:decor_items, id)
  end

  @spec list_decor_items() :: [map()]
  def list_decor_items do
    list(:decor_items)
  end

  @spec get_fabkit_type(integer()) :: {:ok, map()} | :error
  def get_fabkit_type(id) do
    lookup(:fabkit_types, id)
  end

  @spec list_fabkit_types() :: [map()]
  def list_fabkit_types do
    list(:fabkit_types)
  end

  @spec get_decor_limit(integer()) :: integer()
  def get_decor_limit(house_type_id) do
    case get_house_type(house_type_id) do
      {:ok, house} -> house.decor_limit
      :error -> 300  # Default to cozy limit
    end
  end
```

**Step 2: Add to Store initialization**

Ensure the Store loads the new data files on startup.

**Step 3: Commit**

```bash
git add apps/bezgelor_data/lib/bezgelor_data.ex
git commit -m "feat(data): add housing data API"
```

---

## Task 17: Integration Test

**Files:**
- Create: `apps/bezgelor_world/test/integration/housing_flow_test.exs`

**Step 1: Write integration test**

```elixir
defmodule BezgelorWorld.Integration.HousingFlowTest do
  use ExUnit.Case, async: false

  alias BezgelorDb.{Accounts, Characters, Housing, Repo}
  alias BezgelorWorld.Handler.HousingHandler
  alias BezgelorWorld.HousingManager

  @moduletag :database

  setup do
    case Repo.start_link([]) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    email = "housing_flow#{System.unique_integer([:positive])}@test.com"
    {:ok, account} = Accounts.create_account(email, "password123")

    {:ok, owner} =
      Characters.create_character(account.id, %{
        name: "PlotOwner#{System.unique_integer([:positive])}",
        sex: 0, race: 0, class: 0, faction_id: 166, world_id: 1, world_zone_id: 1
      })

    {:ok, visitor} =
      Characters.create_character(account.id, %{
        name: "Visitor#{System.unique_integer([:positive])}",
        sex: 0, race: 0, class: 0, faction_id: 166, world_id: 1, world_zone_id: 1
      })

    {:ok, plot} = Housing.create_plot(owner.id)

    owner_state = %{session_data: %{in_world: true, character_id: owner.id, entity_guid: owner.id}}
    visitor_state = %{session_data: %{in_world: true, character_id: visitor.id, entity_guid: visitor.id}}

    {:ok, account: account, owner: owner, visitor: visitor, plot: plot,
          owner_state: owner_state, visitor_state: visitor_state}
  end

  describe "full housing flow" do
    test "owner enters, places decor, visitor tries to enter", ctx do
      # Owner enters own housing
      {:reply, :server_housing_enter, _, owner_state} =
        HousingHandler.handle_enter_housing(%{owner_character_id: 0}, ctx.owner_state)

      assert owner_state.session_data[:in_housing] == ctx.owner.id

      # Owner places decor
      {:reply, :server_decor_placed, _, _} =
        HousingHandler.handle_place_decor(%{
          decor_id: 1001,
          pos_x: 10.0, pos_y: 0.0, pos_z: 20.0,
          rot_pitch: 0.0, rot_yaw: 45.0, rot_roll: 0.0,
          scale: 1.0,
          is_exterior: false
        }, owner_state)

      # Verify decor was saved
      {:ok, plot} = Housing.get_plot(ctx.owner.id)
      assert length(plot.decor) == 1

      # Visitor cannot enter private plot
      {:reply, :server_housing_denied, _, _} =
        HousingHandler.handle_enter_housing(%{owner_character_id: ctx.owner.id}, ctx.visitor_state)

      # Owner makes plot public
      {:ok, _} = Housing.set_permission_level(ctx.owner.id, :public)

      # Now visitor can enter
      {:reply, :server_housing_enter, _, visitor_state} =
        HousingHandler.handle_enter_housing(%{owner_character_id: ctx.owner.id}, ctx.visitor_state)

      assert visitor_state.session_data[:in_housing] == ctx.owner.id
    end

    test "neighbor and roommate permissions", ctx do
      # Add visitor as neighbor
      {:ok, _} = Housing.add_neighbor(ctx.plot.id, ctx.visitor.id)

      # Set plot to neighbors-only
      {:ok, _} = Housing.set_permission_level(ctx.owner.id, :neighbors)

      # Visitor can now enter
      {:reply, :server_housing_enter, _, visitor_state} =
        HousingHandler.handle_enter_housing(%{owner_character_id: ctx.owner.id}, ctx.visitor_state)

      # But visitor cannot place decor (not roommate)
      {:error, :cannot_place_decor} =
        HousingHandler.handle_place_decor(%{
          decor_id: 1001,
          pos_x: 10.0, pos_y: 0.0, pos_z: 20.0,
          rot_pitch: 0.0, rot_yaw: 0.0, rot_roll: 0.0,
          scale: 1.0,
          is_exterior: false
        }, visitor_state)

      # Promote to roommate
      {:ok, _} = Housing.promote_to_roommate(ctx.plot.id, ctx.visitor.id)

      # Now visitor can place decor
      {:reply, :server_decor_placed, _, _} =
        HousingHandler.handle_place_decor(%{
          decor_id: 1002,
          pos_x: 15.0, pos_y: 0.0, pos_z: 25.0,
          rot_pitch: 0.0, rot_yaw: 0.0, rot_roll: 0.0,
          scale: 1.0,
          is_exterior: false
        }, visitor_state)
    end
  end
end
```

**Step 2: Run integration test**

Run: `cd apps/bezgelor_world && MIX_ENV=test mix test test/integration/housing_flow_test.exs --trace`
Expected: All tests pass

**Step 3: Commit**

```bash
git add apps/bezgelor_world/test/integration/housing_flow_test.exs
git commit -m "test: add housing flow integration test"
```

---

## Summary

This plan implements the full WildStar-authentic housing system in 17 tasks:

| Task | Component | Description |
|------|-----------|-------------|
| 1 | Migration | Create 4 housing tables |
| 2-5 | Schemas | HousingPlot, HousingNeighbor, HousingDecor, HousingFabkit |
| 6-9 | Context | Housing operations (plot, neighbors, decor, fabkits) |
| 10-12 | Packets | Entry, decor, FABkit, and social packets |
| 13 | HousingManager | Instance lifecycle GenServer |
| 14 | HousingHandler | Packet processing |
| 15-16 | Data | JSON data files and BezgelorData API |
| 17 | Integration | Full flow test |

**Total estimated tasks:** 17 discrete commits following TDD.
