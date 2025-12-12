# Phase 7: Game Systems Implementation Plan

**Status:** ✅ Complete

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement core game systems (Social, Inventory, Reputation, Quests, Achievements, Paths, Guilds, Mail) to create a functional MMO experience.

**Architecture:** Each system follows the established pattern: Database schemas in `bezgelor_db`, core logic in `bezgelor_core`, packets in `bezgelor_protocol`, handlers in `bezgelor_world`. Systems are independent but share common patterns.

**Tech Stack:** Elixir, Ecto, GenServer, ETS, Ranch TCP

---

## System Overview

| # | System | Complexity | Tasks | Dependencies | Status |
|---|--------|------------|-------|--------------|--------|
| 1 | Social | Low | 1-15 | None | ✅ Done |
| 2 | Inventory | Medium | 16-40 | None | ✅ Done |
| 3 | Reputation | Low | 41-52 | None | ✅ Done |
| 4 | Quests | High | 53-85 | Inventory (rewards) | ✅ Done |
| 5 | Achievements | Medium | 86-105 | None | ✅ Done |
| 6 | Paths | Medium | 106-125 | Quests (missions) | ✅ Done |
| 7 | Guilds | Medium | 126-155 | Social | ✅ Done |
| 8 | Mail | Medium | 156-175 | Inventory (attachments) | ✅ Done |

---

## Implementation Summary

All 8 game systems have been implemented with the following key files:

### Context Modules (all in `apps/bezgelor_db/lib/bezgelor_db/`)
- `social.ex` - Friends and ignore lists
- `inventory.ex` - Item management, equipment, bags
- `reputation.ex` - Faction standings
- `quests.ex` - Quest tracking and completion
- `achievements.ex` - Achievement progress
- `paths.ex` - Path missions and progression
- `guilds.ex` - Guild management
- `mail.ex` - In-game mail system

---

# System 1: Social (Friends & Ignore)

**Goal:** Players can add friends, see online status, and ignore unwanted players.

## Task 1: Create Friend Schema

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/schema/friend.ex`

```elixir
defmodule BezgelorDb.Schema.Friend do
  @moduledoc """
  Friend relationship between characters.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias BezgelorDb.Schema.Character

  schema "friends" do
    belongs_to :character, Character
    belongs_to :friend_character, Character
    field :note, :string, default: ""
    field :group_name, :string, default: "Friends"
    timestamps()
  end

  def changeset(friend, attrs) do
    friend
    |> cast(attrs, [:character_id, :friend_character_id, :note, :group_name])
    |> validate_required([:character_id, :friend_character_id])
    |> unique_constraint([:character_id, :friend_character_id])
  end
end
```

---

## Task 2: Create Ignore Schema

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/schema/ignore.ex`

```elixir
defmodule BezgelorDb.Schema.Ignore do
  @moduledoc """
  Ignore/block relationship between characters.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias BezgelorDb.Schema.Character

  schema "ignores" do
    belongs_to :character, Character
    belongs_to :ignored_character, Character
    timestamps()
  end

  def changeset(ignore, attrs) do
    ignore
    |> cast(attrs, [:character_id, :ignored_character_id])
    |> validate_required([:character_id, :ignored_character_id])
    |> unique_constraint([:character_id, :ignored_character_id])
  end
end
```

---

## Task 3: Create Migration for Social Tables

**Files:**
- Create: `apps/bezgelor_db/priv/repo/migrations/TIMESTAMP_create_social_tables.exs`

```elixir
defmodule BezgelorDb.Repo.Migrations.CreateSocialTables do
  use Ecto.Migration

  def change do
    create table(:friends) do
      add :character_id, references(:characters, on_delete: :delete_all), null: false
      add :friend_character_id, references(:characters, on_delete: :delete_all), null: false
      add :note, :string, size: 256, default: ""
      add :group_name, :string, size: 64, default: "Friends"
      timestamps()
    end

    create unique_index(:friends, [:character_id, :friend_character_id])
    create index(:friends, [:friend_character_id])

    create table(:ignores) do
      add :character_id, references(:characters, on_delete: :delete_all), null: false
      add :ignored_character_id, references(:characters, on_delete: :delete_all), null: false
      timestamps()
    end

    create unique_index(:ignores, [:character_id, :ignored_character_id])
  end
end
```

**Run:** `mix ecto.gen.migration create_social_tables` then paste content.

---

## Task 4: Create Social Context Module

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/social.ex`

```elixir
defmodule BezgelorDb.Social do
  @moduledoc """
  Social features context - friends and ignore lists.
  """
  import Ecto.Query
  alias BezgelorDb.Repo
  alias BezgelorDb.Schema.{Character, Friend, Ignore}

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
      count >= @max_friends -> {:error, :friend_list_full}
      character_id == friend_id -> {:error, :cannot_friend_self}
      true ->
        %Friend{}
        |> Friend.changeset(%{character_id: character_id, friend_character_id: friend_id, note: note})
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
    Repo.exists?(from f in Friend, where: f.character_id == ^character_id and f.friend_character_id == ^friend_id)
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
      count >= @max_ignores -> {:error, :ignore_list_full}
      character_id == ignored_id -> {:error, :cannot_ignore_self}
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
    Repo.exists?(from i in Ignore, where: i.character_id == ^character_id and i.ignored_character_id == ^ignored_id)
  end
end
```

---

## Task 5: Social Packets - ClientAddFriend

**Files:**
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/client_add_friend.ex`

```elixir
defmodule BezgelorProtocol.Packets.World.ClientAddFriend do
  @moduledoc """
  Request to add a friend.

  ## Wire Format
  target_name : wstring - Name of player to add
  note        : wstring - Optional note
  """
  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:target_name, :note]

  @impl true
  def opcode, do: :client_add_friend

  @impl true
  def read(reader) do
    with {:ok, target_name, reader} <- PacketReader.read_wide_string(reader),
         {:ok, note, reader} <- PacketReader.read_wide_string(reader) do
      {:ok, %__MODULE__{target_name: target_name, note: note}, reader}
    end
  end
end
```

---

## Task 6: Social Packets - ClientRemoveFriend

**Files:**
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/client_remove_friend.ex`

```elixir
defmodule BezgelorProtocol.Packets.World.ClientRemoveFriend do
  @moduledoc """
  Request to remove a friend.

  ## Wire Format
  friend_id : uint64 - Character ID of friend to remove
  """
  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:friend_id]

  @impl true
  def opcode, do: :client_remove_friend

  @impl true
  def read(reader) do
    with {:ok, friend_id, reader} <- PacketReader.read_uint64(reader) do
      {:ok, %__MODULE__{friend_id: friend_id}, reader}
    end
  end
end
```

---

## Task 7: Social Packets - ServerFriendList

**Files:**
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_friend_list.ex`

```elixir
defmodule BezgelorProtocol.Packets.World.ServerFriendList do
  @moduledoc """
  Full friend list sent to client.

  ## Wire Format
  count   : uint32
  friends : [FriendEntry] * count

  FriendEntry:
    character_id : uint64
    name         : wstring
    level        : uint8
    class        : uint8
    online       : uint8 (0/1)
    zone_id      : uint32
    note         : wstring
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct friends: []

  @impl true
  def opcode, do: :server_friend_list

  @impl true
  def write(%__MODULE__{friends: friends}, writer) do
    writer = PacketWriter.write_uint32(writer, length(friends))

    writer = Enum.reduce(friends, writer, fn friend, w ->
      w
      |> PacketWriter.write_uint64(friend.character_id)
      |> PacketWriter.write_wide_string(friend.name)
      |> PacketWriter.write_byte(friend.level)
      |> PacketWriter.write_byte(friend.class)
      |> PacketWriter.write_byte(if(friend.online, do: 1, else: 0))
      |> PacketWriter.write_uint32(friend.zone_id || 0)
      |> PacketWriter.write_wide_string(friend.note || "")
    end)

    {:ok, writer}
  end
end
```

---

## Task 8: Social Packets - ServerSocialResult

**Files:**
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_social_result.ex`

```elixir
defmodule BezgelorProtocol.Packets.World.ServerSocialResult do
  @moduledoc """
  Result of social operation (add/remove friend/ignore).

  ## Result Codes
  0 = success
  1 = player_not_found
  2 = already_friend
  3 = list_full
  4 = cannot_add_self
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:result, :operation, :target_name]

  @impl true
  def opcode, do: :server_social_result

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    result_code = result_to_int(packet.result)
    op_code = operation_to_int(packet.operation)

    writer =
      writer
      |> PacketWriter.write_uint32(result_code)
      |> PacketWriter.write_uint32(op_code)
      |> PacketWriter.write_wide_string(packet.target_name || "")

    {:ok, writer}
  end

  defp result_to_int(:success), do: 0
  defp result_to_int(:player_not_found), do: 1
  defp result_to_int(:already_friend), do: 2
  defp result_to_int(:list_full), do: 3
  defp result_to_int(:cannot_add_self), do: 4
  defp result_to_int(_), do: 255

  defp operation_to_int(:add_friend), do: 0
  defp operation_to_int(:remove_friend), do: 1
  defp operation_to_int(:add_ignore), do: 2
  defp operation_to_int(:remove_ignore), do: 3
  defp operation_to_int(_), do: 0
end
```

---

## Task 9: Social Packets - Ignore Packets

**Files:**
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/client_add_ignore.ex`
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/client_remove_ignore.ex`
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_ignore_list.ex`

Similar structure to friend packets. ClientAddIgnore has target_name, ClientRemoveIgnore has ignore_id, ServerIgnoreList has list of ignored characters.

---

## Task 10: Create SocialHandler

**Files:**
- Create: `apps/bezgelor_world/lib/bezgelor_world/handler/social_handler.ex`

```elixir
defmodule BezgelorWorld.Handler.SocialHandler do
  @moduledoc """
  Handler for social packets (friends, ignores).
  """
  @behaviour BezgelorProtocol.Handler

  alias BezgelorProtocol.PacketReader
  alias BezgelorProtocol.Packets.World.{
    ClientAddFriend, ClientRemoveFriend,
    ClientAddIgnore, ClientRemoveIgnore,
    ServerFriendList, ServerIgnoreList, ServerSocialResult
  }
  alias BezgelorDb.{Characters, Social}
  alias BezgelorWorld.WorldManager

  require Logger

  @impl true
  def handle(payload, state) do
    reader = PacketReader.new(payload)

    # Try each packet type
    with {:error, _} <- try_add_friend(reader, state),
         {:error, _} <- try_remove_friend(reader, state),
         {:error, _} <- try_add_ignore(reader, state),
         {:error, _} <- try_remove_ignore(reader, state) do
      {:error, :unknown_social_packet}
    end
  end

  defp try_add_friend(reader, state) do
    case ClientAddFriend.read(reader) do
      {:ok, packet, _} -> handle_add_friend(packet, state)
      error -> error
    end
  end

  defp handle_add_friend(packet, state) do
    character_id = state.session_data[:character_id]

    case Characters.get_character_by_name(packet.target_name) do
      nil ->
        send_result(:player_not_found, :add_friend, packet.target_name, state)

      target ->
        case Social.add_friend(character_id, target.id, packet.note) do
          {:ok, _} ->
            send_result(:success, :add_friend, packet.target_name, state)
          {:error, :friend_list_full} ->
            send_result(:list_full, :add_friend, packet.target_name, state)
          {:error, :cannot_friend_self} ->
            send_result(:cannot_add_self, :add_friend, packet.target_name, state)
          {:error, _} ->
            send_result(:already_friend, :add_friend, packet.target_name, state)
        end
    end
  end

  # Similar handlers for remove_friend, add_ignore, remove_ignore...

  defp send_result(result, operation, target_name, state) do
    packet = %ServerSocialResult{result: result, operation: operation, target_name: target_name}
    # Send packet...
    {:ok, state}
  end
end
```

---

## Task 11-15: Social Tests

**Files:**
- Create: `apps/bezgelor_db/test/social_test.exs`
- Create: `apps/bezgelor_protocol/test/packets/world/social_packets_test.exs`
- Create: `apps/bezgelor_world/test/handler/social_handler_test.exs`

Test adding/removing friends, adding/removing ignores, list retrieval, edge cases (full list, self-add, duplicates).

---

# System 2: Inventory

**Goal:** Players can carry items in bags, equip gear, and manage their inventory.

**Architecture Decision:** Auto-stack - items automatically merge into existing stacks when looted/moved.

