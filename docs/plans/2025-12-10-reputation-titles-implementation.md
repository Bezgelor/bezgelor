# Reputation & Titles Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Complete Phase 7.12 by adding reputation gains from kills/quests, reputation-gated vendors, and a full title system with account-wide tracking.

**Architecture:** Titles are stored per-account in database, with static definitions in bezgelor_data. Reputation hooks integrate into existing combat and quest flows. Title unlocks fire from reputation level changes, achievement completions, quest completions, and path progress.

**Tech Stack:** Elixir/Ecto, ETS for static data, GenServer handlers, binary protocol packets

---

## Task 1: Database Migration for Titles

**Files:**
- Create: `apps/bezgelor_db/priv/repo/migrations/20251210220000_add_account_titles.exs`

**Step 1: Write the migration**

```elixir
defmodule BezgelorDb.Repo.Migrations.AddAccountTitles do
  use Ecto.Migration

  def change do
    create table(:account_titles) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :title_id, :integer, null: false
      add :unlocked_at, :utc_datetime, null: false

      timestamps()
    end

    create unique_index(:account_titles, [:account_id, :title_id])
    create index(:account_titles, [:account_id])

    alter table(:accounts) do
      add :active_title_id, :integer
    end
  end
end
```

**Step 2: Run migration**

Run: `MIX_ENV=test mix ecto.migrate`
Expected: Migration completes successfully

**Step 3: Commit**

```bash
git add apps/bezgelor_db/priv/repo/migrations/20251210220000_add_account_titles.exs
git commit -m "db: Add account_titles table and active_title_id"
```

---

