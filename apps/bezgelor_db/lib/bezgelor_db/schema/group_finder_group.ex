defmodule BezgelorDb.Schema.GroupFinderGroup do
  @moduledoc """
  Schema for formed groups from the group finder.

  Tracks groups that have been matched and are awaiting entry:
  - Member IDs and role assignments
  - Ready check status
  - Group lifecycle status
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          group_guid: binary(),
          instance_definition_id: integer(),
          difficulty: String.t(),
          member_ids: [integer()],
          roles: map(),
          status: String.t(),
          ready_check: map(),
          expires_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @difficulties ~w(normal veteran challenge mythic_plus)
  @statuses ~w(forming ready entering active disbanded)

  schema "group_finder_groups" do
    field(:group_guid, :binary)
    field(:instance_definition_id, :integer)
    field(:difficulty, :string)
    field(:member_ids, {:array, :integer})
    field(:roles, :map)
    field(:status, :string, default: "forming")
    field(:ready_check, :map, default: %{})
    field(:expires_at, :utc_datetime)

    timestamps()
  end

  @required_fields [:group_guid, :instance_definition_id, :difficulty, :member_ids, :roles]
  @optional_fields [:status, :ready_check, :expires_at]

  @doc """
  Creates a changeset for a group.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(group, attrs) do
    group
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:difficulty, @difficulties)
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint(:group_guid)
  end

  @doc """
  Sets a player's ready status.
  """
  @spec set_ready(t(), integer(), boolean()) :: Ecto.Changeset.t()
  def set_ready(group, character_id, ready) do
    new_ready_check = Map.put(group.ready_check, to_string(character_id), ready)
    change(group, ready_check: new_ready_check)
  end

  @doc """
  Checks if all members are ready.
  """
  @spec all_ready?(t()) :: boolean()
  def all_ready?(%__MODULE__{member_ids: member_ids, ready_check: ready_check}) do
    Enum.all?(member_ids, fn id ->
      Map.get(ready_check, to_string(id), false) == true
    end)
  end

  @doc """
  Returns the count of ready members.
  """
  @spec ready_count(t()) :: integer()
  def ready_count(%__MODULE__{member_ids: member_ids, ready_check: ready_check}) do
    Enum.count(member_ids, fn id ->
      Map.get(ready_check, to_string(id), false) == true
    end)
  end

  @doc """
  Sets the group status.
  """
  @spec set_status(t(), String.t()) :: Ecto.Changeset.t()
  def set_status(group, status) do
    change(group, status: status)
  end

  @doc """
  Checks if a character is a member of this group.
  """
  @spec member?(t(), integer()) :: boolean()
  def member?(%__MODULE__{member_ids: member_ids}, character_id) do
    character_id in member_ids
  end

  @doc """
  Returns the tank ID(s) for this group.
  """
  @spec tanks(t()) :: [integer()]
  def tanks(%__MODULE__{roles: roles}) do
    Map.get(roles, "tank", [])
  end

  @doc """
  Returns the healer ID(s) for this group.
  """
  @spec healers(t()) :: [integer()]
  def healers(%__MODULE__{roles: roles}) do
    Map.get(roles, "healer", [])
  end

  @doc """
  Returns the DPS ID(s) for this group.
  """
  @spec dps(t()) :: [integer()]
  def dps(%__MODULE__{roles: roles}) do
    Map.get(roles, "dps", [])
  end

  @doc """
  Returns the number of members.
  """
  @spec member_count(t()) :: integer()
  def member_count(%__MODULE__{member_ids: member_ids}) do
    length(member_ids)
  end

  @doc """
  Checks if the group is full (5 members for dungeons).
  """
  @spec full?(t(), integer()) :: boolean()
  def full?(%__MODULE__{member_ids: member_ids}, max_size \\ 5) do
    length(member_ids) >= max_size
  end

  @doc """
  Returns the list of valid statuses.
  """
  @spec statuses() :: [String.t()]
  def statuses, do: @statuses
end