## Task 16: Create Item Schema

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/schema/item.ex`

```elixir
defmodule BezgelorDb.Schema.Item do
  @moduledoc """
  An item instance owned by a character.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias BezgelorDb.Schema.Character

  schema "items" do
    belongs_to :character, Character
    field :item_id, :integer          # Reference to static item data
    field :stack_count, :integer, default: 1
    field :bag_index, :integer        # Which bag (0-4, 0 = equipped)
    field :slot_index, :integer       # Slot within bag
    field :durability, :integer
    field :charges, :integer
    field :bound, :boolean, default: false
    field :random_suffix_id, :integer # For random stat items
    timestamps()
  end

  def changeset(item, attrs) do
    item
    |> cast(attrs, [:character_id, :item_id, :stack_count, :bag_index, :slot_index,
                    :durability, :charges, :bound, :random_suffix_id])
    |> validate_required([:character_id, :item_id, :bag_index, :slot_index])
    |> validate_number(:stack_count, greater_than: 0, less_than_or_equal_to: 9999)
    |> unique_constraint([:character_id, :bag_index, :slot_index])
  end
end
```

---

## Task 17: Create Bag Schema

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/schema/bag.ex`

```elixir
defmodule BezgelorDb.Schema.Bag do
  @moduledoc """
  A bag/container owned by a character.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias BezgelorDb.Schema.Character

  schema "bags" do
    belongs_to :character, Character
    field :bag_index, :integer        # 1-4 (0 is backpack, always exists)
    field :item_id, :integer          # Bag item (determines size)
    field :slots, :integer, default: 12
    timestamps()
  end

  def changeset(bag, attrs) do
    bag
    |> cast(attrs, [:character_id, :bag_index, :item_id, :slots])
    |> validate_required([:character_id, :bag_index, :slots])
    |> validate_number(:bag_index, greater_than_or_equal_to: 1, less_than_or_equal_to: 4)
    |> unique_constraint([:character_id, :bag_index])
  end
end
```

---

## Task 18: Create Inventory Migration

**Files:**
- Create: `apps/bezgelor_db/priv/repo/migrations/TIMESTAMP_create_inventory_tables.exs`

```elixir
defmodule BezgelorDb.Repo.Migrations.CreateInventoryTables do
  use Ecto.Migration

  def change do
    create table(:bags) do
      add :character_id, references(:characters, on_delete: :delete_all), null: false
      add :bag_index, :integer, null: false
      add :item_id, :integer
      add :slots, :integer, default: 12
      timestamps()
    end

    create unique_index(:bags, [:character_id, :bag_index])

    create table(:items) do
      add :character_id, references(:characters, on_delete: :delete_all), null: false
      add :item_id, :integer, null: false
      add :stack_count, :integer, default: 1
      add :bag_index, :integer, null: false
      add :slot_index, :integer, null: false
      add :durability, :integer
      add :charges, :integer
      add :bound, :boolean, default: false
      add :random_suffix_id, :integer
      timestamps()
    end

    create unique_index(:items, [:character_id, :bag_index, :slot_index])
    create index(:items, [:character_id])
    create index(:items, [:item_id])
  end
end
```

---

## Task 19: Static Item Data in BezgelorData

**Files:**
- Modify: `apps/bezgelor_data/lib/bezgelor_data.ex`

```elixir
# Add to BezgelorData module

@doc "Get item definition by ID."
@spec get_item(integer()) :: map() | nil
def get_item(item_id) do
  Store.get(:items, item_id)
end

@doc "Get all items matching criteria."
@spec find_items(keyword()) :: [map()]
def find_items(criteria) do
  Store.find(:items, criteria)
end
```

**Files:**
- Create: `apps/bezgelor_data/priv/data/items.json`

```json
{
  "items": [
    {
      "id": 1,
      "name": "Worn Sword",
      "quality": "common",
      "item_type": "weapon",
      "slot": "main_hand",
      "level": 1,
      "max_stack": 1,
      "bind_on": "equip"
    },
    {
      "id": 100,
      "name": "Small Bag",
      "quality": "common",
      "item_type": "bag",
      "bag_slots": 8,
      "max_stack": 1
    }
  ]
}
```

---

## Task 20: Create Inventory Context Module

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/inventory.ex`

```elixir
defmodule BezgelorDb.Inventory do
  @moduledoc """
  Inventory management context.
  """
  import Ecto.Query
  alias BezgelorDb.Repo
  alias BezgelorDb.Schema.{Item, Bag}
  alias BezgelorData

  @backpack_slots 20  # Default backpack size
  @max_bags 4

  # Bag management

  @spec get_bags(integer()) :: [Bag.t()]
  def get_bags(character_id) do
    Bag
    |> where([b], b.character_id == ^character_id)
    |> order_by(:bag_index)
    |> Repo.all()
  end

  @spec total_slots(integer()) :: integer()
  def total_slots(character_id) do
    bags = get_bags(character_id)
    bag_slots = Enum.reduce(bags, 0, fn bag, acc -> acc + bag.slots end)
    @backpack_slots + bag_slots
  end

  # Item management

  @spec get_items(integer()) :: [Item.t()]
  def get_items(character_id) do
    Item
    |> where([i], i.character_id == ^character_id)
    |> order_by([:bag_index, :slot_index])
    |> Repo.all()
  end

  @spec get_item(integer(), integer(), integer()) :: Item.t() | nil
  def get_item(character_id, bag_index, slot_index) do
    Repo.get_by(Item, character_id: character_id, bag_index: bag_index, slot_index: slot_index)
  end

  @spec add_item(integer(), integer(), integer()) :: {:ok, Item.t()} | {:error, term()}
  def add_item(character_id, item_id, count \\ 1) do
    item_def = BezgelorData.get_item(item_id)

    cond do
      item_def == nil -> {:error, :invalid_item}
      count < 1 -> {:error, :invalid_count}
      true -> do_add_item(character_id, item_id, count, item_def)
    end
  end

  defp do_add_item(character_id, item_id, count, item_def) do
    max_stack = item_def["max_stack"] || 1

    # Try to stack with existing items first
    if max_stack > 1 do
      try_stack_item(character_id, item_id, count, max_stack)
    else
      find_empty_slot_and_create(character_id, item_id, count)
    end
  end

  defp try_stack_item(character_id, item_id, count, max_stack) do
    existing = Repo.one(
      from i in Item,
      where: i.character_id == ^character_id and i.item_id == ^item_id and i.stack_count < ^max_stack,
      limit: 1
    )

    case existing do
      nil ->
        find_empty_slot_and_create(character_id, item_id, count)
      item ->
        new_count = min(item.stack_count + count, max_stack)
        remainder = count - (new_count - item.stack_count)

        {:ok, _} = item |> Item.changeset(%{stack_count: new_count}) |> Repo.update()

        if remainder > 0 do
          try_stack_item(character_id, item_id, remainder, max_stack)
        else
          {:ok, item}
        end
    end
  end

  defp find_empty_slot_and_create(character_id, item_id, count) do
    case find_empty_slot(character_id) do
      nil -> {:error, :inventory_full}
      {bag_index, slot_index} ->
        %Item{}
        |> Item.changeset(%{
          character_id: character_id,
          item_id: item_id,
          stack_count: count,
          bag_index: bag_index,
          slot_index: slot_index
        })
        |> Repo.insert()
    end
  end

  @spec find_empty_slot(integer()) :: {integer(), integer()} | nil
  def find_empty_slot(character_id) do
    items = get_items(character_id)
    occupied = MapSet.new(items, fn i -> {i.bag_index, i.slot_index} end)
    bags = get_bags(character_id)

    # Check backpack first (bag 0)
    case find_empty_in_bag(0, @backpack_slots, occupied) do
      nil ->
        # Check other bags
        Enum.find_value(bags, fn bag ->
          find_empty_in_bag(bag.bag_index, bag.slots, occupied)
        end)
      slot -> slot
    end
  end

  defp find_empty_in_bag(bag_index, slots, occupied) do
    Enum.find_value(0..(slots - 1), fn slot ->
      unless MapSet.member?(occupied, {bag_index, slot}), do: {bag_index, slot}
    end)
  end

  @spec remove_item(integer(), integer(), integer(), integer()) :: {:ok, Item.t()} | {:error, term()}
  def remove_item(character_id, bag_index, slot_index, count \\ 1) do
    case get_item(character_id, bag_index, slot_index) do
      nil -> {:error, :item_not_found}
      item when item.stack_count <= count -> Repo.delete(item)
      item ->
        item |> Item.changeset(%{stack_count: item.stack_count - count}) |> Repo.update()
    end
  end

  @spec move_item(integer(), {integer(), integer()}, {integer(), integer()}) :: :ok | {:error, term()}
  def move_item(character_id, {from_bag, from_slot}, {to_bag, to_slot}) do
    source = get_item(character_id, from_bag, from_slot)
    dest = get_item(character_id, to_bag, to_slot)

    cond do
      source == nil -> {:error, :source_empty}
      dest == nil ->
        source |> Item.changeset(%{bag_index: to_bag, slot_index: to_slot}) |> Repo.update()
        :ok
      true ->
        # Swap items
        Repo.transaction(fn ->
          source |> Item.changeset(%{bag_index: -1, slot_index: -1}) |> Repo.update!()
          dest |> Item.changeset(%{bag_index: from_bag, slot_index: from_slot}) |> Repo.update!()
          source |> Item.changeset(%{bag_index: to_bag, slot_index: to_slot}) |> Repo.update!()
        end)
        :ok
    end
  end
end
```

---

## Task 21-25: Inventory Packets

**Files to create:**
- `client_move_item.ex` - Move/swap items between slots
- `client_split_stack.ex` - Split a stack
- `client_destroy_item.ex` - Destroy an item
- `server_inventory_update.ex` - Full inventory sync
- `server_item_add.ex` - Single item added
- `server_item_remove.ex` - Single item removed
- `server_item_update.ex` - Item count/durability changed

---

## Task 26-30: Equipment System

**Files:**
- Create: `apps/bezgelor_core/lib/bezgelor_core/equipment.ex`

Equipment slots (bag 0):
- 0: Head
- 1: Shoulders
- 2: Chest
- 3: Hands
- 4: Legs
- 5: Feet
- 6: Main Hand
- 7: Off Hand
- 8: Implant
- etc.

Implement equip/unequip logic with class/level requirements validation.

---

## Task 31-40: Inventory Handler and Tests

**Files:**
- Create: `apps/bezgelor_world/lib/bezgelor_world/handler/inventory_handler.ex`
- Create: `apps/bezgelor_db/test/inventory_test.exs`
- Create: `apps/bezgelor_world/test/handler/inventory_handler_test.exs`

---

# System 3: Reputation

**Goal:** Track player standing with various factions with full gameplay effects.

**Architecture Decision:** Full effects - vendor discounts, quest gating, faction-specific rewards.