## Task 2: AccountTitle Schema

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/schema/account_title.ex`
- Modify: `apps/bezgelor_db/lib/bezgelor_db/schema/account.ex`

**Step 1: Create AccountTitle schema**

```elixir
defmodule BezgelorDb.Schema.AccountTitle do
  @moduledoc """
  Tracks titles unlocked by an account.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias BezgelorDb.Schema.Account

  schema "account_titles" do
    belongs_to :account, Account
    field :title_id, :integer
    field :unlocked_at, :utc_datetime

    timestamps()
  end

  @doc "Changeset for creating a new account title."
  def changeset(account_title, attrs) do
    account_title
    |> cast(attrs, [:account_id, :title_id, :unlocked_at])
    |> validate_required([:account_id, :title_id, :unlocked_at])
    |> unique_constraint([:account_id, :title_id])
  end
end
```

**Step 2: Add active_title_id to Account schema**

In `apps/bezgelor_db/lib/bezgelor_db/schema/account.ex`, add to the schema block:

```elixir
field :active_title_id, :integer
```

And update the `@type t` to include:

```elixir
active_title_id: integer() | nil,
```

And update `changeset/2` to cast the new field:

```elixir
|> cast(attrs, [:email, :salt, :verifier, :game_token, :session_key, :active_title_id])
```

**Step 3: Commit**

```bash
git add apps/bezgelor_db/lib/bezgelor_db/schema/account_title.ex apps/bezgelor_db/lib/bezgelor_db/schema/account.ex
git commit -m "schema: Add AccountTitle and active_title_id to Account"
```

---

## Task 3: Titles Database Context

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/titles.ex`
- Test: `apps/bezgelor_db/test/titles_test.exs`

**Step 1: Write failing tests**

```elixir
defmodule BezgelorDb.TitlesTest do
  use ExUnit.Case

  alias BezgelorDb.{Accounts, Repo, Titles}

  @moduletag :database

  setup do
    case Repo.start_link([]) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    email = "titles_test#{System.unique_integer([:positive])}@test.com"
    {:ok, account} = Accounts.create_account(email, "password123")

    {:ok, account: account}
  end

  describe "get_titles/1" do
    test "returns empty list for account with no titles", %{account: account} do
      assert Titles.get_titles(account.id) == []
    end

    test "returns all titles for account", %{account: account} do
      {:ok, _} = Titles.grant_title(account.id, 1001)
      {:ok, _} = Titles.grant_title(account.id, 1002)

      titles = Titles.get_titles(account.id)
      assert length(titles) == 2
    end
  end

  describe "has_title?/2" do
    test "returns false for unowned title", %{account: account} do
      refute Titles.has_title?(account.id, 9999)
    end

    test "returns true for owned title", %{account: account} do
      {:ok, _} = Titles.grant_title(account.id, 1001)
      assert Titles.has_title?(account.id, 1001)
    end
  end

  describe "grant_title/2" do
    test "creates new title", %{account: account} do
      assert {:ok, title} = Titles.grant_title(account.id, 1001)
      assert title.title_id == 1001
      assert title.account_id == account.id
      assert title.unlocked_at != nil
    end

    test "returns already_owned for duplicate", %{account: account} do
      {:ok, first} = Titles.grant_title(account.id, 1001)
      assert {:already_owned, ^first} = Titles.grant_title(account.id, 1001)
    end
  end

  describe "set_active_title/2" do
    test "sets active title when owned", %{account: account} do
      {:ok, _} = Titles.grant_title(account.id, 1001)
      assert {:ok, account} = Titles.set_active_title(account.id, 1001)
      assert account.active_title_id == 1001
    end

    test "returns error when not owned", %{account: account} do
      assert {:error, :not_owned} = Titles.set_active_title(account.id, 9999)
    end

    test "clears active title with nil", %{account: account} do
      {:ok, _} = Titles.grant_title(account.id, 1001)
      {:ok, _} = Titles.set_active_title(account.id, 1001)
      assert {:ok, account} = Titles.set_active_title(account.id, nil)
      assert account.active_title_id == nil
    end
  end

  describe "get_active_title/1" do
    test "returns nil when no active title", %{account: account} do
      assert Titles.get_active_title(account.id) == nil
    end

    test "returns active title id", %{account: account} do
      {:ok, _} = Titles.grant_title(account.id, 1001)
      {:ok, _} = Titles.set_active_title(account.id, 1001)
      assert Titles.get_active_title(account.id) == 1001
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `MIX_ENV=test mix test apps/bezgelor_db/test/titles_test.exs --trace`
Expected: FAIL with "module BezgelorDb.Titles is not available"

**Step 3: Implement Titles context**

```elixir
defmodule BezgelorDb.Titles do
  @moduledoc """
  Title management context.
  """
  import Ecto.Query

  alias BezgelorDb.Repo
  alias BezgelorDb.Schema.{Account, AccountTitle}

  @doc "Get all unlocked titles for an account."
  @spec get_titles(integer()) :: [AccountTitle.t()]
  def get_titles(account_id) do
    AccountTitle
    |> where([t], t.account_id == ^account_id)
    |> order_by([t], desc: t.unlocked_at)
    |> Repo.all()
  end

  @doc "Check if account has unlocked a title."
  @spec has_title?(integer(), integer()) :: boolean()
  def has_title?(account_id, title_id) do
    AccountTitle
    |> where([t], t.account_id == ^account_id and t.title_id == ^title_id)
    |> Repo.exists?()
  end

  @doc "Grant a title to an account. Returns {:already_owned, title} if already unlocked."
  @spec grant_title(integer(), integer()) ::
          {:ok, AccountTitle.t()} | {:already_owned, AccountTitle.t()} | {:error, term()}
  def grant_title(account_id, title_id) do
    case Repo.get_by(AccountTitle, account_id: account_id, title_id: title_id) do
      nil ->
        %AccountTitle{}
        |> AccountTitle.changeset(%{
          account_id: account_id,
          title_id: title_id,
          unlocked_at: DateTime.utc_now()
        })
        |> Repo.insert()

      existing ->
        {:already_owned, existing}
    end
  end

  @doc "Set the active displayed title. Pass nil to clear."
  @spec set_active_title(integer(), integer() | nil) ::
          {:ok, Account.t()} | {:error, :not_owned | term()}
  def set_active_title(account_id, nil) do
    Account
    |> Repo.get!(account_id)
    |> Ecto.Changeset.change(active_title_id: nil)
    |> Repo.update()
  end

  def set_active_title(account_id, title_id) do
    if has_title?(account_id, title_id) do
      Account
      |> Repo.get!(account_id)
      |> Ecto.Changeset.change(active_title_id: title_id)
      |> Repo.update()
    else
      {:error, :not_owned}
    end
  end

  @doc "Get the active title ID for an account."
  @spec get_active_title(integer()) :: integer() | nil
  def get_active_title(account_id) do
    Account
    |> where([a], a.id == ^account_id)
    |> select([a], a.active_title_id)
    |> Repo.one()
  end
end
```

**Step 4: Run tests to verify they pass**

Run: `MIX_ENV=test mix test apps/bezgelor_db/test/titles_test.exs --trace`
Expected: All tests pass

**Step 5: Commit**

```bash
git add apps/bezgelor_db/lib/bezgelor_db/titles.ex apps/bezgelor_db/test/titles_test.exs
git commit -m "feat: Add Titles database context with tests"
```

---

## Task 4: Static Title Definitions

**Files:**
- Create: `apps/bezgelor_data/priv/data/titles.json`
- Modify: `apps/bezgelor_data/lib/bezgelor_data.ex`
- Modify: `apps/bezgelor_data/lib/bezgelor_data/store.ex`

**Step 1: Create titles.json with sample data**

```json
{
  "titles": {
    "1001": {
      "id": 1001,
      "name": "Exile's Champion",
      "description": "Reached Exalted standing with the Exiles",
      "category": "reputation",
      "rarity": "epic",
      "unlock_type": "reputation",
      "unlock_requirements": {"faction_id": 166, "level": "exalted"}
    },
    "1002": {
      "id": 1002,
      "name": "Dominion's Bane",
      "description": "Reached Hated standing with the Dominion",
      "category": "reputation",
      "rarity": "rare",
      "unlock_type": "reputation",
      "unlock_requirements": {"faction_id": 167, "level": "hated"}
    },
    "1003": {
      "id": 1003,
      "name": "Friend of the Exiles",
      "description": "Reached Friendly standing with the Exiles",
      "category": "reputation",
      "rarity": "uncommon",
      "unlock_type": "reputation",
      "unlock_requirements": {"faction_id": 166, "level": "friendly"}
    },
    "2001": {
      "id": 2001,
      "name": "Lore Seeker",
      "description": "Discovered 100 datacubes",
      "category": "achievement",
      "rarity": "rare",
      "unlock_type": "achievement",
      "unlock_requirements": {"achievement_id": 500}
    },
    "3001": {
      "id": 3001,
      "name": "Savior of Thayd",
      "description": "Completed the defense of Thayd",
      "category": "quest",
      "rarity": "epic",
      "unlock_type": "quest",
      "unlock_requirements": {"quest_id": 7500}
    },
    "4001": {
      "id": 4001,
      "name": "Master Explorer",
      "description": "Reached max Explorer path level",
      "category": "path",
      "rarity": "legendary",
      "unlock_type": "path",
      "unlock_requirements": {"path": "explorer", "level": 30}
    },
    "4002": {
      "id": 4002,
      "name": "Master Soldier",
      "description": "Reached max Soldier path level",
      "category": "path",
      "rarity": "legendary",
      "unlock_type": "path",
      "unlock_requirements": {"path": "soldier", "level": 30}
    },
    "4003": {
      "id": 4003,
      "name": "Master Settler",
      "description": "Reached max Settler path level",
      "category": "path",
      "rarity": "legendary",
      "unlock_type": "path",
      "unlock_requirements": {"path": "settler", "level": 30}
    },
    "4004": {
      "id": 4004,
      "name": "Master Scientist",
      "description": "Reached max Scientist path level",
      "category": "path",
      "rarity": "legendary",
      "unlock_type": "path",
      "unlock_requirements": {"path": "scientist", "level": 30}
    }
  }
}
```

**Step 2: Add title accessors to BezgelorData**

Add these functions to `apps/bezgelor_data/lib/bezgelor_data.ex`:

```elixir
# Titles

@doc """
Get a title definition by ID.
"""
@spec get_title(non_neg_integer()) :: {:ok, map()} | :error
def get_title(id) do
  Store.get(:titles, id)
end

@doc """
Get a title by ID, raising if not found.
"""
@spec get_title!(non_neg_integer()) :: map()
def get_title!(id) do
  case get_title(id) do
    {:ok, title} -> title
    :error -> raise "Title #{id} not found"
  end
end

@doc """
List all titles.
"""
@spec list_titles() :: [map()]
def list_titles do
  Store.list(:titles)
end

@doc """
List titles by category.
"""
@spec titles_by_category(String.t()) :: [map()]
def titles_by_category(category) do
  list_titles()
  |> Enum.filter(fn t -> t["category"] == category end)
end

@doc """
List titles by unlock type.
"""
@spec titles_by_unlock_type(String.t()) :: [map()]
def titles_by_unlock_type(unlock_type) do
  list_titles()
  |> Enum.filter(fn t -> t["unlock_type"] == unlock_type end)
end

@doc """
Get all titles that unlock for a specific reputation level.
"""
@spec titles_for_reputation(integer(), atom()) :: [map()]
def titles_for_reputation(faction_id, level) do
  level_str = Atom.to_string(level)

  list_titles()
  |> Enum.filter(fn t ->
    t["unlock_type"] == "reputation" and
      get_in(t, ["unlock_requirements", "faction_id"]) == faction_id and
      get_in(t, ["unlock_requirements", "level"]) == level_str
  end)
end

@doc """
Get all titles that unlock for a specific achievement.
"""
@spec titles_for_achievement(integer()) :: [map()]
def titles_for_achievement(achievement_id) do
  list_titles()
  |> Enum.filter(fn t ->
    t["unlock_type"] == "achievement" and
      get_in(t, ["unlock_requirements", "achievement_id"]) == achievement_id
  end)
end

@doc """
Get all titles that unlock for a specific quest.
"""
@spec titles_for_quest(integer()) :: [map()]
def titles_for_quest(quest_id) do
  list_titles()
  |> Enum.filter(fn t ->
    t["unlock_type"] == "quest" and
      get_in(t, ["unlock_requirements", "quest_id"]) == quest_id
  end)
end

@doc """
Get all titles that unlock for path progress.
"""
@spec titles_for_path(String.t(), integer()) :: [map()]
def titles_for_path(path, level) do
  list_titles()
  |> Enum.filter(fn t ->
    t["unlock_type"] == "path" and
      get_in(t, ["unlock_requirements", "path"]) == path and
      get_in(t, ["unlock_requirements", "level"]) <= level
  end)
end
```

**Step 3: Update Store to load titles**

In `apps/bezgelor_data/lib/bezgelor_data/store.ex`, add `:titles` to the list of tables to load and update the `load_json_files/0` function to include:

```elixir
load_json_file(:titles, "titles.json")
```

And update the `stats/0` function to include:

```elixir
titles: count(:titles),
```

**Step 4: Commit**

```bash
git add apps/bezgelor_data/priv/data/titles.json apps/bezgelor_data/lib/bezgelor_data.ex apps/bezgelor_data/lib/bezgelor_data/store.ex
git commit -m "data: Add title definitions and accessors"
```

---

## Task 5: Title Protocol Packets

**Files:**
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_title_list.ex`
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_title_unlocked.ex`
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_active_title_changed.ex`
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/client_set_active_title.ex`
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/client_get_titles.ex`

**Step 1: Create ServerTitleList packet**

```elixir
defmodule BezgelorProtocol.Packets.World.ServerTitleList do
  @moduledoc """
  Full list of unlocked titles sent to client.

  ## Wire Format
  count       : uint16
  active_id   : uint32 (0 = none)
  titles[]    : (title_id:u32, unlocked_at:u64)
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct titles: [], active_title_id: nil

  @impl true
  def opcode, do: :server_title_list

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer = PacketWriter.write_uint16(writer, length(packet.titles))
    writer = PacketWriter.write_uint32(writer, packet.active_title_id || 0)

    writer =
      Enum.reduce(packet.titles, writer, fn title, w ->
        w
        |> PacketWriter.write_uint32(title.title_id)
        |> PacketWriter.write_uint64(datetime_to_unix(title.unlocked_at))
      end)

    {:ok, writer}
  end

  defp datetime_to_unix(nil), do: 0
  defp datetime_to_unix(%DateTime{} = dt), do: DateTime.to_unix(dt)
