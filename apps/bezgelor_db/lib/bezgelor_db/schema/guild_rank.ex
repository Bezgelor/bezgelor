defmodule BezgelorDb.Schema.GuildRank do
  @moduledoc """
  Schema for guild ranks with permissions.

  ## Default Ranks

  - Rank 0: Guild Master (all permissions)
  - Rank 1: Officer
  - Rank 2: Veteran
  - Rank 3: Member
  - Rank 4: Initiate (lowest)

  ## Permission Bits

  - 1: Invite members
  - 2: Kick members
  - 4: Promote members
  - 8: Demote members
  - 16: Edit ranks
  - 32: Edit MOTD
  - 64: Guild bank deposit
  - 128: Guild bank withdraw
  - 256: Disband guild
  - 512: Edit guild info
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Bitwise

  @type t :: %__MODULE__{}

  # Permission bit flags
  @perm_invite 1
  @perm_kick 2
  @perm_promote 4
  @perm_demote 8
  @perm_edit_ranks 16
  @perm_edit_motd 32
  @perm_bank_deposit 64
  @perm_bank_withdraw 128
  @perm_disband 256
  @perm_edit_info 512

  # All permissions
  @perm_all @perm_invite ||| @perm_kick ||| @perm_promote ||| @perm_demote |||
              @perm_edit_ranks ||| @perm_edit_motd ||| @perm_bank_deposit |||
              @perm_bank_withdraw ||| @perm_disband ||| @perm_edit_info

  schema "guild_ranks" do
    belongs_to(:guild, BezgelorDb.Schema.Guild)

    # 0 = Guild Master, 4 = lowest
    field(:rank_index, :integer)
    field(:name, :string)
    field(:permissions, :integer, default: 0)

    timestamps(type: :utc_datetime)
  end

  def changeset(rank, attrs) do
    rank
    |> cast(attrs, [:guild_id, :rank_index, :name, :permissions])
    |> validate_required([:guild_id, :rank_index, :name])
    |> validate_number(:rank_index, greater_than_or_equal_to: 0, less_than_or_equal_to: 9)
    |> validate_length(:name, min: 1, max: 20)
    |> foreign_key_constraint(:guild_id)
    |> unique_constraint([:guild_id, :rank_index], name: :guild_ranks_guild_id_rank_index_index)
  end

  def permissions_changeset(rank, permissions) do
    rank
    |> cast(%{permissions: permissions}, [:permissions])
  end

  def name_changeset(rank, name) do
    rank
    |> cast(%{name: name}, [:name])
    |> validate_length(:name, min: 1, max: 20)
  end

  # Permission helpers
  def has_permission?(%__MODULE__{permissions: perms}, permission) do
    (perms &&& permission) != 0
  end

  def can_invite?(rank), do: has_permission?(rank, @perm_invite)
  def can_kick?(rank), do: has_permission?(rank, @perm_kick)
  def can_promote?(rank), do: has_permission?(rank, @perm_promote)
  def can_demote?(rank), do: has_permission?(rank, @perm_demote)
  def can_edit_ranks?(rank), do: has_permission?(rank, @perm_edit_ranks)
  def can_edit_motd?(rank), do: has_permission?(rank, @perm_edit_motd)
  def can_bank_deposit?(rank), do: has_permission?(rank, @perm_bank_deposit)
  def can_bank_withdraw?(rank), do: has_permission?(rank, @perm_bank_withdraw)
  def can_disband?(rank), do: has_permission?(rank, @perm_disband)
  def can_edit_info?(rank), do: has_permission?(rank, @perm_edit_info)

  # Default rank configurations
  def default_ranks do
    [
      %{rank_index: 0, name: "Guild Master", permissions: @perm_all},
      %{
        rank_index: 1,
        name: "Officer",
        permissions:
          @perm_invite ||| @perm_kick ||| @perm_promote ||| @perm_demote ||| @perm_edit_motd |||
            @perm_bank_deposit ||| @perm_bank_withdraw
      },
      %{
        rank_index: 2,
        name: "Veteran",
        permissions: @perm_invite ||| @perm_bank_deposit ||| @perm_bank_withdraw
      },
      %{rank_index: 3, name: "Member", permissions: @perm_bank_deposit},
      %{rank_index: 4, name: "Initiate", permissions: 0}
    ]
  end
end