## Task 41: Create Reputation Schema

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/schema/reputation.ex`

```elixir
defmodule BezgelorDb.Schema.Reputation do
  @moduledoc """
  Character reputation with a faction.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias BezgelorDb.Schema.Character

  schema "reputations" do
    belongs_to :character, Character
    field :faction_id, :integer
    field :standing, :integer, default: 0  # Raw reputation points
    timestamps()
  end

  def changeset(rep, attrs) do
    rep
    |> cast(attrs, [:character_id, :faction_id, :standing])
    |> validate_required([:character_id, :faction_id])
    |> unique_constraint([:character_id, :faction_id])
  end
end
```

---

## Task 42: Reputation Levels in BezgelorCore

**Files:**
- Create: `apps/bezgelor_core/lib/bezgelor_core/reputation.ex`

```elixir
defmodule BezgelorCore.Reputation do
  @moduledoc """
  Reputation level definitions and calculations.
  """

  @levels [
    {:hated, -42000, -6000},
    {:hostile, -6000, -3000},
    {:unfriendly, -3000, 0},
    {:neutral, 0, 3000},
    {:friendly, 3000, 9000},
    {:honored, 9000, 21000},
    {:revered, 21000, 42000},
    {:exalted, 42000, :infinity}
  ]

  @type level :: :hated | :hostile | :unfriendly | :neutral | :friendly | :honored | :revered | :exalted

  @spec standing_to_level(integer()) :: level()
  def standing_to_level(standing) do
    Enum.find_value(@levels, :neutral, fn {level, min, max} ->
      if standing >= min and (max == :infinity or standing < max), do: level
    end)
  end

  @spec level_progress(integer()) :: {level(), integer(), integer()}
  def level_progress(standing) do
    level = standing_to_level(standing)
    {_level, min, max} = Enum.find(@levels, fn {l, _, _} -> l == level end)

    current = standing - min
    needed = if max == :infinity, do: 0, else: max - min

    {level, current, needed}
  end

  @spec max_standing(), do: 42000
  def max_standing, do: 42000

  @spec min_standing(), do: -42000
  def min_standing, do: -42000

  # Gameplay Effects

  @doc "Get vendor discount percentage for reputation level."
  @spec vendor_discount(level()) :: float()
  def vendor_discount(:hated), do: 0.0
  def vendor_discount(:hostile), do: 0.0
  def vendor_discount(:unfriendly), do: 0.0
  def vendor_discount(:neutral), do: 0.0
  def vendor_discount(:friendly), do: 0.05      # 5% discount
  def vendor_discount(:honored), do: 0.10       # 10% discount
  def vendor_discount(:revered), do: 0.15       # 15% discount
  def vendor_discount(:exalted), do: 0.20       # 20% discount

  @doc "Check if player can interact with faction NPCs."
  @spec can_interact?(level()) :: boolean()
  def can_interact?(:hated), do: false
  def can_interact?(:hostile), do: false
  def can_interact?(_), do: true

  @doc "Check if player can purchase from faction vendors."
  @spec can_purchase?(level()) :: boolean()
  def can_purchase?(:hated), do: false
  def can_purchase?(:hostile), do: false
  def can_purchase?(:unfriendly), do: false
  def can_purchase?(_), do: true

  @doc "Check if reputation meets minimum level requirement."
  @spec meets_requirement?(integer(), level()) :: boolean()
  def meets_requirement?(standing, required_level) do
    current_level = standing_to_level(standing)
    level_to_index(current_level) >= level_to_index(required_level)
  end

  defp level_to_index(:hated), do: 0
  defp level_to_index(:hostile), do: 1
  defp level_to_index(:unfriendly), do: 2
  defp level_to_index(:neutral), do: 3
  defp level_to_index(:friendly), do: 4
  defp level_to_index(:honored), do: 5
  defp level_to_index(:revered), do: 6
  defp level_to_index(:exalted), do: 7
end
```

---

## Task 43: Reputation Context

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/reputation.ex`

```elixir
defmodule BezgelorDb.Reputation do
  @moduledoc """
  Reputation management context.
  """
  import Ecto.Query
  alias BezgelorDb.Repo
  alias BezgelorDb.Schema.Reputation, as: RepSchema
  alias BezgelorCore.Reputation, as: RepCore

  @spec get_reputations(integer()) :: [RepSchema.t()]
  def get_reputations(character_id) do
    RepSchema
    |> where([r], r.character_id == ^character_id)
    |> Repo.all()
  end

  @spec get_reputation(integer(), integer()) :: RepSchema.t() | nil
  def get_reputation(character_id, faction_id) do
    Repo.get_by(RepSchema, character_id: character_id, faction_id: faction_id)
  end

  @spec get_standing(integer(), integer()) :: integer()
  def get_standing(character_id, faction_id) do
    case get_reputation(character_id, faction_id) do
      nil -> 0
      rep -> rep.standing
    end
  end

  @spec modify_reputation(integer(), integer(), integer()) :: {:ok, RepSchema.t()} | {:error, term()}
  def modify_reputation(character_id, faction_id, delta) do
    case get_reputation(character_id, faction_id) do
      nil ->
        %RepSchema{}
        |> RepSchema.changeset(%{
          character_id: character_id,
          faction_id: faction_id,
          standing: clamp(delta)
        })
        |> Repo.insert()

      rep ->
        new_standing = clamp(rep.standing + delta)
        rep |> RepSchema.changeset(%{standing: new_standing}) |> Repo.update()
    end
  end

  defp clamp(value) do
    value
    |> max(RepCore.min_standing())
    |> min(RepCore.max_standing())
  end
end
```

---

## Task 44: Faction Data in BezgelorData

**Files:**
- Create: `apps/bezgelor_data/priv/data/factions.json`

```json
{
  "factions": [
    {"id": 1, "name": "Exiles", "description": "The rebel alliance"},
    {"id": 2, "name": "Dominion", "description": "The galactic empire"},
    {"id": 100, "name": "Protostar", "description": "Corporate entity"}
  ]
}
```

---

## Task 45-52: Reputation Packets, Handler, Migration, Tests

Similar pattern - Create migration, packets (ServerReputationList, ServerReputationUpdate), handler, and tests.

---

# System 4: Quests

**Goal:** Full quest system with objectives, rewards, and progression tracking.

**Architecture Decision:** Hybrid storage - JSON blob for current objective progress (fast reads), normalized table for completion history (efficient queries).

## Task 53: Quest Schema

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/schema/quest.ex`

```elixir
defmodule BezgelorDb.Schema.Quest do
  @moduledoc """
  A quest in a character's log.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias BezgelorDb.Schema.Character

  @quest_states [:available, :accepted, :completed, :failed, :turned_in]

  schema "character_quests" do
    belongs_to :character, Character
    field :quest_id, :integer
    field :state, Ecto.Enum, values: @quest_states, default: :accepted
    field :objectives_progress, :map, default: %{}  # %{objective_id => count}
    field :accepted_at, :utc_datetime
    field :completed_at, :utc_datetime
    timestamps()
  end

  def changeset(quest, attrs) do
    quest
    |> cast(attrs, [:character_id, :quest_id, :state, :objectives_progress, :accepted_at, :completed_at])
    |> validate_required([:character_id, :quest_id, :state])
    |> unique_constraint([:character_id, :quest_id])
  end
end
```

---

## Task 54: Quest Definition in BezgelorData

**Files:**
- Create: `apps/bezgelor_data/priv/data/quests.json`

```json
{
  "quests": [
    {
      "id": 1,
      "name": "Training Day",
      "description": "Defeat training dummies to prove your worth.",
      "level": 1,
      "zone_id": 1,
      "quest_giver_id": 1000,
      "quest_ender_id": 1000,
      "prerequisites": [],
      "objectives": [
        {"id": 1, "type": "kill", "target_id": 1, "count": 3, "description": "Kill Training Dummies"}
      ],
      "rewards": {
        "xp": 100,
        "money": 50,
        "items": [{"item_id": 1, "count": 1}],
        "reputation": [{"faction_id": 1, "amount": 100}]
      }
    }
  ]
}
```

---

## Task 55: Quest Core Logic

**Files:**
- Create: `apps/bezgelor_core/lib/bezgelor_core/quest.ex`

```elixir
defmodule BezgelorCore.Quest do
  @moduledoc """
  Quest logic and definitions.
  """
  alias BezgelorData

  @type objective_type :: :kill | :collect | :interact | :explore | :escort

  @spec get(integer()) :: map() | nil
  def get(quest_id) do
    BezgelorData.get_quest(quest_id)
  end

  @spec check_prerequisites(integer(), MapSet.t()) :: boolean()
  def check_prerequisites(quest_id, completed_quests) do
    case get(quest_id) do
      nil -> false
      quest ->
        prereqs = quest["prerequisites"] || []
        Enum.all?(prereqs, &MapSet.member?(completed_quests, &1))
    end
  end

  @spec objective_complete?(map(), map()) :: boolean()
  def objective_complete?(objective, progress) do
    current = Map.get(progress, to_string(objective["id"]), 0)
    current >= objective["count"]
  end

  @spec all_objectives_complete?(integer(), map()) :: boolean()
  def all_objectives_complete?(quest_id, progress) do
    case get(quest_id) do
      nil -> false
      quest ->
        Enum.all?(quest["objectives"], &objective_complete?(&1, progress))
    end
  end

  @spec update_objective(map(), integer(), integer()) :: map()
  def update_objective(progress, objective_id, delta) do
    key = to_string(objective_id)
    current = Map.get(progress, key, 0)
    Map.put(progress, key, current + delta)
  end
end
```

---

## Task 56: Quest Context

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/quests.ex`

```elixir
defmodule BezgelorDb.Quests do
  @moduledoc """
  Quest management context.
  """
  import Ecto.Query
  alias BezgelorDb.Repo
  alias BezgelorDb.Schema.Quest
  alias BezgelorCore.Quest, as: QuestCore

  @max_quests 25

  @spec get_quests(integer()) :: [Quest.t()]
  def get_quests(character_id) do
    Quest
    |> where([q], q.character_id == ^character_id)
    |> where([q], q.state in [:accepted, :completed])
    |> Repo.all()
  end

  @spec get_completed_quest_ids(integer()) :: MapSet.t()
  def get_completed_quest_ids(character_id) do
    Quest
    |> where([q], q.character_id == ^character_id and q.state == :turned_in)
    |> select([q], q.quest_id)
    |> Repo.all()
    |> MapSet.new()
  end

  @spec accept_quest(integer(), integer()) :: {:ok, Quest.t()} | {:error, term()}
  def accept_quest(character_id, quest_id) do
    quest_def = QuestCore.get(quest_id)
    current_count = Repo.aggregate(
      from(q in Quest, where: q.character_id == ^character_id and q.state == :accepted),
      :count
    )
    completed = get_completed_quest_ids(character_id)

    cond do
      quest_def == nil -> {:error, :quest_not_found}
      current_count >= @max_quests -> {:error, :quest_log_full}
      not QuestCore.check_prerequisites(quest_id, completed) -> {:error, :prerequisites_not_met}
      has_quest?(character_id, quest_id) -> {:error, :already_have_quest}
      true ->
        %Quest{}
        |> Quest.changeset(%{
          character_id: character_id,
          quest_id: quest_id,
          state: :accepted,
          accepted_at: DateTime.utc_now()
        })
        |> Repo.insert()
    end
  end

  @spec update_progress(integer(), integer(), integer(), integer()) :: {:ok, Quest.t()} | {:error, term()}
  def update_progress(character_id, quest_id, objective_id, delta) do
    case get_quest(character_id, quest_id) do
      nil -> {:error, :quest_not_found}
      quest when quest.state != :accepted -> {:error, :quest_not_active}
      quest ->
        new_progress = QuestCore.update_objective(quest.objectives_progress, objective_id, delta)

        new_state = if QuestCore.all_objectives_complete?(quest_id, new_progress) do
          :completed
        else
          :accepted
        end

        quest
        |> Quest.changeset(%{objectives_progress: new_progress, state: new_state})
        |> Repo.update()
    end
  end

  @spec turn_in_quest(integer(), integer()) :: {:ok, map()} | {:error, term()}
  def turn_in_quest(character_id, quest_id) do
    case get_quest(character_id, quest_id) do
      nil -> {:error, :quest_not_found}
      quest when quest.state != :completed -> {:error, :quest_not_complete}
      quest ->
        quest_def = QuestCore.get(quest_id)
        rewards = quest_def["rewards"]

        {:ok, _} = quest
        |> Quest.changeset(%{state: :turned_in, completed_at: DateTime.utc_now()})
        |> Repo.update()

        {:ok, rewards}
    end
  end

  @spec abandon_quest(integer(), integer()) :: :ok | {:error, term()}
  def abandon_quest(character_id, quest_id) do
    case get_quest(character_id, quest_id) do
      nil -> {:error, :quest_not_found}
      quest when quest.state == :turned_in -> {:error, :already_completed}
      quest -> Repo.delete(quest) && :ok
    end
  end

  defp get_quest(character_id, quest_id) do
    Repo.get_by(Quest, character_id: character_id, quest_id: quest_id)
  end

  defp has_quest?(character_id, quest_id) do
    Repo.exists?(from q in Quest, where: q.character_id == ^character_id and q.quest_id == ^quest_id)
  end
end
```

---

## Task 57-65: Quest Packets

**Files to create:**
- `client_accept_quest.ex`
- `client_abandon_quest.ex`
- `client_turn_in_quest.ex`
- `server_quest_log.ex` - Full quest list
- `server_quest_add.ex`
- `server_quest_update.ex` - Objective progress
- `server_quest_complete.ex`
- `server_quest_removed.ex`
- `server_quest_rewards.ex`

---

## Task 66-75: Quest Handler and Event Integration

**Files:**
- Create: `apps/bezgelor_world/lib/bezgelor_world/handler/quest_handler.ex`
- Create: `apps/bezgelor_world/lib/bezgelor_world/quest_tracker.ex`