end
```

**Step 2: Create ServerTitleUnlocked packet**

```elixir
defmodule BezgelorProtocol.Packets.World.ServerTitleUnlocked do
  @moduledoc """
  Notification that a new title was unlocked.

  ## Wire Format
  title_id    : uint32
  unlocked_at : uint64
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:title_id, :unlocked_at]

  @impl true
  def opcode, do: :server_title_unlocked

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_uint32(packet.title_id)
      |> PacketWriter.write_uint64(datetime_to_unix(packet.unlocked_at))

    {:ok, writer}
  end

  defp datetime_to_unix(nil), do: 0
  defp datetime_to_unix(%DateTime{} = dt), do: DateTime.to_unix(dt)
end
```

**Step 3: Create ServerActiveTitleChanged packet**

```elixir
defmodule BezgelorProtocol.Packets.World.ServerActiveTitleChanged do
  @moduledoc """
  Confirms active title change.

  ## Wire Format
  title_id : uint32 (0 = cleared)
  success  : uint8
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:title_id, :success]

  @impl true
  def opcode, do: :server_active_title_changed

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_uint32(packet.title_id || 0)
      |> PacketWriter.write_byte(if(packet.success, do: 1, else: 0))

    {:ok, writer}
  end
end
```

**Step 4: Create ClientSetActiveTitle packet**

```elixir
defmodule BezgelorProtocol.Packets.World.ClientSetActiveTitle do
  @moduledoc """
  Client requests to change active title.

  ## Wire Format
  title_id : uint32 (0 = clear)
  """
  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:title_id]

  @impl true
  def opcode, do: :client_set_active_title

  @impl true
  def read(reader) do
    {title_id, reader} = PacketReader.read_uint32(reader)

    packet = %__MODULE__{
      title_id: if(title_id == 0, do: nil, else: title_id)
    }

    {:ok, packet, reader}
  end
