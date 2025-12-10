# Mounts, Pets & Storefront Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement collection systems for mounts/pets with summoning, customization, pet auto-combat, and a full storefront with premium currency, gifting, and promo codes.

**Architecture:** Hybrid data model - static definitions in BezgelorData JSON, player ownership and storefront catalog in database. Account-level premium currency, character-level gold. Pet auto-combat integrates with existing CombatHandler.

**Tech Stack:** Elixir, Ecto, Phoenix PubSub (for pet combat events), ExUnit

---

## Task 1: Account Currency Schema

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/schema/account_currency.ex`
- Create: `apps/bezgelor_db/priv/repo/migrations/TIMESTAMP_create_account_currencies.exs`

**Step 1: Write the migration**

```elixir
defmodule BezgelorDb.Repo.Migrations.CreateAccountCurrencies do
  use Ecto.Migration

  def change do
    create table(:account_currencies) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :premium_currency, :integer, default: 0
      add :bonus_currency, :integer, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:account_currencies, [:account_id])
  end
end
```

**Step 2: Write the schema**

```elixir
defmodule BezgelorDb.Schema.AccountCurrency do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "account_currencies" do
    belongs_to :account, BezgelorDb.Schema.Account

    field :premium_currency, :integer, default: 0
    field :bonus_currency, :integer, default: 0

    timestamps(type: :utc_datetime)
  end

  def changeset(currency, attrs) do
    currency
    |> cast(attrs, [:account_id, :premium_currency, :bonus_currency])
    |> validate_required([:account_id])
    |> validate_number(:premium_currency, greater_than_or_equal_to: 0)
    |> validate_number(:bonus_currency, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:account_id)
    |> unique_constraint(:account_id)
  end

  def add_premium_changeset(currency, amount) do
    new_amount = currency.premium_currency + amount
    change(currency, premium_currency: new_amount)
  end

  def deduct_premium_changeset(currency, amount) do
    new_amount = currency.premium_currency - amount
    if new_amount >= 0 do
      {:ok, change(currency, premium_currency: new_amount)}
    else
      {:error, :insufficient_funds}
    end
  end