QuestTracker listens for game events (creature kills, item pickups) and updates quest progress.

```elixir
defmodule BezgelorWorld.QuestTracker do
  @moduledoc """
  Tracks game events and updates quest progress.
  """
  use GenServer

  alias BezgelorDb.Quests
  alias BezgelorCore.Quest

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Called when a creature is killed by a player."
  def on_creature_kill(character_id, creature_id) do
    GenServer.cast(__MODULE__, {:creature_kill, character_id, creature_id})
  end

  @doc "Called when a player picks up an item."
  def on_item_pickup(character_id, item_id, count) do
    GenServer.cast(__MODULE__, {:item_pickup, character_id, item_id, count})
  end

  @impl true
  def handle_cast({:creature_kill, character_id, creature_id}, state) do
    # Find quests with kill objectives for this creature
    quests = Quests.get_quests(character_id)

    for quest <- quests do
      quest_def = Quest.get(quest.quest_id)
      if quest_def do
        for obj <- quest_def["objectives"] do
          if obj["type"] == "kill" and obj["target_id"] == creature_id do
            Quests.update_progress(character_id, quest.quest_id, obj["id"], 1)
          end
        end
      end
    end

    {:noreply, state}
  end
end
```

---

## Task 76-85: Quest Migration and Tests

Create migration, comprehensive tests for quest acceptance, progress, completion, rewards.

---

# System 5: Achievements

**Goal:** Track player achievements with real-time event-driven tracking via PubSub.

**Architecture Decision:** Real-time PubSub events trigger achievement checks immediately.

## Task 86: Achievement Schema

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/schema/achievement.ex`

```elixir
defmodule BezgelorDb.Schema.Achievement do
  @moduledoc """
  A character's progress/completion of an achievement.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias BezgelorDb.Schema.Character

  schema "character_achievements" do
    belongs_to :character, Character
    field :achievement_id, :integer
    field :progress, :map, default: %{}  # %{criteria_id => count}
    field :completed_at, :utc_datetime
    timestamps()
  end

  def changeset(achievement, attrs) do
    achievement
    |> cast(attrs, [:character_id, :achievement_id, :progress, :completed_at])
    |> validate_required([:character_id, :achievement_id])
    |> unique_constraint([:character_id, :achievement_id])
  end
end
```

---

## Task 87: Achievement Migration

**Files:**
- Create: `apps/bezgelor_db/priv/repo/migrations/TIMESTAMP_create_achievements.exs`

```elixir
defmodule BezgelorDb.Repo.Migrations.CreateAchievements do
  use Ecto.Migration

  def change do
    create table(:character_achievements) do
      add :character_id, references(:characters, on_delete: :delete_all), null: false
      add :achievement_id, :integer, null: false
      add :progress, :map, default: %{}
      add :completed_at, :utc_datetime
      timestamps()
    end

    create unique_index(:character_achievements, [:character_id, :achievement_id])
    create index(:character_achievements, [:achievement_id])
  end
end
```

---

## Task 88: Achievement Data in BezgelorData

**Files:**
- Create: `apps/bezgelor_data/priv/data/achievements.json`

```json
{
  "achievements": [
    {
      "id": 1,
      "name": "First Blood",
      "description": "Kill your first creature",
      "category": "combat",
      "points": 5,
      "criteria": [
        {"id": 1, "type": "kill_creature", "target_id": null, "count": 1}
      ],
      "rewards": {
        "title_id": null,
        "item_id": null
      }
    },
    {
      "id": 2,
      "name": "Slayer",
      "description": "Kill 100 creatures",
      "category": "combat",
      "points": 10,
      "criteria": [
        {"id": 1, "type": "kill_creature", "target_id": null, "count": 100}
      ]
    },
    {
      "id": 10,
      "name": "Quest Master",
      "description": "Complete 50 quests",
      "category": "questing",
      "points": 25,
      "criteria": [
        {"id": 1, "type": "quest_complete", "target_id": null, "count": 50}
      ]
    },
    {
      "id": 20,
      "name": "Level 10",
      "description": "Reach level 10",
      "category": "leveling",
      "points": 10,
      "criteria": [
        {"id": 1, "type": "level_reached", "target_id": null, "count": 10}
      ]
    }
  ]
}
```

---

## Task 89: Achievement Core Logic

**Files:**
- Create: `apps/bezgelor_core/lib/bezgelor_core/achievement.ex`

```elixir
defmodule BezgelorCore.Achievement do
  @moduledoc """
  Achievement definitions and criteria checking.
  """
  alias BezgelorData

  @type criteria_type :: :kill_creature | :quest_complete | :level_reached | :exploration | :collect_item | :reputation_reached

  @spec get(integer()) :: map() | nil
  def get(achievement_id) do
    BezgelorData.get_achievement(achievement_id)
  end

  @spec criteria_complete?(map(), map()) :: boolean()
  def criteria_complete?(criteria, progress) do
    current = Map.get(progress, to_string(criteria["id"]), 0)
    current >= criteria["count"]
  end

  @spec all_criteria_complete?(integer(), map()) :: boolean()
  def all_criteria_complete?(achievement_id, progress) do
    case get(achievement_id) do
      nil -> false
      achievement ->
        Enum.all?(achievement["criteria"], &criteria_complete?(&1, progress))
    end
  end

  @spec update_progress(map(), integer(), integer()) :: map()
  def update_progress(progress, criteria_id, delta) do
    key = to_string(criteria_id)
    current = Map.get(progress, key, 0)
    Map.put(progress, key, current + delta)
  end

  @spec get_achievements_by_criteria_type(criteria_type()) :: [map()]
  def get_achievements_by_criteria_type(type) do
    type_str = Atom.to_string(type)
    BezgelorData.find_achievements(fn achievement ->
      Enum.any?(achievement["criteria"], fn c -> c["type"] == type_str end)
    end)
  end
end
```

---

## Task 90: Achievement Context

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/achievements.ex`

```elixir
defmodule BezgelorDb.Achievements do
  @moduledoc """
  Achievement management context.
  """
  import Ecto.Query
  alias BezgelorDb.Repo
  alias BezgelorDb.Schema.Achievement
  alias BezgelorCore.Achievement, as: AchievementCore

  @spec get_achievements(integer()) :: [Achievement.t()]
  def get_achievements(character_id) do
    Achievement
    |> where([a], a.character_id == ^character_id)
    |> Repo.all()
  end

  @spec get_completed_achievements(integer()) :: [Achievement.t()]
  def get_completed_achievements(character_id) do
    Achievement
    |> where([a], a.character_id == ^character_id and not is_nil(a.completed_at))
    |> Repo.all()
  end

  @spec get_achievement(integer(), integer()) :: Achievement.t() | nil
  def get_achievement(character_id, achievement_id) do
    Repo.get_by(Achievement, character_id: character_id, achievement_id: achievement_id)
  end

  @spec update_progress(integer(), integer(), integer(), integer()) :: {:ok, Achievement.t(), boolean()} | {:error, term()}
  def update_progress(character_id, achievement_id, criteria_id, delta) do
    achievement = get_or_create_achievement(character_id, achievement_id)

    new_progress = AchievementCore.update_progress(achievement.progress, criteria_id, delta)
    newly_completed = is_nil(achievement.completed_at) and
                      AchievementCore.all_criteria_complete?(achievement_id, new_progress)

    attrs = %{progress: new_progress}
    attrs = if newly_completed, do: Map.put(attrs, :completed_at, DateTime.utc_now()), else: attrs

    case achievement |> Achievement.changeset(attrs) |> Repo.update() do
      {:ok, updated} -> {:ok, updated, newly_completed}
      error -> error
    end
  end

  defp get_or_create_achievement(character_id, achievement_id) do
    case get_achievement(character_id, achievement_id) do
      nil ->
        {:ok, achievement} = %Achievement{}
        |> Achievement.changeset(%{character_id: character_id, achievement_id: achievement_id})
        |> Repo.insert()
        achievement
      achievement -> achievement
    end
  end
end
```

---

## Task 91: Achievement Event Bus (PubSub)

**Files:**
- Create: `apps/bezgelor_world/lib/bezgelor_world/achievement_tracker.ex`

```elixir
defmodule BezgelorWorld.AchievementTracker do
  @moduledoc """
  Real-time achievement tracking via PubSub events.

  Subscribes to game events and immediately checks/updates achievements.
  """
  use GenServer
  require Logger

  alias BezgelorDb.Achievements
  alias BezgelorCore.Achievement
  alias BezgelorWorld.CombatBroadcaster

  @pubsub BezgelorWorld.PubSub
  @topics [:creature_kill, :quest_complete, :level_up, :item_collect, :reputation_change]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # Public API for triggering events

  @doc "Broadcast a creature kill event."
  def creature_killed(character_id, creature_id) do
    Phoenix.PubSub.broadcast(@pubsub, "achievements", {:creature_kill, character_id, creature_id})
  end

  @doc "Broadcast a quest completion event."
  def quest_completed(character_id, quest_id) do
    Phoenix.PubSub.broadcast(@pubsub, "achievements", {:quest_complete, character_id, quest_id})
  end

  @doc "Broadcast a level up event."
  def level_reached(character_id, level) do
    Phoenix.PubSub.broadcast(@pubsub, "achievements", {:level_up, character_id, level})
  end

  @doc "Broadcast an item collection event."
  def item_collected(character_id, item_id, count) do
    Phoenix.PubSub.broadcast(@pubsub, "achievements", {:item_collect, character_id, item_id, count})
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(@pubsub, "achievements")
    {:ok, %{}}
  end

  @impl true
  def handle_info({:creature_kill, character_id, creature_id}, state) do
    check_achievements(character_id, :kill_creature, creature_id, 1)
    {:noreply, state}
  end

  @impl true
  def handle_info({:quest_complete, character_id, quest_id}, state) do
    check_achievements(character_id, :quest_complete, quest_id, 1)
    {:noreply, state}
  end

  @impl true
  def handle_info({:level_up, character_id, level}, state) do
    check_achievements(character_id, :level_reached, nil, level)
    {:noreply, state}
  end

  @impl true
  def handle_info({:item_collect, character_id, item_id, count}, state) do
    check_achievements(character_id, :collect_item, item_id, count)
    {:noreply, state}
  end

  # Private helpers

  defp check_achievements(character_id, criteria_type, target_id, delta) do
    achievements = Achievement.get_achievements_by_criteria_type(criteria_type)

    for achievement <- achievements do
      for criteria <- achievement["criteria"] do
        if matches_criteria?(criteria, criteria_type, target_id) do
          case Achievements.update_progress(character_id, achievement["id"], criteria["id"], delta) do
            {:ok, _updated, true} ->
              Logger.info("Character #{character_id} earned achievement: #{achievement["name"]}")
              send_achievement_earned(character_id, achievement)
            {:ok, _updated, false} ->
              :ok
            {:error, reason} ->
              Logger.error("Failed to update achievement progress: #{inspect(reason)}")
          end
        end
      end
    end
  end

  defp matches_criteria?(criteria, type, target_id) do
    criteria["type"] == Atom.to_string(type) and
    (criteria["target_id"] == nil or criteria["target_id"] == target_id)
  end

  defp send_achievement_earned(character_id, achievement) do
    # TODO: Send achievement packet to player
    :ok
  end
end
```

---

## Task 92-95: Achievement Packets

**Files:**
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_achievement_list.ex`

```elixir
defmodule BezgelorProtocol.Packets.World.ServerAchievementList do
  @moduledoc """
  Full achievement list sent to client.
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct achievements: []

  @impl true
  def opcode, do: :server_achievement_list

  @impl true
  def write(%__MODULE__{achievements: achievements}, writer) do
    writer = PacketWriter.write_uint32(writer, length(achievements))

    writer = Enum.reduce(achievements, writer, fn ach, w ->
      w
      |> PacketWriter.write_uint32(ach.achievement_id)
      |> PacketWriter.write_byte(if(ach.completed_at, do: 1, else: 0))
      |> PacketWriter.write_uint64(ach.completed_at && DateTime.to_unix(ach.completed_at) || 0)
      |> write_progress(ach.progress)
    end)

    {:ok, writer}
  end

  defp write_progress(writer, progress) do
    entries = Map.to_list(progress)
    writer = PacketWriter.write_uint32(writer, length(entries))

    Enum.reduce(entries, writer, fn {criteria_id, count}, w ->
      w
      |> PacketWriter.write_uint32(String.to_integer(criteria_id))
      |> PacketWriter.write_uint32(count)
    end)
  end