end
```

**Step 5: Create ClientGetTitles packet**

```elixir
defmodule BezgelorProtocol.Packets.World.ClientGetTitles do
  @moduledoc """
  Client requests title list refresh.

  ## Wire Format
  (empty)
  """
  @behaviour BezgelorProtocol.Packet.Readable

  defstruct []

  @impl true
  def opcode, do: :client_get_titles

  @impl true
  def read(reader) do
    {:ok, %__MODULE__{}, reader}
  end
end
```

**Step 6: Commit**

```bash
git add apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_title_list.ex \
        apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_title_unlocked.ex \
        apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_active_title_changed.ex \
        apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/client_set_active_title.ex \
        apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/client_get_titles.ex
git commit -m "protocol: Add title packets (list, unlocked, changed, set, get)"
```

---

## Task 6: TitleHandler

**Files:**
- Create: `apps/bezgelor_world/lib/bezgelor_world/handler/title_handler.ex`

**Step 1: Create TitleHandler**

```elixir
defmodule BezgelorWorld.Handler.TitleHandler do
  @moduledoc """
  Handles title-related packets and unlock events.

  ## Packets Handled
  - ClientSetActiveTitle - Change displayed title
  - ClientGetTitles - Request title list refresh

  ## Unlock Sources
  - Reputation level changes
  - Achievement completions
  - Quest completions
  - Path progress
  """

  require Logger

  alias BezgelorDb.Titles
  alias BezgelorData
  alias BezgelorProtocol.Packets.World.{
    ServerTitleList,
    ServerTitleUnlocked,
    ServerActiveTitleChanged
  }

  @doc """
  Send full title list to client (called on login).
  """
  @spec send_title_list(pid(), integer()) :: :ok
  def send_title_list(connection_pid, account_id) do
    titles = Titles.get_titles(account_id)
    active_title_id = Titles.get_active_title(account_id)

    packet = %ServerTitleList{
      titles: titles,
      active_title_id: active_title_id
    }

    send(connection_pid, {:send_packet, packet})
    :ok
  end

  @doc """
  Handle client request to change active title.
  """
  @spec handle_set_active_title(pid(), integer(), integer() | nil) :: :ok
  def handle_set_active_title(connection_pid, account_id, title_id) do
    result = Titles.set_active_title(account_id, title_id)

    response = case result do
      {:ok, _account} ->
        Logger.debug("Account #{account_id} set active title to #{inspect(title_id)}")
        %ServerActiveTitleChanged{title_id: title_id, success: true}

      {:error, :not_owned} ->
        Logger.warning("Account #{account_id} tried to set unowned title #{title_id}")
        %ServerActiveTitleChanged{title_id: nil, success: false}

      {:error, reason} ->
        Logger.error("Failed to set active title: #{inspect(reason)}")
        %ServerActiveTitleChanged{title_id: nil, success: false}
    end

    send(connection_pid, {:send_packet, response})
    :ok
  end

  @doc """
  Check and grant titles after reputation level change.
  """
  @spec check_reputation_titles(pid(), integer(), integer(), atom()) :: :ok
  def check_reputation_titles(connection_pid, account_id, faction_id, new_level) do
    titles = BezgelorData.titles_for_reputation(faction_id, new_level)

    Enum.each(titles, fn title_def ->
      grant_title_if_new(connection_pid, account_id, title_def["id"])
    end)

    :ok
  end

  @doc """
  Check and grant titles after achievement completion.
  """
  @spec check_achievement_titles(pid(), integer(), integer()) :: :ok
  def check_achievement_titles(connection_pid, account_id, achievement_id) do
    titles = BezgelorData.titles_for_achievement(achievement_id)

    Enum.each(titles, fn title_def ->
      grant_title_if_new(connection_pid, account_id, title_def["id"])
    end)

    :ok
  end

  @doc """
  Check and grant titles after quest completion.
  """
  @spec check_quest_titles(pid(), integer(), integer()) :: :ok
  def check_quest_titles(connection_pid, account_id, quest_id) do
    titles = BezgelorData.titles_for_quest(quest_id)

    Enum.each(titles, fn title_def ->
      grant_title_if_new(connection_pid, account_id, title_def["id"])
    end)

    :ok
  end

  @doc """
  Check and grant titles after path progress.
  """
  @spec check_path_titles(pid(), integer(), String.t(), integer()) :: :ok
  def check_path_titles(connection_pid, account_id, path, level) do
    titles = BezgelorData.titles_for_path(path, level)

    Enum.each(titles, fn title_def ->
      grant_title_if_new(connection_pid, account_id, title_def["id"])
    end)

    :ok
  end

  # Private

  defp grant_title_if_new(connection_pid, account_id, title_id) do
    case Titles.grant_title(account_id, title_id) do
      {:ok, title} ->
        Logger.info("Account #{account_id} unlocked title #{title_id}")

        packet = %ServerTitleUnlocked{
          title_id: title.title_id,
          unlocked_at: title.unlocked_at
        }

        send(connection_pid, {:send_packet, packet})

      {:already_owned, _} ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to grant title #{title_id}: #{inspect(reason)}")
    end
  end
