defmodule BezgelorProtocol.Handler.RealmSelectHandler do
  @moduledoc """
  Handler for ClientRealmSelect packets.

  Called when the player selects a realm from the realm list dialog.

  ## Packet Structure

  ```
  realm_id : uint32 - ID of the selected realm
  ```

  ## Behavior

  1. If same realm selected → ignore (client crashes otherwise)
  2. If target realm offline → ignore with warning
  3. If target realm online → generate new session key, send ServerNewRealm
  """

  @behaviour BezgelorProtocol.Handler

  alias BezgelorProtocol.PacketReader
  alias BezgelorProtocol.PacketWriter
  alias BezgelorProtocol.Packets.World.ServerNewRealm
  alias BezgelorDb.Accounts
  alias BezgelorDb.Realms

  require Logger

  @impl true
  def handle(payload, state) do
    # Read the realm ID from the packet
    reader = PacketReader.new(payload)

    case PacketReader.read_uint32(reader) do
      {:ok, realm_id, _reader} ->
        handle_realm_select(realm_id, state)

      {:error, reason} ->
        Logger.warning("RealmSelectHandler: failed to read realm_id - #{inspect(reason)}")
        {:ok, state}
    end
  end

  defp handle_realm_select(realm_id, state) do
    current_realm_id = Application.get_env(:bezgelor_realm, :realm_id, 1)

    if realm_id == current_realm_id do
      # Same realm selected (or clicked back) - ignore per NexusForever:
      # "clicking back or selecting the current realm also triggers this packet,
      # client crashes if we don't ignore it"
      Logger.debug("RealmSelectHandler: same realm selected (#{realm_id}), ignoring")
      {:ok, state}
    else
      # Different realm selected - look up from database
      case Realms.get_realm(realm_id) do
        nil ->
          Logger.warning("RealmSelectHandler: realm #{realm_id} not found in database")
          {:ok, state}

        realm ->
          handle_realm_transfer(realm, state)
      end
    end
  end

  defp handle_realm_transfer(realm, state) do
    if realm.online do
      account_id = get_in(state.session_data, [:account_id])

      # Generate new session key for the target realm
      session_key = :crypto.strong_rand_bytes(16)

      # Update account's session key in database
      case update_session_key(account_id, session_key) do
        :ok ->
          send_new_realm(realm, session_key, state)

        {:error, reason} ->
          Logger.error("RealmSelectHandler: failed to update session key - #{inspect(reason)}")
          {:ok, state}
      end
    else
      Logger.warning("RealmSelectHandler: realm '#{realm.name}' (#{realm.id}) is offline")
      {:ok, state}
    end
  end

  defp update_session_key(nil, _session_key), do: {:error, :no_account}

  defp update_session_key(account_id, session_key) do
    case Accounts.get_by_id(account_id) do
      nil ->
        {:error, :account_not_found}

      account ->
        case Accounts.update_session_key(account, session_key) do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp send_new_realm(realm, session_key, state) do
    Logger.info(
      "RealmSelectHandler: sending transfer to realm '#{realm.name}' (#{realm.id}) " <>
        "at #{realm.address}:#{realm.port}"
    )

    # Build ServerNewRealm packet
    packet = ServerNewRealm.from_realm(realm, session_key)

    # Encode and send
    writer = PacketWriter.new()
    {:ok, writer} = ServerNewRealm.write(packet, writer)
    data = PacketWriter.to_binary(writer)

    {:reply_world_encrypted, :server_new_realm, data, state}
  end
end