end
```

**Files:**
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_achievement_earned.ex`

```elixir
defmodule BezgelorProtocol.Packets.World.ServerAchievementEarned do
  @moduledoc """
  Achievement earned notification.
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:achievement_id, :points, :earned_at]

  @impl true
  def opcode, do: :server_achievement_earned

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_uint32(packet.achievement_id)
      |> PacketWriter.write_uint32(packet.points)
      |> PacketWriter.write_uint64(DateTime.to_unix(packet.earned_at))

    {:ok, writer}
  end
end
```

---

## Task 96-105: Achievement Handler and Tests

**Files:**
- Create: `apps/bezgelor_world/lib/bezgelor_world/handler/achievement_handler.ex`
- Create: `apps/bezgelor_db/test/achievements_test.exs`
- Create: `apps/bezgelor_world/test/achievement_tracker_test.exs`

---

# System 6: Paths

**Goal:** Implement WildStar's path system (Soldier, Settler, Scientist, Explorer).

**Architecture Decision:** Quest wrapper - path missions wrap quests but add path-specific tracking layer.

## Task 106: Path Schema

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/schema/character_path.ex`

```elixir
defmodule BezgelorDb.Schema.CharacterPath do
  @moduledoc """
  A character's path progression.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias BezgelorDb.Schema.Character

  @path_types [:soldier, :settler, :scientist, :explorer]

  schema "character_paths" do
    belongs_to :character, Character
    field :path_type, Ecto.Enum, values: @path_types
    field :level, :integer, default: 1
    field :xp, :integer, default: 0
    field :abilities_unlocked, {:array, :integer}, default: []
    timestamps()
  end

  def changeset(path, attrs) do
    path
    |> cast(attrs, [:character_id, :path_type, :level, :xp, :abilities_unlocked])
    |> validate_required([:character_id, :path_type])
    |> validate_number(:level, greater_than_or_equal_to: 1, less_than_or_equal_to: 30)
    |> unique_constraint([:character_id, :path_type])
  end
end
```

---

## Task 107: Path Mission Schema (Quest Wrapper)

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/schema/path_mission.ex`

```elixir
defmodule BezgelorDb.Schema.PathMission do
  @moduledoc """
  Path mission - wraps a quest with path-specific tracking.

  Path missions are quests that grant path XP instead of regular XP.
  The underlying quest handles objectives; this tracks path-specific progress.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias BezgelorDb.Schema.Character

  schema "character_path_missions" do
    belongs_to :character, Character
    field :mission_id, :integer       # Path mission definition ID
    field :quest_id, :integer         # Underlying quest ID
    field :path_type, Ecto.Enum, values: [:soldier, :settler, :scientist, :explorer]
    field :state, Ecto.Enum, values: [:active, :completed], default: :active
    field :completed_at, :utc_datetime
    timestamps()
  end

  def changeset(mission, attrs) do
    mission
    |> cast(attrs, [:character_id, :mission_id, :quest_id, :path_type, :state, :completed_at])
    |> validate_required([:character_id, :mission_id, :quest_id, :path_type])
    |> unique_constraint([:character_id, :mission_id])
  end
end
```

---

## Task 108: Path Migration

**Files:**
- Create: `apps/bezgelor_db/priv/repo/migrations/TIMESTAMP_create_paths.exs`

```elixir
defmodule BezgelorDb.Repo.Migrations.CreatePaths do
  use Ecto.Migration

  def change do
    create table(:character_paths) do
      add :character_id, references(:characters, on_delete: :delete_all), null: false
      add :path_type, :string, null: false
      add :level, :integer, default: 1
      add :xp, :integer, default: 0
      add :abilities_unlocked, {:array, :integer}, default: []
      timestamps()
    end

    create unique_index(:character_paths, [:character_id, :path_type])

    create table(:character_path_missions) do
      add :character_id, references(:characters, on_delete: :delete_all), null: false
      add :mission_id, :integer, null: false
      add :quest_id, :integer, null: false
      add :path_type, :string, null: false
      add :state, :string, default: "active"
      add :completed_at, :utc_datetime
      timestamps()
    end

    create unique_index(:character_path_missions, [:character_id, :mission_id])
    create index(:character_path_missions, [:character_id, :path_type])
  end
end
```

---

## Task 109: Path Data in BezgelorData

**Files:**
- Create: `apps/bezgelor_data/priv/data/paths.json`

```json
{
  "path_levels": [
    {"level": 1, "xp_required": 0},
    {"level": 2, "xp_required": 1000},
    {"level": 3, "xp_required": 3000},
    {"level": 4, "xp_required": 6000},
    {"level": 5, "xp_required": 10000}
  ],
  "path_abilities": {
    "soldier": [
      {"id": 1, "name": "Combat Supply Drop", "unlock_level": 1},
      {"id": 2, "name": "Backup", "unlock_level": 5},
      {"id": 3, "name": "Artillery Strike", "unlock_level": 10}
    ],
    "settler": [
      {"id": 10, "name": "Vendbot", "unlock_level": 1},
      {"id": 11, "name": "Mail Depot", "unlock_level": 5}
    ],
    "scientist": [
      {"id": 20, "name": "Holographic Distraction", "unlock_level": 1},
      {"id": 21, "name": "Summon Group", "unlock_level": 5}
    ],
    "explorer": [
      {"id": 30, "name": "Explorer's Safe Fall", "unlock_level": 1},
      {"id": 31, "name": "Air Brakes", "unlock_level": 5}
    ]
  },
  "path_missions": [
    {
      "id": 1,
      "name": "Defend the Camp",
      "path_type": "soldier",
      "quest_id": 1001,
      "xp_reward": 500,
      "zone_id": 1
    },
    {
      "id": 10,
      "name": "Build the Outpost",
      "path_type": "settler",
      "quest_id": 1010,
      "xp_reward": 500,
      "zone_id": 1
    }
  ]
}
```

---

## Task 110: Path Core Logic

**Files:**
- Create: `apps/bezgelor_core/lib/bezgelor_core/path.ex`

```elixir
defmodule BezgelorCore.Path do
  @moduledoc """
  Path system logic.
  """
  alias BezgelorData

  @max_level 30

  @spec get_mission(integer()) :: map() | nil
  def get_mission(mission_id) do
    BezgelorData.get_path_mission(mission_id)
  end

  @spec get_abilities(atom()) :: [map()]
  def get_abilities(path_type) do
    BezgelorData.get_path_abilities(path_type)
  end

  @spec xp_for_level(integer()) :: integer()
  def xp_for_level(level) when level >= 1 do
    levels = BezgelorData.get_path_levels()
    case Enum.find(levels, fn l -> l["level"] == level end) do
      nil -> 999_999_999
      level_data -> level_data["xp_required"]
    end
  end

  @spec level_from_xp(integer()) :: integer()
  def level_from_xp(xp) do
    levels = BezgelorData.get_path_levels() |> Enum.sort_by(& &1["level"], :desc)

    case Enum.find(levels, fn l -> xp >= l["xp_required"] end) do
      nil -> 1
      level_data -> min(level_data["level"], @max_level)
    end
  end

  @spec abilities_at_level(atom(), integer()) :: [integer()]
  def abilities_at_level(path_type, level) do
    get_abilities(path_type)
    |> Enum.filter(fn a -> a["unlock_level"] <= level end)
    |> Enum.map(& &1["id"])
  end
end
```

---

## Task 111: Path Context

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/paths.ex`

```elixir
defmodule BezgelorDb.Paths do
  @moduledoc """
  Path management context.
  """
  import Ecto.Query
  alias BezgelorDb.Repo
  alias BezgelorDb.Schema.{CharacterPath, PathMission}
  alias BezgelorCore.Path

  @spec get_path(integer(), atom()) :: CharacterPath.t() | nil
  def get_path(character_id, path_type) do
    Repo.get_by(CharacterPath, character_id: character_id, path_type: path_type)
  end

  @spec get_or_create_path(integer(), atom()) :: CharacterPath.t()
  def get_or_create_path(character_id, path_type) do
    case get_path(character_id, path_type) do
      nil ->
        {:ok, path} = %CharacterPath{}
        |> CharacterPath.changeset(%{character_id: character_id, path_type: path_type})
        |> Repo.insert()
        path
      path -> path
    end
  end

  @spec add_path_xp(integer(), atom(), integer()) :: {:ok, CharacterPath.t(), boolean()} | {:error, term()}
  def add_path_xp(character_id, path_type, xp_amount) do
    path = get_or_create_path(character_id, path_type)
    new_xp = path.xp + xp_amount
    old_level = path.level
    new_level = Path.level_from_xp(new_xp)
    leveled_up = new_level > old_level

    new_abilities = if leveled_up do
      Path.abilities_at_level(path_type, new_level)
    else
      path.abilities_unlocked
    end

    attrs = %{xp: new_xp, level: new_level, abilities_unlocked: new_abilities}

    case path |> CharacterPath.changeset(attrs) |> Repo.update() do
      {:ok, updated} -> {:ok, updated, leveled_up}
      error -> error
    end
  end

  @spec start_mission(integer(), integer()) :: {:ok, PathMission.t()} | {:error, term()}
  def start_mission(character_id, mission_id) do
    mission_def = Path.get_mission(mission_id)

    cond do
      mission_def == nil -> {:error, :mission_not_found}
      has_mission?(character_id, mission_id) -> {:error, :already_have_mission}
      true ->
        %PathMission{}
        |> PathMission.changeset(%{
          character_id: character_id,
          mission_id: mission_id,
          quest_id: mission_def["quest_id"],
          path_type: String.to_existing_atom(mission_def["path_type"])
        })
        |> Repo.insert()
    end
  end

  @spec complete_mission(integer(), integer()) :: {:ok, map()} | {:error, term()}
  def complete_mission(character_id, mission_id) do
    case get_mission(character_id, mission_id) do
      nil -> {:error, :mission_not_found}
      mission when mission.state == :completed -> {:error, :already_completed}
      mission ->
        mission_def = Path.get_mission(mission_id)
        xp_reward = mission_def["xp_reward"] || 0

        {:ok, _} = mission
        |> PathMission.changeset(%{state: :completed, completed_at: DateTime.utc_now()})
        |> Repo.update()

        {:ok, _path, leveled} = add_path_xp(character_id, mission.path_type, xp_reward)

        {:ok, %{xp_reward: xp_reward, leveled_up: leveled}}
    end
  end

  defp get_mission(character_id, mission_id) do
    Repo.get_by(PathMission, character_id: character_id, mission_id: mission_id)
  end

  defp has_mission?(character_id, mission_id) do
    Repo.exists?(from m in PathMission, where: m.character_id == ^character_id and m.mission_id == ^mission_id)
  end
end
```

---

## Task 112-115: Path Packets

**Files:**
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_path_info.ex`

```elixir
defmodule BezgelorProtocol.Packets.World.ServerPathInfo do
  @moduledoc """
  Path progression info sent to client.
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:path_type, :level, :xp, :xp_to_next, :abilities]

  @impl true
  def opcode, do: :server_path_info

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_byte(path_type_to_int(packet.path_type))
      |> PacketWriter.write_byte(packet.level)
      |> PacketWriter.write_uint32(packet.xp)
      |> PacketWriter.write_uint32(packet.xp_to_next)
      |> PacketWriter.write_uint32(length(packet.abilities))

    writer = Enum.reduce(packet.abilities, writer, fn ability_id, w ->
      PacketWriter.write_uint32(w, ability_id)
    end)

    {:ok, writer}
  end

  defp path_type_to_int(:soldier), do: 0
  defp path_type_to_int(:settler), do: 1
  defp path_type_to_int(:scientist), do: 2
  defp path_type_to_int(:explorer), do: 3
end
```

**Files:**
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_path_level_up.ex`

```elixir
defmodule BezgelorProtocol.Packets.World.ServerPathLevelUp do
  @moduledoc """
  Path level up notification.
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:path_type, :new_level, :new_abilities]

  @impl true
  def opcode, do: :server_path_level_up

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_byte(path_type_to_int(packet.path_type))
      |> PacketWriter.write_byte(packet.new_level)
      |> PacketWriter.write_uint32(length(packet.new_abilities))

    writer = Enum.reduce(packet.new_abilities, writer, fn ability_id, w ->
      PacketWriter.write_uint32(w, ability_id)
    end)

    {:ok, writer}
  end

  defp path_type_to_int(:soldier), do: 0
  defp path_type_to_int(:settler), do: 1
  defp path_type_to_int(:scientist), do: 2
  defp path_type_to_int(:explorer), do: 3