end
```

**Step 2: Commit**

```bash
git add apps/bezgelor_world/lib/bezgelor_world/handler/title_handler.ex
git commit -m "feat: Add TitleHandler for title management and unlocks"
```

---

## Task 7: Reputation Integration - Kill Rewards

**Files:**
- Modify: `apps/bezgelor_world/lib/bezgelor_world/creature_manager.ex`
- Modify: `apps/bezgelor_data/priv/data/creatures.json` (add reputation_rewards field)

**Step 1: Add reputation rewards to creature death handling**

In `apps/bezgelor_world/lib/bezgelor_world/creature_manager.ex`, modify `handle_creature_death/4` to include reputation rewards in the result:

Find the `result_info` map in `handle_creature_death/4` and add:

```elixir
reputation_rewards: template.reputation_rewards || []
```

The full `result_info` should become:

```elixir
result_info = %{
  creature_guid: entity.guid,
  xp_reward: xp_reward,
  loot_drops: loot_drops,
  gold: Loot.gold_from_drops(loot_drops),
  items: Loot.items_from_drops(loot_drops),
  killer_guid: killer_guid,
  reputation_rewards: template.reputation_rewards || []
}
```

**Step 2: Update creature template to support reputation_rewards**

In `apps/bezgelor_core/lib/bezgelor_core/creature_template.ex`, add the field:

```elixir
field :reputation_rewards, list(map()), default: []
```

And update the `from_data/1` function to parse it:

```elixir
reputation_rewards: Map.get(data, "reputation_rewards", [])
```

**Step 3: Add sample reputation_rewards to a creature in creatures.json**

Update a creature entry in `apps/bezgelor_data/priv/data/creatures.json`:

```json
{
  "id": 12345,
  "reputation_rewards": [
    {"faction_id": 166, "amount": 25},
    {"faction_id": 167, "amount": -10}
  ]
}
```

**Step 4: Commit**

```bash
git add apps/bezgelor_world/lib/bezgelor_world/creature_manager.ex \
        apps/bezgelor_core/lib/bezgelor_core/creature_template.ex \
        apps/bezgelor_data/priv/data/creatures.json
