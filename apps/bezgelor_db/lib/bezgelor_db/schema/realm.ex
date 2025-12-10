defmodule BezgelorDb.Schema.Realm do
  @moduledoc """
  Database schema for game realms (servers).

  ## Overview

  Realms represent game world servers that players can connect to.
  Each realm has a unique name and connection details.

  ## Fields

  - `name` - Unique realm display name
  - `address` - World server IP address
  - `port` - World server port
  - `type` - Realm type (:pve or :pvp)
  - `flags` - Realm flags bitfield
  - `online` - Whether the realm is currently online
  - `note_text_id` - Server message text ID

  ## Example

      {:ok, realm} = Realms.create_realm(%{
        name: "Nexus",
        address: "127.0.0.1",
        port: 24000,
        type: :pve,
        online: true
      })
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type realm_type :: :pve | :pvp

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t() | nil,
          address: String.t() | nil,
          port: integer() | nil,
          type: realm_type() | nil,
          flags: integer(),
          online: boolean(),
          note_text_id: integer(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "realms" do
    field :name, :string
    field :address, :string
    field :port, :integer
    field :type, Ecto.Enum, values: [:pve, :pvp]
    field :flags, :integer, default: 0
    field :online, :boolean, default: false
    field :note_text_id, :integer, default: 0

    timestamps(type: :utc_datetime)
  end

  @doc """
  Build a changeset for creating or updating a realm.

  ## Validations

  - Name is required and must be unique
  - Address is required (IP address string)
  - Port is required and must be valid (1-65535)
  - Type is required
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(realm, attrs) do
    realm
    |> cast(attrs, [:name, :address, :port, :type, :flags, :online, :note_text_id])
    |> validate_required([:name, :address, :port, :type])
    |> validate_number(:port, greater_than: 0, less_than: 65536)
    |> unique_constraint(:name)
  end
end