end
```

---

## Task 116-125: Path Handler and Tests

**Files:**
- Create: `apps/bezgelor_world/lib/bezgelor_world/handler/path_handler.ex`
- Create: `apps/bezgelor_db/test/paths_test.exs`
- Create: `apps/bezgelor_world/test/handler/path_handler_test.exs`

---

# System 7: Guilds

**Goal:** Full guild system with ranks, permissions, and guild bank.

**Architecture Decision:** Full system with bank + permissions matrix from the start.

## Task 126: Guild Schema

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/schema/guild.ex`

```elixir
defmodule BezgelorDb.Schema.Guild do
  @moduledoc """
  A guild/organization.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias BezgelorDb.Schema.{Character, GuildMember, GuildRank, GuildBankTab}

  schema "guilds" do
    field :name, :string
    field :tag, :string              # Short tag (2-4 chars)
    field :motd, :string, default: ""
    field :info, :string, default: ""  # Guild info/description
    field :bank_gold, :integer, default: 0
    belongs_to :leader, Character
    has_many :members, GuildMember
    has_many :ranks, GuildRank
    has_many :bank_tabs, GuildBankTab
    timestamps()
  end

  def changeset(guild, attrs) do
    guild
    |> cast(attrs, [:name, :tag, :motd, :info, :bank_gold, :leader_id])
    |> validate_required([:name, :tag, :leader_id])
    |> validate_length(:name, min: 2, max: 24)
    |> validate_length(:tag, min: 2, max: 4)
    |> validate_length(:motd, max: 500)
    |> unique_constraint(:name)
    |> unique_constraint(:tag)
  end
end
```

---

## Task 127: Guild Member Schema

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/schema/guild_member.ex`

```elixir
defmodule BezgelorDb.Schema.GuildMember do
  @moduledoc """
  A member of a guild.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias BezgelorDb.Schema.{Character, Guild, GuildRank}

  schema "guild_members" do
    belongs_to :guild, Guild
    belongs_to :character, Character
    belongs_to :rank, GuildRank
    field :note, :string, default: ""       # Officer note
    field :public_note, :string, default: ""
    field :joined_at, :utc_datetime
    field :last_online_at, :utc_datetime
    timestamps()
  end

  def changeset(member, attrs) do
    member
    |> cast(attrs, [:guild_id, :character_id, :rank_id, :note, :public_note, :joined_at, :last_online_at])
    |> validate_required([:guild_id, :character_id, :rank_id])
    |> unique_constraint([:guild_id, :character_id])
    |> unique_constraint(:character_id)  # One guild per character
  end
end
```

---

## Task 128: Guild Rank Schema

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/schema/guild_rank.ex`

```elixir
defmodule BezgelorDb.Schema.GuildRank do
  @moduledoc """
  A rank within a guild with permissions.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias BezgelorDb.Schema.Guild

  # Permission bitmask values
  @permissions %{
    invite: 0x0001,
    kick: 0x0002,
    promote: 0x0004,
    demote: 0x0008,
    edit_motd: 0x0010,
    edit_info: 0x0020,
    edit_ranks: 0x0040,
    bank_view: 0x0080,
    bank_deposit: 0x0100,
    bank_withdraw_tab1: 0x0200,
    bank_withdraw_tab2: 0x0400,
    bank_withdraw_tab3: 0x0800,
    bank_withdraw_tab4: 0x1000,
    guild_chat: 0x2000,
    officer_chat: 0x4000
  }

  schema "guild_ranks" do
    belongs_to :guild, Guild
    field :rank_index, :integer      # 0 = GM, 1 = Officer, etc.
    field :name, :string
    field :permissions, :integer, default: 0
    field :daily_gold_limit, :integer, default: 0  # 0 = unlimited
    timestamps()
  end

  def changeset(rank, attrs) do
    rank
    |> cast(attrs, [:guild_id, :rank_index, :name, :permissions, :daily_gold_limit])
    |> validate_required([:guild_id, :rank_index, :name])
    |> validate_number(:rank_index, greater_than_or_equal_to: 0, less_than_or_equal_to: 9)
    |> unique_constraint([:guild_id, :rank_index])
  end

  def permissions_map, do: @permissions

  def has_permission?(permission_bits, permission) when is_atom(permission) do
    perm_bit = Map.get(@permissions, permission, 0)
    Bitwise.band(permission_bits, perm_bit) != 0
  end
end
```

---

## Task 129: Guild Bank Schemas

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/schema/guild_bank_tab.ex`