git commit -m "feat: Add reputation rewards to creature kills"
```

---

## Task 8: Reputation Integration - Quest Rewards

**Files:**
- Modify: `apps/bezgelor_world/lib/bezgelor_world/handler/quest_handler.ex`

**Step 1: Add reputation reward processing to quest turn-in**

In `apps/bezgelor_world/lib/bezgelor_world/handler/quest_handler.ex`, modify `handle_turn_in_quest/3` to process reputation rewards.

Add these aliases at the top:

```elixir
alias BezgelorWorld.Handler.{ReputationHandler, TitleHandler}
alias BezgelorDb.Characters
```

Replace the TODO comment section in `handle_turn_in_quest/3` with:

```elixir
# Grant reputation rewards
if quest_data = BezgelorData.get_quest(packet.quest_id) do
  reputation_rewards = Map.get(quest_data, :reputation_rewards, [])
  account_id = get_account_id(character_id)

  Enum.each(reputation_rewards, fn reward ->
    {:ok, result} = ReputationHandler.modify_reputation(
      connection_pid,
      character_id,
      reward["faction_id"],
      reward["amount"]
    )

    # Check for title unlocks on level change
    if result[:level_changed] do
      TitleHandler.check_reputation_titles(
        connection_pid,
        account_id,
        reward["faction_id"],
        result.level
      )
    end
  end)

  # Check for quest-specific titles
  TitleHandler.check_quest_titles(connection_pid, account_id, packet.quest_id)
