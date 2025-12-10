defmodule BezgelorDb.Realms do
  @moduledoc """
  Realm management context.

  ## Overview

  This module provides the primary interface for realm operations:

  - Listing available realms
  - Creating and updating realms
  - Managing realm online status

  ## Usage

      # List all online realms
      realms = Realms.list_online_realms()

      # Get a specific realm
      realm = Realms.get_realm(1)

      # Set realm online
      {:ok, realm} = Realms.set_online(realm, true)
  """

  import Ecto.Query
  alias BezgelorDb.Repo
  alias BezgelorDb.Schema.Realm

  @doc """
  Get all realms.

  ## Returns

  List of all realm structs.
  """
  @spec list_realms() :: [Realm.t()]
  def list_realms do
    Repo.all(Realm)
  end

  @doc """
  Get only online realms.

  ## Returns

  List of realms where `online` is true.
  """
  @spec list_online_realms() :: [Realm.t()]
  def list_online_realms do
    Realm
    |> where([r], r.online == true)
    |> Repo.all()
  end

  @doc """
  Get first online realm.

  Used for simple realm selection when client authenticates.

  ## Returns

  - First online `Realm` struct
  - `nil` if no realms are online
  """
  @spec get_first_online_realm() :: Realm.t() | nil
  def get_first_online_realm do
    Realm
    |> where([r], r.online == true)
    |> first()
    |> Repo.one()
  end

  @doc """
  Get a realm by ID.

  ## Parameters

  - `id` - The realm ID

  ## Returns

  - `Realm` struct if found
  - `nil` if not found
  """
  @spec get_realm(integer()) :: Realm.t() | nil
  def get_realm(id) do
    Repo.get(Realm, id)
  end

  @doc """
  Get a realm by name.

  ## Parameters

  - `name` - The realm name

  ## Returns

  - `Realm` struct if found
  - `nil` if not found
  """
  @spec get_realm_by_name(String.t()) :: Realm.t() | nil
  def get_realm_by_name(name) do
    Repo.get_by(Realm, name: name)
  end

  @doc """
  Create a new realm.

  ## Parameters

  - `attrs` - Map with realm attributes

  ## Returns

  - `{:ok, realm}` on success
  - `{:error, changeset}` on failure

  ## Example

      {:ok, realm} = Realms.create_realm(%{
        name: "Nexus",
        address: "127.0.0.1",
        port: 24000,
        type: :pve
      })
  """
  @spec create_realm(map()) :: {:ok, Realm.t()} | {:error, Ecto.Changeset.t()}
  def create_realm(attrs) do
    %Realm{}
    |> Realm.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Update an existing realm.

  ## Parameters

  - `realm` - The realm to update
  - `attrs` - Map with attributes to update

  ## Returns

  - `{:ok, realm}` on success
  - `{:error, changeset}` on failure
  """
  @spec update_realm(Realm.t(), map()) :: {:ok, Realm.t()} | {:error, Ecto.Changeset.t()}
  def update_realm(%Realm{} = realm, attrs) do
    realm
    |> Realm.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Delete a realm.

  ## Parameters

  - `realm` - The realm to delete

  ## Returns

  - `{:ok, realm}` on success
  - `{:error, changeset}` on failure
  """
  @spec delete_realm(Realm.t()) :: {:ok, Realm.t()} | {:error, Ecto.Changeset.t()}
  def delete_realm(%Realm{} = realm) do
    Repo.delete(realm)
  end

  @doc """
  Set a realm's online status.

  ## Parameters

  - `realm` - The realm to update
  - `online` - Boolean online status

  ## Returns

  - `{:ok, realm}` on success
  - `{:error, changeset}` on failure
  """
  @spec set_online(Realm.t(), boolean()) :: {:ok, Realm.t()} | {:error, Ecto.Changeset.t()}
  def set_online(%Realm{} = realm, online) do
    update_realm(realm, %{online: online})
  end

  @doc """
  Convert an IP address string to network byte order uint32.

  ## Parameters

  - `ip_string` - IP address as string (e.g., "127.0.0.1")

  ## Returns

  The IP as a uint32 in network byte order (big-endian).

  ## Example

      iex> Realms.ip_to_uint32("127.0.0.1")
      2130706433  # 0x7F000001
  """
  @spec ip_to_uint32(String.t()) :: non_neg_integer()
  def ip_to_uint32(ip_string) when is_binary(ip_string) do
    [a, b, c, d] =
      ip_string
      |> String.split(".")
      |> Enum.map(&String.to_integer/1)

    <<n::big-unsigned-32>> = <<a, b, c, d>>
    n
  end
end