```elixir
defmodule BezgelorDb.Schema.GuildBankTab do
  @moduledoc """
  A tab in the guild bank.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias BezgelorDb.Schema.{Guild, GuildBankItem}

  @slots_per_tab 98

  schema "guild_bank_tabs" do
    belongs_to :guild, Guild
    field :tab_index, :integer      # 0-7
    field :name, :string, default: "Tab"
    field :icon, :string, default: ""
    has_many :items, GuildBankItem
    timestamps()
  end

  def changeset(tab, attrs) do
    tab
    |> cast(attrs, [:guild_id, :tab_index, :name, :icon])
    |> validate_required([:guild_id, :tab_index])
    |> validate_number(:tab_index, greater_than_or_equal_to: 0, less_than_or_equal_to: 7)
    |> unique_constraint([:guild_id, :tab_index])
  end

  def slots_per_tab, do: @slots_per_tab
end
```

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/schema/guild_bank_item.ex`

```elixir
defmodule BezgelorDb.Schema.GuildBankItem do
  @moduledoc """
  An item in the guild bank.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias BezgelorDb.Schema.GuildBankTab

  schema "guild_bank_items" do
    belongs_to :bank_tab, GuildBankTab
    field :slot_index, :integer
    field :item_id, :integer
    field :stack_count, :integer, default: 1
    timestamps()
  end

  def changeset(item, attrs) do
    item
    |> cast(attrs, [:bank_tab_id, :slot_index, :item_id, :stack_count])
    |> validate_required([:bank_tab_id, :slot_index, :item_id])
    |> validate_number(:stack_count, greater_than: 0)
    |> unique_constraint([:bank_tab_id, :slot_index])
  end
end
```

---

## Task 130: Guild Migration

**Files:**
- Create: `apps/bezgelor_db/priv/repo/migrations/TIMESTAMP_create_guilds.exs`

```elixir
defmodule BezgelorDb.Repo.Migrations.CreateGuilds do
  use Ecto.Migration

  def change do
    create table(:guilds) do
      add :name, :string, size: 24, null: false
      add :tag, :string, size: 4, null: false
      add :motd, :string, size: 500, default: ""
      add :info, :text, default: ""
      add :bank_gold, :bigint, default: 0
      add :leader_id, references(:characters, on_delete: :nilify_all)
      timestamps()
    end

    create unique_index(:guilds, [:name])
    create unique_index(:guilds, [:tag])

    create table(:guild_ranks) do
      add :guild_id, references(:guilds, on_delete: :delete_all), null: false
      add :rank_index, :integer, null: false
      add :name, :string, size: 32, null: false
      add :permissions, :integer, default: 0
      add :daily_gold_limit, :integer, default: 0
      timestamps()
    end

    create unique_index(:guild_ranks, [:guild_id, :rank_index])

    create table(:guild_members) do
      add :guild_id, references(:guilds, on_delete: :delete_all), null: false
      add :character_id, references(:characters, on_delete: :delete_all), null: false
      add :rank_id, references(:guild_ranks, on_delete: :restrict), null: false
      add :note, :string, size: 256, default: ""
      add :public_note, :string, size: 256, default: ""
      add :joined_at, :utc_datetime
      add :last_online_at, :utc_datetime
      timestamps()
    end

    create unique_index(:guild_members, [:character_id])
    create index(:guild_members, [:guild_id])

    create table(:guild_bank_tabs) do
      add :guild_id, references(:guilds, on_delete: :delete_all), null: false
      add :tab_index, :integer, null: false
      add :name, :string, size: 32, default: "Tab"
      add :icon, :string, default: ""
      timestamps()
    end

    create unique_index(:guild_bank_tabs, [:guild_id, :tab_index])

    create table(:guild_bank_items) do
      add :bank_tab_id, references(:guild_bank_tabs, on_delete: :delete_all), null: false
      add :slot_index, :integer, null: false
      add :item_id, :integer, null: false
      add :stack_count, :integer, default: 1
      timestamps()
    end

    create unique_index(:guild_bank_items, [:bank_tab_id, :slot_index])
  end
end
```

---

## Task 131: Guild Context

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/guilds.ex`

```elixir
defmodule BezgelorDb.Guilds do
  @moduledoc """
  Guild management context.
  """
  import Ecto.Query
  alias BezgelorDb.Repo
  alias BezgelorDb.Schema.{Guild, GuildMember, GuildRank, GuildBankTab, GuildBankItem}

  @default_ranks [
    %{rank_index: 0, name: "Guild Master", permissions: 0xFFFF},
    %{rank_index: 1, name: "Officer", permissions: 0x7FFF},
    %{rank_index: 2, name: "Veteran", permissions: 0x2180},
    %{rank_index: 3, name: "Member", permissions: 0x2080},
    %{rank_index: 4, name: "Initiate", permissions: 0x2000}
  ]

  # Guild CRUD

  @spec create_guild(integer(), String.t(), String.t()) :: {:ok, Guild.t()} | {:error, term()}
  def create_guild(leader_id, name, tag) do
    Repo.transaction(fn ->
      # Check if leader is already in a guild
      if get_member_by_character(leader_id) do
        Repo.rollback(:already_in_guild)
      end

      # Create guild
      {:ok, guild} = %Guild{}
      |> Guild.changeset(%{name: name, tag: tag, leader_id: leader_id})
      |> Repo.insert()

      # Create default ranks
      ranks = Enum.map(@default_ranks, fn rank_data ->
        {:ok, rank} = %GuildRank{}
        |> GuildRank.changeset(Map.put(rank_data, :guild_id, guild.id))
        |> Repo.insert()
        rank
      end)

      gm_rank = Enum.find(ranks, & &1.rank_index == 0)

      # Add leader as member
      {:ok, _member} = %GuildMember{}
      |> GuildMember.changeset(%{
        guild_id: guild.id,
        character_id: leader_id,
        rank_id: gm_rank.id,
        joined_at: DateTime.utc_now()
      })
      |> Repo.insert()

      # Create first bank tab
      {:ok, _tab} = %GuildBankTab{}
      |> GuildBankTab.changeset(%{guild_id: guild.id, tab_index: 0, name: "Tab 1"})
      |> Repo.insert()

      guild
    end)
  end

  @spec get_guild(integer()) :: Guild.t() | nil
  def get_guild(guild_id) do
    Repo.get(Guild, guild_id)
  end

  @spec get_guild_by_name(String.t()) :: Guild.t() | nil
  def get_guild_by_name(name) do
    Repo.get_by(Guild, name: name)
  end

  @spec disband_guild(integer(), integer()) :: :ok | {:error, term()}
  def disband_guild(guild_id, requester_id) do
    guild = get_guild(guild_id)

    cond do
      guild == nil -> {:error, :guild_not_found}
      guild.leader_id != requester_id -> {:error, :not_leader}
      true ->
        Repo.delete(guild)
        :ok
    end
  end

  # Membership

  @spec invite_member(integer(), integer(), integer()) :: {:ok, GuildMember.t()} | {:error, term()}
  def invite_member(guild_id, inviter_id, target_id) do
    with {:ok, _} <- check_permission(guild_id, inviter_id, :invite),
         nil <- get_member_by_character(target_id) do
      # Get default rank (lowest)
      rank = get_lowest_rank(guild_id)

      %GuildMember{}
      |> GuildMember.changeset(%{
        guild_id: guild_id,
        character_id: target_id,
        rank_id: rank.id,
        joined_at: DateTime.utc_now()
      })
      |> Repo.insert()
    else
      {:error, _} = err -> err
      _member -> {:error, :already_in_guild}
    end
  end

  @spec kick_member(integer(), integer(), integer()) :: :ok | {:error, term()}
  def kick_member(guild_id, kicker_id, target_id) do
    with {:ok, _} <- check_permission(guild_id, kicker_id, :kick),
         %{} = member <- get_member(guild_id, target_id),
         :ok <- check_can_act_on(guild_id, kicker_id, target_id) do
      Repo.delete(member)
      :ok
    else
      nil -> {:error, :member_not_found}
      {:error, _} = err -> err
    end
  end

  @spec leave_guild(integer()) :: :ok | {:error, term()}
  def leave_guild(character_id) do
    case get_member_by_character(character_id) do
      nil -> {:error, :not_in_guild}
      member ->
        guild = get_guild(member.guild_id)
        if guild.leader_id == character_id do
          {:error, :leader_cannot_leave}
        else
          Repo.delete(member)
          :ok
        end
    end
  end

  @spec get_members(integer()) :: [GuildMember.t()]
  def get_members(guild_id) do
    GuildMember
    |> where([m], m.guild_id == ^guild_id)
    |> preload([:character, :rank])
    |> Repo.all()
  end

  @spec get_member(integer(), integer()) :: GuildMember.t() | nil
  def get_member(guild_id, character_id) do
    Repo.get_by(GuildMember, guild_id: guild_id, character_id: character_id)
  end

  @spec get_member_by_character(integer()) :: GuildMember.t() | nil
  def get_member_by_character(character_id) do
    GuildMember
    |> where([m], m.character_id == ^character_id)
    |> preload(:guild)
    |> Repo.one()
  end

  # Rank management

  @spec promote_member(integer(), integer(), integer()) :: {:ok, GuildMember.t()} | {:error, term()}
  def promote_member(guild_id, promoter_id, target_id) do
    with {:ok, _} <- check_permission(guild_id, promoter_id, :promote),
         %{} = member <- get_member(guild_id, target_id),
         :ok <- check_can_act_on(guild_id, promoter_id, target_id) do
      next_rank = get_next_higher_rank(guild_id, member.rank.rank_index)

      if next_rank do
        member |> GuildMember.changeset(%{rank_id: next_rank.id}) |> Repo.update()
      else
        {:error, :already_max_rank}
      end
    else
      nil -> {:error, :member_not_found}
      {:error, _} = err -> err
    end
  end

  @spec demote_member(integer(), integer(), integer()) :: {:ok, GuildMember.t()} | {:error, term()}
  def demote_member(guild_id, demoter_id, target_id) do
    with {:ok, _} <- check_permission(guild_id, demoter_id, :demote),
         %{} = member <- get_member(guild_id, target_id),
         :ok <- check_can_act_on(guild_id, demoter_id, target_id) do
      next_rank = get_next_lower_rank(guild_id, member.rank.rank_index)

      if next_rank do
        member |> GuildMember.changeset(%{rank_id: next_rank.id}) |> Repo.update()
      else
        {:error, :already_lowest_rank}
      end
    else
      nil -> {:error, :member_not_found}
      {:error, _} = err -> err
    end
  end

  # Bank operations

  @spec deposit_item(integer(), integer(), integer(), integer(), integer()) :: {:ok, GuildBankItem.t()} | {:error, term()}
  def deposit_item(guild_id, character_id, tab_index, item_id, count) do
    with {:ok, _} <- check_permission(guild_id, character_id, :bank_deposit),
         {:ok, tab} <- get_bank_tab(guild_id, tab_index),
         {:ok, slot} <- find_empty_bank_slot(tab.id) do
      %GuildBankItem{}
      |> GuildBankItem.changeset(%{bank_tab_id: tab.id, slot_index: slot, item_id: item_id, stack_count: count})
      |> Repo.insert()
    end
  end

  @spec withdraw_item(integer(), integer(), integer(), integer()) :: {:ok, GuildBankItem.t()} | {:error, term()}
  def withdraw_item(guild_id, character_id, tab_index, slot_index) do
    permission = String.to_existing_atom("bank_withdraw_tab#{tab_index + 1}")

    with {:ok, _} <- check_permission(guild_id, character_id, permission),
         {:ok, tab} <- get_bank_tab(guild_id, tab_index),
         {:ok, item} <- get_bank_item(tab.id, slot_index) do
      Repo.delete(item)
      {:ok, item}
    end
  end

  @spec deposit_gold(integer(), integer(), integer()) :: {:ok, Guild.t()} | {:error, term()}
  def deposit_gold(guild_id, character_id, amount) do
    with {:ok, _} <- check_permission(guild_id, character_id, :bank_deposit),
         %{} = guild <- get_guild(guild_id) do
      guild |> Guild.changeset(%{bank_gold: guild.bank_gold + amount}) |> Repo.update()
    else
      nil -> {:error, :guild_not_found}
      error -> error
    end
  end

  # Private helpers

  defp check_permission(guild_id, character_id, permission) do
    member = get_member(guild_id, character_id) |> Repo.preload(:rank)

    cond do
      member == nil -> {:error, :not_in_guild}
      GuildRank.has_permission?(member.rank.permissions, permission) -> {:ok, member}
      true -> {:error, :no_permission}
    end
  end

  defp check_can_act_on(guild_id, actor_id, target_id) do
    actor = get_member(guild_id, actor_id) |> Repo.preload(:rank)
    target = get_member(guild_id, target_id) |> Repo.preload(:rank)

    if actor.rank.rank_index < target.rank.rank_index do
      :ok
    else
      {:error, :insufficient_rank}
    end
  end

  defp get_lowest_rank(guild_id) do
    GuildRank
    |> where([r], r.guild_id == ^guild_id)
    |> order_by(desc: :rank_index)
    |> limit(1)
    |> Repo.one()
  end

  defp get_next_higher_rank(guild_id, current_index) do
    GuildRank
    |> where([r], r.guild_id == ^guild_id and r.rank_index < ^current_index)
    |> order_by(desc: :rank_index)
    |> limit(1)
    |> Repo.one()
  end

  defp get_next_lower_rank(guild_id, current_index) do
    GuildRank
    |> where([r], r.guild_id == ^guild_id and r.rank_index > ^current_index)
    |> order_by(asc: :rank_index)
    |> limit(1)
    |> Repo.one()
  end

  defp get_bank_tab(guild_id, tab_index) do
    case Repo.get_by(GuildBankTab, guild_id: guild_id, tab_index: tab_index) do
      nil -> {:error, :tab_not_found}
      tab -> {:ok, tab}
    end
  end

  defp find_empty_bank_slot(tab_id) do
    used = GuildBankItem
    |> where([i], i.bank_tab_id == ^tab_id)
    |> select([i], i.slot_index)
    |> Repo.all()
    |> MapSet.new()

    case Enum.find(0..(GuildBankTab.slots_per_tab() - 1), &(not MapSet.member?(used, &1))) do
      nil -> {:error, :tab_full}
      slot -> {:ok, slot}
    end
  end

  defp get_bank_item(tab_id, slot_index) do
    case Repo.get_by(GuildBankItem, bank_tab_id: tab_id, slot_index: slot_index) do
      nil -> {:error, :item_not_found}
      item -> {:ok, item}
    end
  end
end
```

---

## Task 132-145: Guild Packets and Handler

**Files to create:**
- `server_guild_info.ex` - Full guild data
- `server_guild_roster.ex` - Member list
- `server_guild_rank_list.ex` - Rank definitions
- `server_guild_bank_tab.ex` - Bank tab contents
- `client_guild_create.ex`
- `client_guild_invite.ex`
- `client_guild_kick.ex`
- `client_guild_promote.ex`
- `client_guild_demote.ex`
- `client_guild_bank_deposit.ex`
- `client_guild_bank_withdraw.ex`
- `guild_handler.ex`

---

## Task 146-155: Guild Tests

**Files:**
- Create: `apps/bezgelor_db/test/guilds_test.exs`
- Create: `apps/bezgelor_world/test/handler/guild_handler_test.exs`

---

# System 8: Mail

**Goal:** Send and receive mail with full attachments and COD support.

**Architecture Decision:** Full attachments + COD from day one.

## Task 156: Mail Schema

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/schema/mail.ex`

```elixir
defmodule BezgelorDb.Schema.Mail do
  @moduledoc """
  A mail message with optional attachments.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias BezgelorDb.Schema.{Character, MailAttachment}

  @mail_types [:normal, :auction, :cod, :system]

  schema "mails" do
    belongs_to :sender, Character
    belongs_to :recipient, Character
    field :mail_type, Ecto.Enum, values: @mail_types, default: :normal
    field :subject, :string
    field :body, :string, default: ""
    field :gold, :integer, default: 0       # Attached gold
    field :cod_amount, :integer, default: 0  # COD price (recipient pays)
    field :is_read, :boolean, default: false
    field :expires_at, :utc_datetime
    field :returned, :boolean, default: false
    has_many :attachments, MailAttachment
    timestamps()
  end

  @expiry_days 30

  def changeset(mail, attrs) do
    mail
    |> cast(attrs, [:sender_id, :recipient_id, :mail_type, :subject, :body, :gold, :cod_amount, :is_read, :expires_at, :returned])
    |> validate_required([:sender_id, :recipient_id, :subject])
    |> validate_length(:subject, min: 1, max: 64)
    |> validate_length(:body, max: 2000)
    |> validate_number(:gold, greater_than_or_equal_to: 0)
    |> validate_number(:cod_amount, greater_than_or_equal_to: 0)
    |> set_default_expiry()
  end

  defp set_default_expiry(changeset) do
    if get_field(changeset, :expires_at) == nil do
      put_change(changeset, :expires_at, DateTime.add(DateTime.utc_now(), @expiry_days * 24 * 60 * 60, :second))
    else
      changeset
    end
  end

  def expiry_days, do: @expiry_days
end
```

---

## Task 157: Mail Attachment Schema

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/schema/mail_attachment.ex`

```elixir
defmodule BezgelorDb.Schema.MailAttachment do
  @moduledoc """
  An item attached to a mail.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias BezgelorDb.Schema.Mail

  @max_attachments 12

  schema "mail_attachments" do
    belongs_to :mail, Mail
    field :slot_index, :integer    # 0-11
    field :item_id, :integer
    field :stack_count, :integer, default: 1
    # Store item state for when items are detached from character
    field :durability, :integer
    field :charges, :integer
    field :random_suffix_id, :integer
    timestamps()
  end

  def changeset(attachment, attrs) do
    attachment
    |> cast(attrs, [:mail_id, :slot_index, :item_id, :stack_count, :durability, :charges, :random_suffix_id])
    |> validate_required([:mail_id, :slot_index, :item_id])
    |> validate_number(:slot_index, greater_than_or_equal_to: 0, less_than: @max_attachments)
    |> validate_number(:stack_count, greater_than: 0)
    |> unique_constraint([:mail_id, :slot_index])
  end

  def max_attachments, do: @max_attachments
end
```

---

## Task 158: Mail Migration

**Files:**
- Create: `apps/bezgelor_db/priv/repo/migrations/TIMESTAMP_create_mail.exs`

```elixir
defmodule BezgelorDb.Repo.Migrations.CreateMail do
  use Ecto.Migration

  def change do
    create table(:mails) do
      add :sender_id, references(:characters, on_delete: :nilify_all)
      add :recipient_id, references(:characters, on_delete: :delete_all), null: false
      add :mail_type, :string, default: "normal"
      add :subject, :string, size: 64, null: false
      add :body, :text, default: ""
      add :gold, :bigint, default: 0
      add :cod_amount, :bigint, default: 0
      add :is_read, :boolean, default: false
      add :expires_at, :utc_datetime, null: false
      add :returned, :boolean, default: false
      timestamps()
    end

    create index(:mails, [:recipient_id])
    create index(:mails, [:sender_id])
    create index(:mails, [:expires_at])

    create table(:mail_attachments) do
      add :mail_id, references(:mails, on_delete: :delete_all), null: false
      add :slot_index, :integer, null: false
      add :item_id, :integer, null: false
      add :stack_count, :integer, default: 1
      add :durability, :integer
      add :charges, :integer
      add :random_suffix_id, :integer
      timestamps()
    end

    create unique_index(:mail_attachments, [:mail_id, :slot_index])
  end
end
```

---