end
```

Add helper function:

```elixir
defp get_account_id(character_id) do
  case Characters.get_character(character_id) do
    nil -> nil
    char -> char.account_id
  end
end
```

**Step 2: Commit**

```bash
git add apps/bezgelor_world/lib/bezgelor_world/handler/quest_handler.ex
git commit -m "feat: Add reputation rewards to quest turn-in"
```

---

## Task 9: Reputation Handler Enhancement

**Files:**
- Modify: `apps/bezgelor_world/lib/bezgelor_world/handler/reputation_handler.ex`

**Step 1: Update modify_reputation to return level change info**

Modify the `modify_reputation/4` function to detect and return level changes:

```elixir
@doc """
Modify reputation and send update to client.
Returns {:ok, %{standing: integer, level: atom, level_changed: boolean}} or {:error, term}.
"""
@spec modify_reputation(pid(), integer(), integer(), integer()) ::
        {:ok, map()} | {:error, term()}
def modify_reputation(connection_pid, character_id, faction_id, delta) do
  # Get old level before modification
  old_level = Reputation.get_level(character_id, faction_id)

  case Reputation.modify_reputation(character_id, faction_id, delta) do
    {:ok, rep} ->
      new_level = RepCore.standing_to_level(rep.standing)
      level_changed = old_level != new_level

      packet = %ServerReputationUpdate{
        faction_id: faction_id,
        standing: rep.standing,
        delta: delta,
        level: new_level
      }

      send(connection_pid, {:send_packet, packet})

      Logger.debug(
        "Reputation updated for character #{character_id}: " <>
          "faction #{faction_id}, delta #{delta}, new standing #{rep.standing} (#{new_level})" <>
          if(level_changed, do: " [LEVEL CHANGED from #{old_level}]", else: "")
      )

      {:ok, %{standing: rep.standing, level: new_level, level_changed: level_changed}}

    {:error, reason} ->
      Logger.warning(
        "Failed to modify reputation for character #{character_id}: #{inspect(reason)}"
      )

      {:error, reason}
  end
