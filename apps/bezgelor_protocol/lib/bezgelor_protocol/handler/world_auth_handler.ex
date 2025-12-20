defmodule BezgelorProtocol.Handler.WorldAuthHandler do
  @moduledoc """
  Handler for ClientHelloRealm packets on the world server (port 24000).

  This handler validates session keys issued by the realm server
  and updates the encryption key for subsequent packets.

  ## Authentication Flow

  1. Parse ClientHelloRealm with session key
  2. Look up account by email + session key
  3. Update encryption to use session-key-derived key
  4. Wait for client to send ClientCharacterList (handled separately)

  Note: Character list is NOT sent here. The client will request it
  via ClientCharacterList packet, which is handled by CharacterListHandler.
  """

  @behaviour BezgelorProtocol.Handler

  alias BezgelorProtocol.Packets.World.ClientHelloRealm
  alias BezgelorProtocol.PacketReader
  alias BezgelorCrypto.PacketCrypt
  alias BezgelorDb.Accounts

  require Logger

  @impl true
  def handle(payload, state) do
    reader = PacketReader.new(payload)

    case ClientHelloRealm.read(reader) do
      {:ok, packet, _reader} ->
        state = put_in(state.session_data[:email], packet.email)
        process_auth(packet, state)

      {:error, reason} ->
        Logger.warning("Failed to parse ClientHelloRealm: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp process_auth(packet, state) do
    with {:ok, account} <- validate_session(packet) do
      # Store account in session
      state = put_in(state.session_data[:account_id], account.id)

      # CRITICAL: Update encryption key to use session key
      # This matches NexusForever's SetEncryptionKey(helloRealm.SessionKey)
      # All subsequent packets will use this new encryption key
      new_key = PacketCrypt.key_from_ticket(packet.session_key)
      new_encryption = PacketCrypt.new(new_key)
      state = %{state | encryption: new_encryption}

      # Set account metadata for log tracing
      Logger.metadata(account: packet.email)

      Logger.info(
        "World auth successful for account #{account.id} (#{packet.email}), " <>
          "switched to session-based encryption"
      )

      # Don't send character list here - wait for ClientCharacterList request
      # This matches NexusForever's flow
      {:ok, state}
    else
      {:error, reason} ->
        Logger.warning("World authentication failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp validate_session(packet) do
    # Session key comes as raw bytes, need to convert to hex for comparison
    session_key_hex = Base.encode16(packet.session_key)

    # Use atomic validation that checks email + session_key + account_id together
    # to prevent race conditions between session lookup and account ID verification
    case Accounts.validate_session_key_with_account(
           packet.email,
           session_key_hex,
           packet.account_id
         ) do
      {:error, :session_not_found} ->
        Logger.debug("Invalid session for email: #{packet.email}")
        {:error, :invalid_session}

      {:error, :session_expired} ->
        Logger.info("Session expired for email: #{packet.email}")
        {:error, :session_expired}

      {:error, :account_mismatch} ->
        Logger.warning("Account ID mismatch for email: #{packet.email}")
        {:error, :account_mismatch}

      {:ok, account} ->
        {:ok, account}
    end
  end
end