## Task 159: Mail Context

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/mail.ex`

```elixir
defmodule BezgelorDb.Mail do
  @moduledoc """
  Mail management context.
  """
  import Ecto.Query
  alias BezgelorDb.Repo
  alias BezgelorDb.Schema.{Mail, MailAttachment}
  alias BezgelorDb.{Characters, Inventory}

  @max_inbox 100
  @send_cost 30  # Base mail cost in copper

  # Inbox management

  @spec get_inbox(integer()) :: [Mail.t()]
  def get_inbox(character_id) do
    Mail
    |> where([m], m.recipient_id == ^character_id and not m.returned)
    |> where([m], m.expires_at > ^DateTime.utc_now())
    |> order_by(desc: :inserted_at)
    |> preload(:attachments)
    |> Repo.all()
  end

  @spec get_mail(integer(), integer()) :: Mail.t() | nil
  def get_mail(mail_id, character_id) do
    Mail
    |> where([m], m.id == ^mail_id and m.recipient_id == ^character_id)
    |> preload(:attachments)
    |> Repo.one()
  end

  @spec unread_count(integer()) :: integer()
  def unread_count(character_id) do
    Mail
    |> where([m], m.recipient_id == ^character_id and not m.is_read and not m.returned)
    |> where([m], m.expires_at > ^DateTime.utc_now())
    |> Repo.aggregate(:count)
  end

  # Sending mail

  @spec send_mail(integer(), String.t(), String.t(), String.t(), keyword()) :: {:ok, Mail.t()} | {:error, term()}
  def send_mail(sender_id, recipient_name, subject, body, opts \\ []) do
    gold = Keyword.get(opts, :gold, 0)
    cod_amount = Keyword.get(opts, :cod_amount, 0)
    items = Keyword.get(opts, :items, [])  # List of {bag_index, slot_index}

    recipient = Characters.get_character_by_name(recipient_name)
    inbox_count = if recipient, do: Repo.aggregate(from(m in Mail, where: m.recipient_id == ^recipient.id), :count), else: 0

    cond do
      recipient == nil -> {:error, :recipient_not_found}
      recipient.id == sender_id -> {:error, :cannot_mail_self}
      inbox_count >= @max_inbox -> {:error, :recipient_inbox_full}
      cod_amount > 0 and length(items) == 0 -> {:error, :cod_requires_items}
      true ->
        do_send_mail(sender_id, recipient.id, subject, body, gold, cod_amount, items)
    end
  end

  defp do_send_mail(sender_id, recipient_id, subject, body, gold, cod_amount, item_slots) do
    Repo.transaction(fn ->
      # Create mail
      {:ok, mail} = %Mail{}
      |> Mail.changeset(%{
        sender_id: sender_id,
        recipient_id: recipient_id,
        subject: subject,
        body: body,
        gold: gold,
        cod_amount: cod_amount,
        mail_type: if(cod_amount > 0, do: :cod, else: :normal)
      })
      |> Repo.insert()

      # Move items from sender's inventory to mail attachments
      Enum.with_index(item_slots, fn {bag_index, slot_index}, index ->
        item = Inventory.get_item(sender_id, bag_index, slot_index)

        if item do
          # Remove from inventory
          {:ok, _} = Inventory.remove_item(sender_id, bag_index, slot_index, item.stack_count)

          # Add as attachment
          {:ok, _} = %MailAttachment{}
          |> MailAttachment.changeset(%{
            mail_id: mail.id,
            slot_index: index,
            item_id: item.item_id,
            stack_count: item.stack_count,
            durability: item.durability,
            charges: item.charges,
            random_suffix_id: item.random_suffix_id
          })
          |> Repo.insert()
        end
      end)

      mail
    end)
  end

  # Reading/taking mail

  @spec mark_read(integer(), integer()) :: {:ok, Mail.t()} | {:error, term()}
  def mark_read(mail_id, character_id) do
    case get_mail(mail_id, character_id) do
      nil -> {:error, :mail_not_found}
      mail -> mail |> Mail.changeset(%{is_read: true}) |> Repo.update()
    end
  end

  @spec take_gold(integer(), integer()) :: {:ok, integer()} | {:error, term()}
  def take_gold(mail_id, character_id) do
    case get_mail(mail_id, character_id) do
      nil -> {:error, :mail_not_found}
      %{gold: 0} -> {:error, :no_gold}
      %{cod_amount: cod} when cod > 0 -> {:error, :cod_must_pay_first}
      mail ->
        gold = mail.gold
        {:ok, _} = mail |> Mail.changeset(%{gold: 0}) |> Repo.update()
        {:ok, gold}
    end
  end

  @spec take_attachment(integer(), integer(), integer()) :: {:ok, MailAttachment.t()} | {:error, term()}
  def take_attachment(mail_id, character_id, slot_index) do
    mail = get_mail(mail_id, character_id)

    cond do
      mail == nil -> {:error, :mail_not_found}
      mail.cod_amount > 0 -> {:error, :cod_must_pay_first}
      true ->
        attachment = Enum.find(mail.attachments, & &1.slot_index == slot_index)

        if attachment do
          # Add to player inventory
          case Inventory.add_item(character_id, attachment.item_id, attachment.stack_count) do
            {:ok, _item} ->
              Repo.delete(attachment)
              {:ok, attachment}
            {:error, _} = err -> err
          end
        else
          {:error, :attachment_not_found}
        end
    end
  end

  @spec pay_cod(integer(), integer()) :: {:ok, Mail.t()} | {:error, term()}
  def pay_cod(mail_id, character_id) do
    mail = get_mail(mail_id, character_id)

    cond do
      mail == nil -> {:error, :mail_not_found}
      mail.cod_amount == 0 -> {:error, :not_cod_mail}
      true ->
        # TODO: Deduct gold from recipient, send to sender
        # For now, just clear COD
        cod_amount = mail.cod_amount
        {:ok, _} = mail |> Mail.changeset(%{cod_amount: 0}) |> Repo.update()

        # Send gold to sender via return mail
        send_gold_mail(mail.sender_id, mail.recipient_id, cod_amount)

        {:ok, mail}
    end
  end

  defp send_gold_mail(recipient_id, sender_id, gold) do
    %Mail{}
    |> Mail.changeset(%{
      sender_id: sender_id,
      recipient_id: recipient_id,
      subject: "COD Payment",
      body: "Payment received for COD mail.",
      gold: gold,
      mail_type: :normal
    })
    |> Repo.insert()
  end

  # Delete/return mail

  @spec delete_mail(integer(), integer()) :: :ok | {:error, term()}
  def delete_mail(mail_id, character_id) do
    case get_mail(mail_id, character_id) do
      nil -> {:error, :mail_not_found}
      mail when length(mail.attachments) > 0 -> {:error, :has_attachments}
      mail when mail.gold > 0 -> {:error, :has_gold}
      mail ->
        Repo.delete(mail)
        :ok
    end
  end

  @spec return_mail(integer(), integer()) :: {:ok, Mail.t()} | {:error, term()}
  def return_mail(mail_id, character_id) do
    case get_mail(mail_id, character_id) do
      nil -> {:error, :mail_not_found}
      %{returned: true} -> {:error, :already_returned}
      %{sender_id: nil} -> {:error, :no_sender}
      mail ->
        # Swap sender and recipient, mark as returned
        mail
        |> Mail.changeset(%{
          sender_id: mail.recipient_id,
          recipient_id: mail.sender_id,
          returned: true,
          is_read: false,
          cod_amount: 0,  # Clear COD on return
          expires_at: DateTime.add(DateTime.utc_now(), Mail.expiry_days() * 24 * 60 * 60, :second)
        })
        |> Repo.update()
    end
  end

  # Cleanup expired mail

  @spec cleanup_expired() :: {integer(), nil}
  def cleanup_expired do
    Mail
    |> where([m], m.expires_at < ^DateTime.utc_now())
    |> Repo.delete_all()
  end
end
```

---

## Task 160-165: Mail Packets

**Files:**
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_mail_list.ex`

```elixir
defmodule BezgelorProtocol.Packets.World.ServerMailList do
  @moduledoc """
  Mail inbox list.
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct mails: []

  @impl true
  def opcode, do: :server_mail_list

  @impl true
  def write(%__MODULE__{mails: mails}, writer) do
    writer = PacketWriter.write_uint32(writer, length(mails))

    writer = Enum.reduce(mails, writer, fn mail, w ->
      w
      |> PacketWriter.write_uint64(mail.id)
      |> PacketWriter.write_uint64(mail.sender_id || 0)
      |> PacketWriter.write_wide_string(mail.sender_name || "Unknown")
      |> PacketWriter.write_wide_string(mail.subject)
      |> PacketWriter.write_byte(mail_type_to_int(mail.mail_type))
      |> PacketWriter.write_byte(if(mail.is_read, do: 1, else: 0))
      |> PacketWriter.write_uint64(mail.gold)
      |> PacketWriter.write_uint64(mail.cod_amount)
      |> PacketWriter.write_uint32(length(mail.attachments))
      |> PacketWriter.write_uint64(DateTime.to_unix(mail.expires_at))
    end)

    {:ok, writer}
  end

  defp mail_type_to_int(:normal), do: 0
  defp mail_type_to_int(:auction), do: 1
  defp mail_type_to_int(:cod), do: 2
  defp mail_type_to_int(:system), do: 3
  defp mail_type_to_int(_), do: 0
end
```

**Files:**
- Create: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/client_send_mail.ex`

```elixir
defmodule BezgelorProtocol.Packets.World.ClientSendMail do
  @moduledoc """
  Send mail request.
  """
  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:recipient_name, :subject, :body, :gold, :cod_amount, :attachments]

  @impl true
  def opcode, do: :client_send_mail

  @impl true
  def read(reader) do
    with {:ok, recipient_name, reader} <- PacketReader.read_wide_string(reader),
         {:ok, subject, reader} <- PacketReader.read_wide_string(reader),
         {:ok, body, reader} <- PacketReader.read_wide_string(reader),
         {:ok, gold, reader} <- PacketReader.read_uint64(reader),
         {:ok, cod_amount, reader} <- PacketReader.read_uint64(reader),
         {:ok, attachment_count, reader} <- PacketReader.read_uint32(reader),
         {:ok, attachments, reader} <- read_attachments(reader, attachment_count) do
      {:ok, %__MODULE__{
        recipient_name: recipient_name,
        subject: subject,
        body: body,
        gold: gold,
        cod_amount: cod_amount,
        attachments: attachments
      }, reader}
    end
  end

  defp read_attachments(reader, count, acc \\ [])
  defp read_attachments(reader, 0, acc), do: {:ok, Enum.reverse(acc), reader}
  defp read_attachments(reader, count, acc) do
    with {:ok, bag_index, reader} <- PacketReader.read_uint32(reader),
         {:ok, slot_index, reader} <- PacketReader.read_uint32(reader) do
      read_attachments(reader, count - 1, [{bag_index, slot_index} | acc])
    end
  end
end
```

---

## Task 166-175: Mail Handler and Tests

**Files:**
- Create: `apps/bezgelor_world/lib/bezgelor_world/handler/mail_handler.ex`
- Create: `apps/bezgelor_db/test/mail_test.exs`
- Create: `apps/bezgelor_world/test/handler/mail_handler_test.exs`

---

# Testing Strategy

Each system should have:

1. **Unit tests** for core logic (bezgelor_core)
2. **Context tests** for database operations (bezgelor_db)
3. **Packet tests** for serialization (bezgelor_protocol)
4. **Handler tests** for request processing (bezgelor_world)
5. **Integration tests** for end-to-end flows

---

# Execution Order

**Phase 7A (Foundation):**
1. Social (Tasks 1-15) - Simple, establishes patterns
2. Reputation (Tasks 41-52) - Simple, needed by quests

**Phase 7B (Core Systems):**
3. Inventory (Tasks 16-40) - Needed by quests and mail
4. Quests (Tasks 53-85) - Core progression

**Phase 7C (Progression):**
5. Achievements (Tasks 86-105)
6. Paths (Tasks 106-125)

**Phase 7D (Social/Group):**
7. Guilds (Tasks 126-155)
8. Mail (Tasks 156-175)

---

# Success Criteria

Phase 7 is complete when:

- [ ] Players can add/remove friends and see online status
- [ ] Players can ignore unwanted players
- [ ] Players can carry items in bags and equip gear
- [ ] Players gain reputation with factions
- [ ] Players can accept, track, and complete quests
- [ ] Players earn achievements for various activities
- [ ] Players can progress in their chosen Path
- [ ] Players can create/join guilds with ranks
- [ ] Players can send/receive mail with attachments
- [ ] All tests pass (target: 200+ new tests)