end
```

**Step 2: Commit**

```bash
git add apps/bezgelor_world/lib/bezgelor_world/handler/reputation_handler.ex
git commit -m "feat: Return level_changed from reputation modifications"
```

---

## Task 10: Achievement Handler Title Integration

**Files:**
- Modify: `apps/bezgelor_world/lib/bezgelor_world/handler/achievement_handler.ex`

**Step 1: Add title check after achievement completion**

Add alias at top:

```elixir
alias BezgelorWorld.Handler.TitleHandler
alias BezgelorDb.Characters
```

Modify `send_earned/2` to also check for titles:

```elixir
defp send_earned(connection_pid, achievement, character_id) do
  packet = %ServerAchievementEarned{
    achievement_id: achievement.achievement_id,
    points: achievement.points_awarded,
    completed_at: achievement.completed_at
  }

  send(connection_pid, {:send_packet, packet})

  Logger.info("Achievement #{achievement.achievement_id} earned! (#{achievement.points_awarded} points)")

  # Check for title unlocks
  case Characters.get_character(character_id) do
    nil -> :ok
    char ->
      TitleHandler.check_achievement_titles(
        connection_pid,
        char.account_id,
        achievement.achievement_id
      )
  end
end
```

Update all calls to `send_earned/2` to pass character_id as third argument.

**Step 2: Commit**

```bash
git add apps/bezgelor_world/lib/bezgelor_world/handler/achievement_handler.ex
git commit -m "feat: Add title unlock check after achievement completion"
```

---

## Task 11: Run Full Test Suite

**Step 1: Run all tests**

Run: `MIX_ENV=test mix test --trace`
Expected: All tests pass

**Step 2: Fix any failures**

If tests fail, debug and fix issues.

**Step 3: Commit any fixes**

```bash
git add -A
git commit -m "fix: Address test failures from reputation/title integration"
```

---

## Task 12: Update STATUS.md

**Files:**
- Modify: `docs/STATUS.md`

**Step 1: Mark Reputation as complete**

Update Phase 7 table:
- Change `| 7.12 Reputation | ⏳ Pending |` to `| 7.12 Reputation | ✅ Complete |`

Update Phase 7 completion percentage:
- Change `~92%` to `100%`

Update "What Remains" section:
- Remove "Phase 7 Pending Systems" section entirely

Update database schema count:
- Add `account_title` to Account-wide section
- Update count from 37 to 38

Add to Recent Completions:
- `- **2025-12-10:** Phase 7 System 12 (Reputation - kill/quest rewards, vendor gating, titles)`

**Step 2: Commit**

```bash
git add docs/STATUS.md
git commit -m "docs: Mark Phase 7 Reputation complete (100%)"
```

---

## Summary

| Task | Description | Files | LOC |
|------|-------------|-------|-----|
| 1 | Migration | 1 new | ~25 |
| 2 | AccountTitle schema | 1 new, 1 modify | ~40 |
| 3 | Titles context | 1 new, 1 test | ~180 |
| 4 | Static data | 1 new, 2 modify | ~120 |
| 5 | Protocol packets | 5 new | ~120 |
| 6 | TitleHandler | 1 new | ~120 |
| 7 | Kill reputation | 2 modify | ~20 |
| 8 | Quest reputation | 1 modify | ~30 |
| 9 | Reputation handler | 1 modify | ~15 |
| 10 | Achievement titles | 1 modify | ~15 |
| 11 | Test suite | - | - |
| 12 | STATUS.md | 1 modify | ~10 |

**Total: ~695 LOC**