end
```

**Step 3: Run migration**

Run: `MIX_ENV=test mix ecto.migrate`
Expected: Migration succeeds

**Step 4: Commit**

```bash
git add apps/bezgelor_db/lib/bezgelor_db/schema/account_currency.ex apps/bezgelor_db/priv/repo/migrations/*_create_account_currencies.exs
git commit -m "feat(db): Add AccountCurrency schema for premium currency"
```

---

## Task 2: Collection Schemas

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/schema/account_collection.ex`
- Create: `apps/bezgelor_db/lib/bezgelor_db/schema/character_collection.ex`
- Create: `apps/bezgelor_db/priv/repo/migrations/TIMESTAMP_create_collections.exs`

**Step 1: Write the migration**

```elixir
defmodule BezgelorDb.Repo.Migrations.CreateCollections do
  use Ecto.Migration

  def change do
    create table(:account_collections) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :collectible_type, :string, null: false  # "mount" or "pet"
      add :collectible_id, :integer, null: false
      add :unlock_source, :string  # purchase, achievement, promo, gift

      timestamps(type: :utc_datetime)
    end

    create unique_index(:account_collections, [:account_id, :collectible_type, :collectible_id])
    create index(:account_collections, [:account_id, :collectible_type])

    create table(:character_collections) do
      add :character_id, references(:characters, on_delete: :delete_all), null: false
      add :collectible_type, :string, null: false
      add :collectible_id, :integer, null: false
      add :unlock_source, :string  # quest, drop, event

      timestamps(type: :utc_datetime)
    end

    create unique_index(:character_collections, [:character_id, :collectible_type, :collectible_id])
    create index(:character_collections, [:character_id, :collectible_type])
  end
end
```

**Step 2: Write AccountCollection schema**

```elixir
defmodule BezgelorDb.Schema.AccountCollection do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "account_collections" do
    belongs_to :account, BezgelorDb.Schema.Account

    field :collectible_type, :string  # "mount" or "pet"
    field :collectible_id, :integer
    field :unlock_source, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(collection, attrs) do
    collection
    |> cast(attrs, [:account_id, :collectible_type, :collectible_id, :unlock_source])
    |> validate_required([:account_id, :collectible_type, :collectible_id])
    |> validate_inclusion(:collectible_type, ["mount", "pet"])
    |> foreign_key_constraint(:account_id)
    |> unique_constraint([:account_id, :collectible_type, :collectible_id])
  end
end
```

**Step 3: Write CharacterCollection schema**

```elixir
defmodule BezgelorDb.Schema.CharacterCollection do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "character_collections" do
    belongs_to :character, BezgelorDb.Schema.Character

    field :collectible_type, :string
    field :collectible_id, :integer
    field :unlock_source, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(collection, attrs) do
    collection
    |> cast(attrs, [:character_id, :collectible_type, :collectible_id, :unlock_source])
    |> validate_required([:character_id, :collectible_type, :collectible_id])
    |> validate_inclusion(:collectible_type, ["mount", "pet"])
    |> foreign_key_constraint(:character_id)
    |> unique_constraint([:character_id, :collectible_type, :collectible_id])
  end
end
```

**Step 4: Run migration**

Run: `MIX_ENV=test mix ecto.migrate`
Expected: Migration succeeds

**Step 5: Commit**

```bash
git add apps/bezgelor_db/lib/bezgelor_db/schema/account_collection.ex apps/bezgelor_db/lib/bezgelor_db/schema/character_collection.ex apps/bezgelor_db/priv/repo/migrations/*_create_collections.exs
git commit -m "feat(db): Add collection schemas for mounts/pets"
```

---

## Task 3: Active Mount & Pet Schemas

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/schema/active_mount.ex`
- Create: `apps/bezgelor_db/lib/bezgelor_db/schema/active_pet.ex`
- Create: `apps/bezgelor_db/priv/repo/migrations/TIMESTAMP_create_active_mounts_pets.exs`

**Step 1: Write the migration**

```elixir
defmodule BezgelorDb.Repo.Migrations.CreateActiveMountsPets do
  use Ecto.Migration

  def change do
    create table(:active_mounts) do
      add :character_id, references(:characters, on_delete: :delete_all), null: false
      add :mount_id, :integer, null: false
      add :customization, :map, default: %{}  # dyes, flair, upgrades

      timestamps(type: :utc_datetime)
    end

    create unique_index(:active_mounts, [:character_id])

    create table(:active_pets) do
      add :character_id, references(:characters, on_delete: :delete_all), null: false
      add :pet_id, :integer, null: false
      add :level, :integer, default: 1
      add :xp, :integer, default: 0
      add :nickname, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:active_pets, [:character_id])
  end
end
```

**Step 2: Write ActiveMount schema**

```elixir
defmodule BezgelorDb.Schema.ActiveMount do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "active_mounts" do
    belongs_to :character, BezgelorDb.Schema.Character

    field :mount_id, :integer
    field :customization, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  def changeset(mount, attrs) do
    mount
    |> cast(attrs, [:character_id, :mount_id, :customization])
    |> validate_required([:character_id, :mount_id])
    |> foreign_key_constraint(:character_id)
    |> unique_constraint(:character_id)
  end

  def customization_changeset(mount, customization) do
    mount
    |> change(customization: customization)
  end
end
```

**Step 3: Write ActivePet schema**

```elixir
defmodule BezgelorDb.Schema.ActivePet do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @max_level 25

  schema "active_pets" do
    belongs_to :character, BezgelorDb.Schema.Character

    field :pet_id, :integer
    field :level, :integer, default: 1
    field :xp, :integer, default: 0
    field :nickname, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(pet, attrs) do
    pet
    |> cast(attrs, [:character_id, :pet_id, :level, :xp, :nickname])
    |> validate_required([:character_id, :pet_id])
    |> validate_number(:level, greater_than_or_equal_to: 1, less_than_or_equal_to: @max_level)
    |> validate_number(:xp, greater_than_or_equal_to: 0)
    |> validate_length(:nickname, max: 20)
    |> foreign_key_constraint(:character_id)
    |> unique_constraint(:character_id)
  end

  def xp_changeset(pet, xp, level) do
    pet
    |> cast(%{xp: xp, level: level}, [:xp, :level])
  end

  def nickname_changeset(pet, nickname) do
    pet
    |> cast(%{nickname: nickname}, [:nickname])
    |> validate_length(:nickname, max: 20)
  end

  def max_level, do: @max_level
end
```

**Step 4: Run migration**

Run: `MIX_ENV=test mix ecto.migrate`
Expected: Migration succeeds

**Step 5: Commit**

```bash
git add apps/bezgelor_db/lib/bezgelor_db/schema/active_mount.ex apps/bezgelor_db/lib/bezgelor_db/schema/active_pet.ex apps/bezgelor_db/priv/repo/migrations/*_create_active_mounts_pets.exs
git commit -m "feat(db): Add ActiveMount and ActivePet schemas"
```

---

## Task 4: Collections Context

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/collections.ex`
- Create: `apps/bezgelor_db/test/collections_test.exs`

**Step 1: Write failing tests**

```elixir
defmodule BezgelorDb.CollectionsTest do
  use ExUnit.Case

  alias BezgelorDb.{Accounts, Characters, Collections, Repo}

  @moduletag :database

  setup do
    case Repo.start_link([]) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    email = "collection_test#{System.unique_integer([:positive])}@test.com"
    {:ok, account} = Accounts.create_account(email, "password123")

    {:ok, character} =
      Characters.create_character(account.id, %{
        name: "Collector#{System.unique_integer([:positive])}",
        sex: 0, race: 0, class: 0, faction_id: 166, world_id: 1, world_zone_id: 1
      })

    {:ok, account: account, character: character}
  end

  describe "account collections" do
    test "unlock_account_mount adds mount", %{account: account} do
      {:ok, collection} = Collections.unlock_account_mount(account.id, 1001, "purchase")
      assert collection.collectible_id == 1001
    end

    test "get_account_mounts returns mounts", %{account: account} do
      {:ok, _} = Collections.unlock_account_mount(account.id, 1001, "purchase")
      {:ok, _} = Collections.unlock_account_mount(account.id, 1002, "achievement")

      mounts = Collections.get_account_mounts(account.id)
      assert length(mounts) == 2
    end

    test "owns_mount? checks ownership", %{account: account, character: character} do
      refute Collections.owns_mount?(account.id, character.id, 1001)

      {:ok, _} = Collections.unlock_account_mount(account.id, 1001, "purchase")

      assert Collections.owns_mount?(account.id, character.id, 1001)
    end
  end

  describe "character collections" do
    test "unlock_character_mount adds mount", %{character: character} do
      {:ok, collection} = Collections.unlock_character_mount(character.id, 2001, "quest")
      assert collection.collectible_id == 2001
    end

    test "get_all_mounts merges account and character", %{account: account, character: character} do
      {:ok, _} = Collections.unlock_account_mount(account.id, 1001, "purchase")
      {:ok, _} = Collections.unlock_character_mount(character.id, 2001, "quest")

      mounts = Collections.get_all_mounts(account.id, character.id)
      assert length(mounts) == 2
    end
  end

  describe "pets" do
    test "unlock_account_pet adds pet", %{account: account} do
      {:ok, collection} = Collections.unlock_account_pet(account.id, 3001, "purchase")
      assert collection.collectible_id == 3001
    end

    test "owns_pet? checks ownership", %{account: account, character: character} do
      refute Collections.owns_pet?(account.id, character.id, 3001)

      {:ok, _} = Collections.unlock_character_pet(character.id, 3001, "drop")

      assert Collections.owns_pet?(account.id, character.id, 3001)
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `MIX_ENV=test mix test apps/bezgelor_db/test/collections_test.exs --include database`
Expected: FAIL - module Collections not found

**Step 3: Write Collections context**

```elixir
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
```

**Step 4: Run tests to verify they pass**

Run: `MIX_ENV=test mix test apps/bezgelor_db/test/collections_test.exs --include database`
Expected: All tests pass

**Step 5: Commit**

```bash
git add apps/bezgelor_db/lib/bezgelor_db/collections.ex apps/bezgelor_db/test/collections_test.exs
git commit -m "feat(db): Add Collections context for mounts/pets"
```

---

## Task 5: Mounts Context

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/mounts.ex`
- Create: `apps/bezgelor_db/test/mounts_test.exs`

**Step 1: Write failing tests**

```elixir
defmodule BezgelorDb.MountsTest do
  use ExUnit.Case

  alias BezgelorDb.{Accounts, Characters, Collections, Mounts, Repo}

  @moduletag :database

  setup do
    case Repo.start_link([]) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    email = "mount_test#{System.unique_integer([:positive])}@test.com"
    {:ok, account} = Accounts.create_account(email, "password123")

    {:ok, character} =
      Characters.create_character(account.id, %{
        name: "Rider#{System.unique_integer([:positive])}",
        sex: 0, race: 0, class: 0, faction_id: 166, world_id: 1, world_zone_id: 1
      })

    # Unlock a mount for tests
    {:ok, _} = Collections.unlock_account_mount(account.id, 1001, "purchase")

    {:ok, account: account, character: character}
  end

  describe "active mount" do
    test "set_active_mount activates mount", %{account: account, character: character} do
      {:ok, mount} = Mounts.set_active_mount(character.id, account.id, 1001)
      assert mount.mount_id == 1001
    end

    test "get_active_mount returns current mount", %{account: account, character: character} do
      {:ok, _} = Mounts.set_active_mount(character.id, account.id, 1001)
      mount = Mounts.get_active_mount(character.id)
      assert mount.mount_id == 1001
    end

    test "set_active_mount fails if not owned", %{account: account, character: character} do
      {:error, :not_owned} = Mounts.set_active_mount(character.id, account.id, 9999)
    end

    test "clear_active_mount removes mount", %{account: account, character: character} do
      {:ok, _} = Mounts.set_active_mount(character.id, account.id, 1001)
      :ok = Mounts.clear_active_mount(character.id)
      assert Mounts.get_active_mount(character.id) == nil
    end
  end

  describe "customization" do
    test "update_customization changes mount look", %{account: account, character: character} do
      {:ok, _} = Mounts.set_active_mount(character.id, account.id, 1001)
      {:ok, mount} = Mounts.update_customization(character.id, %{
        "dyes" => [1, 2, 3],
        "flair" => ["flag_01"]
      })

      assert mount.customization["dyes"] == [1, 2, 3]
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `MIX_ENV=test mix test apps/bezgelor_db/test/mounts_test.exs --include database`
Expected: FAIL - module Mounts not found

**Step 3: Write Mounts context**

```elixir
defmodule BezgelorDb.Mounts do
  @moduledoc """
  Active mount management with customization.
  """

  import Ecto.Query
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
      nil -> :ok
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
```

**Step 4: Run tests to verify they pass**

Run: `MIX_ENV=test mix test apps/bezgelor_db/test/mounts_test.exs --include database`
Expected: All tests pass

**Step 5: Commit**

```bash
git add apps/bezgelor_db/lib/bezgelor_db/mounts.ex apps/bezgelor_db/test/mounts_test.exs
git commit -m "feat(db): Add Mounts context with customization"
```

---

## Task 6: Pets Context

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/pets.ex`
- Create: `apps/bezgelor_db/test/pets_test.exs`

**Step 1: Write failing tests**

```elixir
defmodule BezgelorDb.PetsTest do
  use ExUnit.Case

  alias BezgelorDb.{Accounts, Characters, Collections, Pets, Repo}

  @moduletag :database

  setup do
    case Repo.start_link([]) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    email = "pet_test#{System.unique_integer([:positive])}@test.com"
    {:ok, account} = Accounts.create_account(email, "password123")

    {:ok, character} =
      Characters.create_character(account.id, %{
        name: "PetOwner#{System.unique_integer([:positive])}",
        sex: 0, race: 0, class: 0, faction_id: 166, world_id: 1, world_zone_id: 1
      })

    {:ok, _} = Collections.unlock_account_pet(account.id, 2001, "purchase")

    {:ok, account: account, character: character}
  end

  describe "active pet" do
    test "set_active_pet summons pet", %{account: account, character: character} do
      {:ok, pet} = Pets.set_active_pet(character.id, account.id, 2001)
      assert pet.pet_id == 2001
      assert pet.level == 1
    end

    test "get_active_pet returns current pet", %{account: account, character: character} do
      {:ok, _} = Pets.set_active_pet(character.id, account.id, 2001)
      pet = Pets.get_active_pet(character.id)
      assert pet.pet_id == 2001
    end

    test "clear_active_pet dismisses pet", %{account: account, character: character} do
      {:ok, _} = Pets.set_active_pet(character.id, account.id, 2001)
      :ok = Pets.clear_active_pet(character.id)
      assert Pets.get_active_pet(character.id) == nil
    end
  end

  describe "pet progression" do
    test "award_pet_xp increases XP", %{account: account, character: character} do
      {:ok, _} = Pets.set_active_pet(character.id, account.id, 2001)
      {:ok, pet, :xp_gained} = Pets.award_pet_xp(character.id, 50)
      assert pet.xp == 50
    end

    test "award_pet_xp triggers level up", %{account: account, character: character} do
      {:ok, _} = Pets.set_active_pet(character.id, account.id, 2001)
      # Default level curve: 100 XP for level 2
      {:ok, pet, :level_up} = Pets.award_pet_xp(character.id, 150)
      assert pet.level == 2
      assert pet.xp == 50  # Leftover after level up
    end

    test "set_nickname changes pet name", %{account: account, character: character} do
      {:ok, _} = Pets.set_active_pet(character.id, account.id, 2001)
      {:ok, pet} = Pets.set_nickname(character.id, "Fluffy")
      assert pet.nickname == "Fluffy"
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `MIX_ENV=test mix test apps/bezgelor_db/test/pets_test.exs --include database`
Expected: FAIL - module Pets not found

**Step 3: Write Pets context**

```elixir
defmodule BezgelorDb.Pets do
  @moduledoc """
  Active pet management with leveling and XP.
  """

  alias BezgelorDb.Repo
  alias BezgelorDb.Schema.ActivePet
  alias BezgelorDb.Collections

  # Default XP curve - XP needed to reach each level
  @default_level_curve [0, 100, 250, 500, 800, 1200, 1700, 2300, 3000, 3800,
                        4700, 5700, 6800, 8000, 9300, 10700, 12200, 13800, 15500, 17300,
                        19200, 21200, 23300, 25500, 27800]

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

  @spec award_pet_xp(integer(), integer(), list() | nil) ::
          {:ok, ActivePet.t(), :xp_gained | :level_up} | {:error, :no_active_pet}
  def award_pet_xp(character_id, amount, level_curve \\ nil) do
    curve = level_curve || @default_level_curve

    case get_active_pet(character_id) do
      nil ->
        {:error, :no_active_pet}

      pet ->
        new_xp = pet.xp + amount
        {new_level, remaining_xp} = calculate_level(pet.level, new_xp, curve)
        result_type = if new_level > pet.level, do: :level_up, else: :xp_gained

        {:ok, updated} =
          pet
          |> ActivePet.xp_changeset(remaining_xp, new_level)
          |> Repo.update()

        {:ok, updated, result_type}
    end
  end

  @spec set_nickname(integer(), String.t()) ::
          {:ok, ActivePet.t()} | {:error, :no_active_pet}
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

  defp calculate_level(current_level, xp, curve) when current_level >= length(curve) - 1 do
    {current_level, xp}
  end

  defp calculate_level(current_level, xp, curve) do
    xp_for_next = Enum.at(curve, current_level)

    if xp >= xp_for_next do
      calculate_level(current_level + 1, xp - xp_for_next, curve)
    else
      {current_level, xp}
    end
  end
end
```

**Step 4: Run tests to verify they pass**

Run: `MIX_ENV=test mix test apps/bezgelor_db/test/pets_test.exs --include database`
Expected: All tests pass

**Step 5: Commit**

```bash
git add apps/bezgelor_db/lib/bezgelor_db/pets.ex apps/bezgelor_db/test/pets_test.exs
git commit -m "feat(db): Add Pets context with XP and leveling"
```

---

## Task 7: Storefront Schemas

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/schema/store_category.ex`
- Create: `apps/bezgelor_db/lib/bezgelor_db/schema/store_item.ex`
- Create: `apps/bezgelor_db/lib/bezgelor_db/schema/store_promotion.ex`
- Create: `apps/bezgelor_db/lib/bezgelor_db/schema/promo_code.ex`
- Create: `apps/bezgelor_db/lib/bezgelor_db/schema/purchase_history.ex`
- Create: `apps/bezgelor_db/priv/repo/migrations/TIMESTAMP_create_storefront.exs`

**Step 1: Write the migration**

```elixir
defmodule BezgelorDb.Repo.Migrations.CreateStorefront do
  use Ecto.Migration

  def change do
    create table(:store_categories) do
      add :name, :string, null: false
      add :sort_order, :integer, default: 0
      add :parent_id, references(:store_categories, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:store_categories, [:parent_id])

    create table(:store_items) do
      add :category_id, references(:store_categories, on_delete: :nilify_all)
      add :name, :string, null: false
      add :description, :text
      add :item_type, :string, null: false  # mount, pet, costume, bundle, currency_pack
      add :reference_id, :integer  # mount_id, pet_id, etc.
      add :price_gold, :integer, default: 0
      add :price_premium, :integer, default: 0
      add :account_wide, :boolean, default: false
      add :giftable, :boolean, default: true
      add :available, :boolean, default: true
      add :featured, :boolean, default: false

      timestamps(type: :utc_datetime)
    end

    create index(:store_items, [:category_id])
    create index(:store_items, [:item_type])
    create index(:store_items, [:available])
    create index(:store_items, [:featured])

    create table(:store_promotions) do
      add :name, :string, null: false
      add :discount_percent, :integer, null: false
      add :starts_at, :utc_datetime, null: false
      add :ends_at, :utc_datetime, null: false
      add :applies_to_type, :string  # category, item, all
      add :applies_to_id, :integer

      timestamps(type: :utc_datetime)
    end

    create index(:store_promotions, [:starts_at, :ends_at])

    create table(:daily_deals) do
      add :store_item_id, references(:store_items, on_delete: :delete_all), null: false
      add :discount_percent, :integer, null: false
      add :deal_date, :date, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:daily_deals, [:deal_date])

    create table(:promo_codes) do
      add :code, :string, null: false
      add :code_type, :string, null: false  # single_use, multi_use, per_account
      add :max_uses, :integer
      add :current_uses, :integer, default: 0
      add :rewards, :map, default: []  # [{type, id, quantity}]
      add :expires_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:promo_codes, [:code])

    create table(:promo_redemptions) do
      add :code_id, references(:promo_codes, on_delete: :delete_all), null: false
      add :account_id, references(:accounts, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:promo_redemptions, [:code_id, :account_id])

    create table(:purchase_history) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :character_id, references(:characters, on_delete: :nilify_all)
      add :store_item_id, references(:store_items, on_delete: :nilify_all)
      add :currency_type, :string, null: false  # gold, premium
      add :amount_paid, :integer, null: false
      add :discount_applied, :integer, default: 0
      add :is_gift, :boolean, default: false
      add :gift_recipient_id, :integer

      timestamps(type: :utc_datetime)
    end

    create index(:purchase_history, [:account_id])
    create index(:purchase_history, [:character_id])
  end
end
```

**Step 2: Write StoreCategory schema**

```elixir
defmodule BezgelorDb.Schema.StoreCategory do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "store_categories" do
    field :name, :string
    field :sort_order, :integer, default: 0

    belongs_to :parent, __MODULE__
    has_many :children, __MODULE__, foreign_key: :parent_id
    has_many :items, BezgelorDb.Schema.StoreItem, foreign_key: :category_id

    timestamps(type: :utc_datetime)
  end

  def changeset(category, attrs) do
    category
    |> cast(attrs, [:name, :sort_order, :parent_id])
    |> validate_required([:name])
    |> foreign_key_constraint(:parent_id)
  end
end
```

**Step 3: Write StoreItem schema**

```elixir
defmodule BezgelorDb.Schema.StoreItem do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @item_types ~w(mount pet costume bundle currency_pack)

  schema "store_items" do
    belongs_to :category, BezgelorDb.Schema.StoreCategory

    field :name, :string
    field :description, :string
    field :item_type, :string
    field :reference_id, :integer
    field :price_gold, :integer, default: 0
    field :price_premium, :integer, default: 0
    field :account_wide, :boolean, default: false
    field :giftable, :boolean, default: true
    field :available, :boolean, default: true
    field :featured, :boolean, default: false

    timestamps(type: :utc_datetime)
  end

  def changeset(item, attrs) do
    item
    |> cast(attrs, [:category_id, :name, :description, :item_type, :reference_id,
                    :price_gold, :price_premium, :account_wide, :giftable, :available, :featured])
    |> validate_required([:name, :item_type])
    |> validate_inclusion(:item_type, @item_types)
    |> validate_number(:price_gold, greater_than_or_equal_to: 0)
    |> validate_number(:price_premium, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:category_id)
  end
end
```

**Step 4: Write PromoCode schema**

```elixir
defmodule BezgelorDb.Schema.PromoCode do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @code_types ~w(single_use multi_use per_account)

  schema "promo_codes" do
    field :code, :string
    field :code_type, :string
    field :max_uses, :integer
    field :current_uses, :integer, default: 0
    field :rewards, {:array, :map}, default: []
    field :expires_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(promo, attrs) do
    promo
    |> cast(attrs, [:code, :code_type, :max_uses, :current_uses, :rewards, :expires_at])
    |> validate_required([:code, :code_type])
    |> validate_inclusion(:code_type, @code_types)
    |> unique_constraint(:code)
  end

  def increment_uses_changeset(promo) do
    change(promo, current_uses: promo.current_uses + 1)
  end
end
```

**Step 5: Write PurchaseHistory schema**

```elixir
defmodule BezgelorDb.Schema.PurchaseHistory do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "purchase_history" do
    belongs_to :account, BezgelorDb.Schema.Account
    belongs_to :character, BezgelorDb.Schema.Character
    belongs_to :store_item, BezgelorDb.Schema.StoreItem

    field :currency_type, :string
    field :amount_paid, :integer
    field :discount_applied, :integer, default: 0
    field :is_gift, :boolean, default: false
    field :gift_recipient_id, :integer

    timestamps(type: :utc_datetime)
  end

  def changeset(history, attrs) do
    history
    |> cast(attrs, [:account_id, :character_id, :store_item_id, :currency_type,
                    :amount_paid, :discount_applied, :is_gift, :gift_recipient_id])
    |> validate_required([:account_id, :currency_type, :amount_paid])
    |> validate_inclusion(:currency_type, ["gold", "premium"])
    |> foreign_key_constraint(:account_id)
    |> foreign_key_constraint(:character_id)
    |> foreign_key_constraint(:store_item_id)
  end
end
```

**Step 6: Run migration**

Run: `MIX_ENV=test mix ecto.migrate`
Expected: Migration succeeds

**Step 7: Commit**

```bash
git add apps/bezgelor_db/lib/bezgelor_db/schema/store_*.ex apps/bezgelor_db/lib/bezgelor_db/schema/promo_code.ex apps/bezgelor_db/lib/bezgelor_db/schema/purchase_history.ex apps/bezgelor_db/priv/repo/migrations/*_create_storefront.exs
git commit -m "feat(db): Add storefront schemas"
```

---

## Task 8: Storefront Context

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/storefront.ex`
- Create: `apps/bezgelor_db/test/storefront_test.exs`

**Step 1: Write failing tests**

```elixir
defmodule BezgelorDb.StorefrontTest do
  use ExUnit.Case

  alias BezgelorDb.{Accounts, Characters, Storefront, Repo}
  alias BezgelorDb.Schema.{StoreCategory, StoreItem, PromoCode}

  @moduletag :database

  setup do
    case Repo.start_link([]) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    email = "store_test#{System.unique_integer([:positive])}@test.com"
    {:ok, account} = Accounts.create_account(email, "password123")

    {:ok, character} =
      Characters.create_character(account.id, %{
        name: "Shopper#{System.unique_integer([:positive])}",
        sex: 0, race: 0, class: 0, faction_id: 166, world_id: 1, world_zone_id: 1
      })

    # Create test category and item
    {:ok, category} = Repo.insert(%StoreCategory{name: "Mounts"})
    {:ok, item} = Repo.insert(%StoreItem{
      category_id: category.id,
      name: "Test Mount",
      item_type: "mount",
      reference_id: 1001,
      price_premium: 500,
      account_wide: true
    })

    # Give account some currency
    {:ok, _} = Storefront.add_premium_currency(account.id, 1000, "test")

    {:ok, account: account, character: character, category: category, item: item}
  end

  describe "currency" do
    test "get_premium_balance returns balance", %{account: account} do
      balance = Storefront.get_premium_balance(account.id)
      assert balance == 1000
    end

    test "add_premium_currency increases balance", %{account: account} do
      {:ok, new_balance} = Storefront.add_premium_currency(account.id, 500, "bonus")
      assert new_balance == 1500
    end

    test "deduct_premium_currency decreases balance", %{account: account} do
      {:ok, new_balance} = Storefront.deduct_premium_currency(account.id, 300)
      assert new_balance == 700
    end

    test "deduct fails with insufficient funds", %{account: account} do
      {:error, :insufficient_funds} = Storefront.deduct_premium_currency(account.id, 2000)
    end
  end

  describe "purchasing" do
    test "purchase_item succeeds with premium", %{account: account, character: character, item: item} do
      {:ok, result} = Storefront.purchase_item(account.id, character.id, item.id, :premium)
      assert result.amount_paid == 500

      # Balance should be reduced
      assert Storefront.get_premium_balance(account.id) == 500
    end

    test "purchase_item fails without funds", %{account: account, character: character, item: item} do
      Storefront.deduct_premium_currency(account.id, 900)  # Leave only 100
      {:error, :insufficient_funds} = Storefront.purchase_item(account.id, character.id, item.id, :premium)
    end
  end

  describe "promo codes" do
    test "redeem_code grants rewards", %{account: account} do
      {:ok, code} = Repo.insert(%PromoCode{
        code: "TESTCODE",
        code_type: "per_account",
        rewards: [%{"type" => "currency", "amount" => 100}]
      })

      {:ok, rewards} = Storefront.redeem_code(account.id, "TESTCODE")
      assert length(rewards) == 1
    end

    test "redeem_code fails if already redeemed", %{account: account} do
      {:ok, _} = Repo.insert(%PromoCode{
        code: "ONCEONLY",
        code_type: "per_account",
        rewards: []
      })

      {:ok, _} = Storefront.redeem_code(account.id, "ONCEONLY")
      {:error, :already_redeemed} = Storefront.redeem_code(account.id, "ONCEONLY")
    end

    test "redeem_code fails if expired", %{account: account} do
      past = DateTime.add(DateTime.utc_now(), -86400, :second)
      {:ok, _} = Repo.insert(%PromoCode{
        code: "EXPIRED",
        code_type: "per_account",
        rewards: [],
        expires_at: past
      })

      {:error, :expired} = Storefront.redeem_code(account.id, "EXPIRED")
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `MIX_ENV=test mix test apps/bezgelor_db/test/storefront_test.exs --include database`
Expected: FAIL - module Storefront not found

**Step 3: Write Storefront context**

```elixir
defmodule BezgelorDb.Storefront do
  @moduledoc """
  Storefront management: catalog, purchases, promo codes.
  """

  import Ecto.Query
  alias BezgelorDb.Repo
  alias BezgelorDb.Schema.{
    AccountCurrency, StoreCategory, StoreItem,
    PromoCode, PurchaseHistory
  }
  alias BezgelorDb.Collections

  # Currency

  @spec get_premium_balance(integer()) :: integer()
  def get_premium_balance(account_id) do
    case get_or_create_currency(account_id) do
      {:ok, currency} -> currency.premium_currency
      _ -> 0
    end
  end

  @spec add_premium_currency(integer(), integer(), String.t()) ::
          {:ok, integer()} | {:error, term()}
  def add_premium_currency(account_id, amount, _source) do
    {:ok, currency} = get_or_create_currency(account_id)

    {:ok, updated} =
      currency
      |> AccountCurrency.add_premium_changeset(amount)
      |> Repo.update()

    {:ok, updated.premium_currency}
  end

  @spec deduct_premium_currency(integer(), integer()) ::
          {:ok, integer()} | {:error, :insufficient_funds}
  def deduct_premium_currency(account_id, amount) do
    {:ok, currency} = get_or_create_currency(account_id)

    case AccountCurrency.deduct_premium_changeset(currency, amount) do
      {:ok, changeset} ->
        {:ok, updated} = Repo.update(changeset)
        {:ok, updated.premium_currency}

      {:error, :insufficient_funds} ->
        {:error, :insufficient_funds}
    end
  end

  defp get_or_create_currency(account_id) do
    case Repo.get_by(AccountCurrency, account_id: account_id) do
      nil ->
        %AccountCurrency{}
        |> AccountCurrency.changeset(%{account_id: account_id})
        |> Repo.insert()

      currency ->
        {:ok, currency}
    end
  end

  # Catalog

  @spec get_categories() :: [StoreCategory.t()]
  def get_categories do
    StoreCategory
    |> where([c], is_nil(c.parent_id))
    |> order_by([c], c.sort_order)
    |> Repo.all()
  end

  @spec get_items(integer()) :: [StoreItem.t()]
  def get_items(category_id) do
    StoreItem
    |> where([i], i.category_id == ^category_id and i.available == true)
    |> Repo.all()
  end

  @spec get_featured_items() :: [StoreItem.t()]
  def get_featured_items do
    StoreItem
    |> where([i], i.featured == true and i.available == true)
    |> Repo.all()
  end

  # Purchasing

  @spec purchase_item(integer(), integer(), integer(), :gold | :premium) ::
          {:ok, PurchaseHistory.t()} | {:error, term()}
  def purchase_item(account_id, character_id, item_id, currency_type) do
    with {:ok, item} <- get_available_item(item_id),
         {:ok, price} <- get_price(item, currency_type),
         :ok <- check_balance(account_id, character_id, currency_type, price),
         {:ok, _} <- deduct_currency(account_id, character_id, currency_type, price),
         {:ok, _} <- grant_item(account_id, character_id, item) do
      # Record purchase
      %PurchaseHistory{}
      |> PurchaseHistory.changeset(%{
        account_id: account_id,
        character_id: character_id,
        store_item_id: item_id,
        currency_type: Atom.to_string(currency_type),
        amount_paid: price
      })
      |> Repo.insert()
    end
  end

  defp get_available_item(item_id) do
    case Repo.get(StoreItem, item_id) do
      nil -> {:error, :item_not_found}
      %{available: false} -> {:error, :item_not_available}
      item -> {:ok, item}
    end
  end

  defp get_price(item, :gold), do: {:ok, item.price_gold}
  defp get_price(item, :premium), do: {:ok, item.price_premium}

  defp check_balance(account_id, _char_id, :premium, price) do
    if get_premium_balance(account_id) >= price, do: :ok, else: {:error, :insufficient_funds}
  end

  defp check_balance(_account_id, _char_id, :gold, _price) do
    # TODO: Check character gold
    :ok
  end

  defp deduct_currency(account_id, _char_id, :premium, amount) do
    deduct_premium_currency(account_id, amount)
  end

  defp deduct_currency(_account_id, _char_id, :gold, _amount) do
    # TODO: Deduct character gold
    {:ok, 0}
  end

  defp grant_item(account_id, character_id, item) do
    case item.item_type do
      "mount" ->
        if item.account_wide do
          Collections.unlock_account_mount(account_id, item.reference_id, "purchase")
        else
          Collections.unlock_character_mount(character_id, item.reference_id, "purchase")
        end

      "pet" ->
        if item.account_wide do
          Collections.unlock_account_pet(account_id, item.reference_id, "purchase")
        else
          Collections.unlock_character_pet(character_id, item.reference_id, "purchase")
        end

      "currency_pack" ->
        add_premium_currency(account_id, item.reference_id, "purchase")

      _ ->
        {:ok, :granted}
    end
  end

  # Promo Codes

  @spec redeem_code(integer(), String.t()) ::
          {:ok, list()} | {:error, term()}
  def redeem_code(account_id, code_string) do
    with {:ok, code} <- find_valid_code(code_string),
         :ok <- check_code_usable(code, account_id),
         {:ok, _} <- record_redemption(code, account_id),
         rewards <- grant_rewards(account_id, code.rewards) do
      {:ok, rewards}
    end
  end

  defp find_valid_code(code_string) do
    case Repo.get_by(PromoCode, code: String.upcase(code_string)) do
      nil -> {:error, :invalid_code}
      code -> {:ok, code}
    end
  end

  defp check_code_usable(code, account_id) do
    now = DateTime.utc_now()

    cond do
      code.expires_at && DateTime.compare(code.expires_at, now) == :lt ->
        {:error, :expired}

      code.code_type == "single_use" && code.current_uses >= 1 ->
        {:error, :already_used}

      code.code_type == "multi_use" && code.max_uses && code.current_uses >= code.max_uses ->
        {:error, :max_uses_reached}

      code.code_type == "per_account" && already_redeemed?(code.id, account_id) ->
        {:error, :already_redeemed}

      true ->
        :ok
    end
  end

  defp already_redeemed?(code_id, account_id) do
    Repo.exists?(
      from r in "promo_redemptions",
      where: r.code_id == ^code_id and r.account_id == ^account_id
    )
  end

  defp record_redemption(code, account_id) do
    Repo.transaction(fn ->
      # Increment uses
      code
      |> PromoCode.increment_uses_changeset()
      |> Repo.update!()

      # Record redemption
      Repo.insert!(%{
        __struct__: Ecto.Schema,
        __meta__: %Ecto.Schema.Metadata{source: "promo_redemptions", state: :built},
        code_id: code.id,
        account_id: account_id,
        inserted_at: DateTime.utc_now() |> DateTime.truncate(:second),
        updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
    end)
  end

  defp grant_rewards(account_id, rewards) do
    Enum.map(rewards, fn reward ->
      case reward["type"] do
        "currency" ->
          add_premium_currency(account_id, reward["amount"], "promo")
          reward

        "mount" ->
          Collections.unlock_account_mount(account_id, reward["id"], "promo")
          reward

        "pet" ->
          Collections.unlock_account_pet(account_id, reward["id"], "promo")
          reward

        _ ->
          reward
      end
    end)
  end
end
```

**Step 4: Run tests to verify they pass**

Run: `MIX_ENV=test mix test apps/bezgelor_db/test/storefront_test.exs --include database`
Expected: All tests pass

**Step 5: Commit**

```bash
git add apps/bezgelor_db/lib/bezgelor_db/storefront.ex apps/bezgelor_db/test/storefront_test.exs
git commit -m "feat(db): Add Storefront context with purchases and promo codes"
```

---

## Task 9: Mount Packets

**Files:**
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_mount_list.ex`
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_mount_summoned.ex`
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_mount_dismissed.ex`

**Step 1: Write ServerMountList packet**

```elixir
defmodule BezgelorProtocol.Packets.World.ServerMountList do
  @moduledoc """
  Full mount collection sent on login.

  ## Wire Format
  mount_count       : uint16
  mounts            : [uint32] * mount_count
  active_mount_id   : uint32 (0 if none)
  customization_len : uint16
  customization     : JSON bytes
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct mounts: [], active_mount_id: 0, customization: %{}

  @impl true
  def opcode, do: :server_mount_list

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    customization_json = Jason.encode!(packet.customization)

    writer =
      writer
      |> PacketWriter.write_uint16(length(packet.mounts))

    writer =
      Enum.reduce(packet.mounts, writer, fn mount_id, w ->
        PacketWriter.write_uint32(w, mount_id)
      end)

    writer =
      writer
      |> PacketWriter.write_uint32(packet.active_mount_id)
      |> PacketWriter.write_uint16(byte_size(customization_json))
      |> PacketWriter.write_bytes(customization_json)

    {:ok, writer}
  end
end
```

**Step 2: Write ServerMountSummoned packet**

```elixir
defmodule BezgelorProtocol.Packets.World.ServerMountSummoned do
  @moduledoc """
  Mount summoned notification.

  ## Wire Format
  character_id : uint32
  mount_id     : uint32
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:character_id, :mount_id]

  @impl true
  def opcode, do: :server_mount_summoned

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_uint32(packet.character_id)
      |> PacketWriter.write_uint32(packet.mount_id)

    {:ok, writer}
  end
end
```

**Step 3: Write ServerMountDismissed packet**

```elixir
defmodule BezgelorProtocol.Packets.World.ServerMountDismissed do
  @moduledoc """
  Mount dismissed notification.

  ## Wire Format
  character_id : uint32
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:character_id]

  @impl true
  def opcode, do: :server_mount_dismissed

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer = PacketWriter.write_uint32(writer, packet.character_id)
    {:ok, writer}
  end
end
```

**Step 4: Commit**

```bash
git add apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_mount_*.ex
git commit -m "feat(protocol): Add mount packets"
```

---

## Task 10: Pet Packets

**Files:**
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_pet_list.ex`
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_pet_summoned.ex`
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_pet_level_up.ex`

**Step 1: Write ServerPetList packet**

```elixir
defmodule BezgelorProtocol.Packets.World.ServerPetList do
  @moduledoc """
  Full pet collection sent on login.

  ## Wire Format
  pet_count       : uint16
  pets            : [uint32] * pet_count
  has_active      : uint8 (bool)
  [if has_active]
  active_pet_id   : uint32
  active_level    : uint8
  active_xp       : uint32
  nickname_len    : uint8
  nickname        : string
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct pets: [], active_pet: nil

  @impl true
  def opcode, do: :server_pet_list

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_uint16(length(packet.pets))

    writer =
      Enum.reduce(packet.pets, writer, fn pet_id, w ->
        PacketWriter.write_uint32(w, pet_id)
      end)

    case packet.active_pet do
      nil ->
        writer = PacketWriter.write_byte(writer, 0)
        {:ok, writer}

      pet ->
        nickname = pet.nickname || ""
        writer =
          writer
          |> PacketWriter.write_byte(1)
          |> PacketWriter.write_uint32(pet.pet_id)
          |> PacketWriter.write_byte(pet.level)
          |> PacketWriter.write_uint32(pet.xp)
          |> PacketWriter.write_byte(byte_size(nickname))
          |> PacketWriter.write_bytes(nickname)

        {:ok, writer}
    end
  end
end
```

**Step 2: Write ServerPetSummoned packet**

```elixir
defmodule BezgelorProtocol.Packets.World.ServerPetSummoned do
  @moduledoc """
  Pet summoned notification.

  ## Wire Format
  character_id : uint32
  pet_id       : uint32
  level        : uint8
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:character_id, :pet_id, :level]

  @impl true
  def opcode, do: :server_pet_summoned

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_uint32(packet.character_id)
      |> PacketWriter.write_uint32(packet.pet_id)
      |> PacketWriter.write_byte(packet.level || 1)

    {:ok, writer}
  end
end
```

**Step 3: Write ServerPetLevelUp packet**

```elixir
defmodule BezgelorProtocol.Packets.World.ServerPetLevelUp do
  @moduledoc """
  Pet level up notification.

  ## Wire Format
  new_level : uint8
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:new_level]

  @impl true
  def opcode, do: :server_pet_level_up

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer = PacketWriter.write_byte(writer, packet.new_level)
    {:ok, writer}
  end
end
```

**Step 4: Commit**

```bash
git add apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_pet_*.ex
git commit -m "feat(protocol): Add pet packets"
```

---

## Task 11: Mount Handler

**Files:**
- Create: `apps/bezgelor_world/lib/bezgelor_world/handler/mount_handler.ex`

**Step 1: Write MountHandler**

```elixir
defmodule BezgelorWorld.Handler.MountHandler do
  @moduledoc """
  Handles mount summoning, dismissing, and customization.
  """

  alias BezgelorDb.{Collections, Mounts}
  alias BezgelorProtocol.Packets.World.{
    ServerMountList,
    ServerMountSummoned,
    ServerMountDismissed
  }

  require Logger

  @doc "Send full mount collection to client on login."
  @spec send_mount_list(pid(), integer(), integer()) :: :ok
  def send_mount_list(connection_pid, account_id, character_id) do
    mounts = Collections.get_all_mounts(account_id, character_id)
    active = Mounts.get_active_mount(character_id)

    packet = %ServerMountList{
      mounts: mounts,
      active_mount_id: if(active, do: active.mount_id, else: 0),
      customization: if(active, do: active.customization, else: %{})
    }

    send(connection_pid, {:send_packet, packet})
    :ok
  end

  @doc "Summon a mount."
  @spec summon_mount(pid(), integer(), integer(), integer()) :: :ok | {:error, term()}
  def summon_mount(connection_pid, character_id, account_id, mount_id) do
    case Mounts.set_active_mount(character_id, account_id, mount_id) do
      {:ok, mount} ->
        packet = %ServerMountSummoned{
          character_id: character_id,
          mount_id: mount.mount_id
        }

        send(connection_pid, {:send_packet, packet})
        send(connection_pid, {:broadcast_nearby, packet})
        Logger.debug("Mount #{mount_id} summoned for character #{character_id}")
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Dismiss current mount."
  @spec dismiss_mount(pid(), integer()) :: :ok
  def dismiss_mount(connection_pid, character_id) do
    :ok = Mounts.clear_active_mount(character_id)

    packet = %ServerMountDismissed{character_id: character_id}
    send(connection_pid, {:send_packet, packet})
    send(connection_pid, {:broadcast_nearby, packet})

    Logger.debug("Mount dismissed for character #{character_id}")
    :ok
  end

  @doc "Update mount customization."
  @spec update_customization(pid(), integer(), map()) :: :ok | {:error, term()}
  def update_customization(connection_pid, character_id, customization) do
    case Mounts.update_customization(character_id, customization) do
      {:ok, _mount} ->
        # Could send customization update packet here
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end
end
```

**Step 2: Commit**

```bash
git add apps/bezgelor_world/lib/bezgelor_world/handler/mount_handler.ex
git commit -m "feat(world): Add MountHandler"
```

---

## Task 12: Pet Handler with Auto-Combat

**Files:**
- Create: `apps/bezgelor_world/lib/bezgelor_world/handler/pet_handler.ex`

**Step 1: Write PetHandler with auto-combat**

```elixir
defmodule BezgelorWorld.Handler.PetHandler do
  @moduledoc """
  Handles pet summoning, XP, and auto-combat.

  ## Auto-Combat

  Pets automatically attack when the player is in combat.
  Damage is calculated as: base_damage + (level * 2)
  Pets earn 10% of kill XP.

  Note: This is simplified from WildStar's full pet ability system.
  See GitHub issue #1 for future enhancement.
  """

  use GenServer

  alias BezgelorDb.{Collections, Pets}
  alias BezgelorProtocol.Packets.World.{
    ServerPetList,
    ServerPetSummoned,
    ServerPetLevelUp
  }

  require Logger

  defstruct [:connection_pid, :character_id, :account_id, :in_combat, :attack_timer]

  @attack_interval 2000  # 2 seconds between pet attacks
  @pet_xp_share 0.10     # 10% of kill XP goes to pet

  # Client API

  def start_link(connection_pid, character_id, account_id) do
    GenServer.start_link(__MODULE__, {connection_pid, character_id, account_id})
  end

  @doc "Send full pet collection to client."
  @spec send_pet_list(pid(), integer(), integer()) :: :ok
  def send_pet_list(connection_pid, account_id, character_id) do
    pets = Collections.get_all_pets(account_id, character_id)
    active = Pets.get_active_pet(character_id)

    packet = %ServerPetList{
      pets: pets,
      active_pet: active
    }

    send(connection_pid, {:send_packet, packet})
    :ok
  end

  @doc "Summon a pet."
  @spec summon_pet(pid(), integer(), integer(), integer()) :: :ok | {:error, term()}
  def summon_pet(connection_pid, character_id, account_id, pet_id) do
    case Pets.set_active_pet(character_id, account_id, pet_id) do
      {:ok, pet} ->
        packet = %ServerPetSummoned{
          character_id: character_id,
          pet_id: pet.pet_id,
          level: pet.level
        }

        send(connection_pid, {:send_packet, packet})
        send(connection_pid, {:broadcast_nearby, packet})
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Dismiss current pet."
  @spec dismiss_pet(integer()) :: :ok
  def dismiss_pet(character_id) do
    Pets.clear_active_pet(character_id)
  end

  @doc "Notify pet handler of combat state change."
  def on_combat_start(handler_pid, enemy_id) do
    GenServer.cast(handler_pid, {:combat_start, enemy_id})
  end

  def on_combat_end(handler_pid) do
    GenServer.cast(handler_pid, :combat_end)
  end

  @doc "Award XP to pet from a kill."
  def on_enemy_killed(character_id, xp_earned) do
    pet_xp = trunc(xp_earned * @pet_xp_share)

    case Pets.award_pet_xp(character_id, pet_xp) do
      {:ok, pet, :level_up} ->
        # Pet leveled up - would broadcast this
        Logger.info("Pet leveled up to #{pet.level}!")
        {:ok, :level_up, pet.level}

      {:ok, _pet, :xp_gained} ->
        {:ok, :xp_gained}

      {:error, :no_active_pet} ->
        :ok
    end
  end

  # GenServer Callbacks

  @impl true
  def init({connection_pid, character_id, account_id}) do
    state = %__MODULE__{
      connection_pid: connection_pid,
      character_id: character_id,
      account_id: account_id,
      in_combat: false,
      attack_timer: nil
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:combat_start, _enemy_id}, state) do
    # Start pet auto-attacks
    timer = Process.send_after(self(), :pet_attack, @attack_interval)

    {:noreply, %{state | in_combat: true, attack_timer: timer}}
  end

  @impl true
  def handle_cast(:combat_end, state) do
    # Stop pet auto-attacks
    if state.attack_timer do
      Process.cancel_timer(state.attack_timer)
    end

    {:noreply, %{state | in_combat: false, attack_timer: nil}}
  end

  @impl true
  def handle_info(:pet_attack, %{in_combat: false} = state) do
    {:noreply, state}
  end

  @impl true
  def handle_info(:pet_attack, state) do
    case Pets.get_active_pet(state.character_id) do
      nil ->
        {:noreply, %{state | in_combat: false}}

      pet ->
        # Calculate and apply damage
        # This would integrate with CombatHandler
        _damage = calculate_pet_damage(pet)

        # Schedule next attack
        timer = Process.send_after(self(), :pet_attack, @attack_interval)
        {:noreply, %{state | attack_timer: timer}}
    end
  end

  defp calculate_pet_damage(pet) do
    base_damage = 10  # Would come from pet definition
    base_damage + (pet.level * 2)
  end
end
```

**Step 2: Commit**

```bash
git add apps/bezgelor_world/lib/bezgelor_world/handler/pet_handler.ex
git commit -m "feat(world): Add PetHandler with auto-combat"
```

---

## Task 13: Run All Tests

**Step 1: Run full test suite**

Run: `MIX_ENV=test mix test apps/bezgelor_db/test --include database`
Expected: All tests pass

**Step 2: Commit any fixes if needed**

---

## Task 14: Final Commit

**Step 1: Verify all changes**

Run: `git status`
Expected: Clean working tree

**Step 2: Create summary commit if needed**

```bash
git log --oneline -10
```

---

## Summary

| Task | Files | Tests |
|------|-------|-------|
| 1. Account Currency | 2 | - |
| 2. Collection Schemas | 3 | - |
| 3. Active Mount/Pet | 3 | - |
| 4. Collections Context | 2 | 6 |
| 5. Mounts Context | 2 | 5 |
| 6. Pets Context | 2 | 6 |
| 7. Storefront Schemas | 6 | - |
| 8. Storefront Context | 2 | 7 |
| 9. Mount Packets | 3 | - |
| 10. Pet Packets | 3 | - |
| 11. Mount Handler | 1 | - |
| 12. Pet Handler | 1 | - |

**Total: ~30 files, ~24 tests**
