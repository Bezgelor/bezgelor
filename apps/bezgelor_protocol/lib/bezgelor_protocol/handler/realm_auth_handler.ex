defmodule BezgelorProtocol.Handler.RealmAuthHandler do
  @moduledoc """
  Handler for ClientHelloAuth packets on the realm server (port 23115).

  This handler validates game tokens issued by the STS server
  and provides realm information for world server connection.

  ## Authentication Flow

  1. Parse ClientHelloAuth (realm variant) with game token
  2. Validate build version (must be 16042)
  3. Look up account by email + game token
  4. Check account suspension status
  5. Select an online realm
  6. Generate session key for world server
  7. Send ServerAuthAccepted, ServerRealmMessages, ServerRealmInfo
  """

  @behaviour BezgelorProtocol.Handler

  alias BezgelorProtocol.Packets.Realm.{
    ClientHelloAuth,
    ServerAuthAccepted,
    ServerAuthDenied,
    ServerRealmMessages,
    ServerRealmInfo
  }

  alias BezgelorProtocol.{PacketReader, PacketWriter}
  alias BezgelorCrypto.Random
  alias BezgelorDb.{Accounts, Realms}

  require Logger

  @expected_build 16042

  @impl true
  def handle(payload, state) do
    reader = PacketReader.new(payload)

    case ClientHelloAuth.read(reader) do
      {:ok, packet, _reader} ->
        state = put_in(state.session_data[:email], packet.email)
        process_auth(packet, state)

      {:error, reason} ->
        Logger.warning("Failed to parse ClientHelloAuth (realm): #{inspect(reason)}")
        response = build_denial(:unknown)
        {:reply, :server_auth_denied_realm, encode_packet(response), state}
    end
  end

  defp process_auth(packet, state) do
    case validate_build(packet.build) do
      :ok ->
        authenticate(packet, state)

      {:error, reason} ->
        Logger.warning("Build version mismatch: expected #{@expected_build}, got #{packet.build}")
        response = build_denial(reason)
        {:reply, :server_auth_denied_realm, encode_packet(response), state}
    end
  end

  defp validate_build(@expected_build), do: :ok
  defp validate_build(_), do: {:error, :version_mismatch}

  defp authenticate(packet, state) do
    # Convert game token bytes to hex for database lookup
    game_token_hex = Base.encode16(packet.game_token)

    with {:ok, account} <- lookup_account(packet.email, game_token_hex),
         :ok <- check_suspension(account),
         {:ok, realm} <- get_realm(),
         {:ok, session_key} <- generate_session_key(account) do
      # Build responses
      accepted = %ServerAuthAccepted{}
      messages = %ServerRealmMessages{messages: []}
      realm_info = build_realm_info(account, realm, session_key)

      # Update session data
      state = put_in(state.session_data[:account_id], account.id)
      state = put_in(state.session_data[:session_key], session_key)

      # Send multiple responses
      responses = [
        {:server_auth_accepted_realm, encode_packet(accepted)},
        {:server_realm_messages, encode_packet(messages)},
        {:server_realm_info, encode_packet(realm_info)}
      ]

      {:reply_multi, responses, state}
    else
      {:error, reason} ->
        Logger.warning("Realm authentication failed: #{inspect(reason)}")
        {result, days} = denial_from_reason(reason)
        response = build_denial(result, days)
        {:reply, :server_auth_denied_realm, encode_packet(response), state}
    end
  end

  defp lookup_account(email, game_token) do
    case Accounts.get_by_token(email, game_token) do
      nil ->
        Logger.debug("Account not found or invalid token for email: #{email}")
        {:error, :invalid_token}

      account ->
        {:ok, account}
    end
  end

  defp check_suspension(account) do
    case Accounts.check_suspension(account) do
      :ok -> :ok
      {:error, :account_banned} -> {:error, :account_banned}
      {:error, {:account_suspended, days}} -> {:error, {:account_suspended, days}}
    end
  end

  defp get_realm do
    case Realms.get_first_online_realm() do
      nil ->
        Logger.warning("No online realms available")
        {:error, :no_realms_available}

      realm ->
        {:ok, realm}
    end
  end

  defp generate_session_key(account) do
    session_key = Random.bytes(16)
    hex_key = Base.encode16(session_key)

    case Accounts.update_session_key(account, hex_key) do
      {:ok, _} -> {:ok, session_key}
      {:error, _} -> {:error, :database_error}
    end
  end

  defp build_realm_info(account, realm, session_key) do
    %ServerRealmInfo{
      address: Realms.ip_to_uint32(realm.address),
      port: realm.port,
      session_key: session_key,
      account_id: account.id,
      realm_name: realm.name,
      flags: realm.flags,
      type: realm.type,
      note_text_id: realm.note_text_id
    }
  end

  defp build_denial(result, days \\ 0.0) do
    %ServerAuthDenied{
      result: result,
      error_value: 0,
      suspended_days: days
    }
  end

  defp denial_from_reason(:invalid_token), do: {:invalid_token, 0.0}
  defp denial_from_reason(:version_mismatch), do: {:version_mismatch, 0.0}
  defp denial_from_reason(:account_banned), do: {:account_banned, 0.0}
  defp denial_from_reason({:account_suspended, days}), do: {:account_suspended, days / 1.0}
  defp denial_from_reason(:no_realms_available), do: {:no_realms_available, 0.0}
  defp denial_from_reason(:database_error), do: {:database_error, 0.0}
  defp denial_from_reason(_), do: {:unknown, 0.0}

  defp encode_packet(%ServerAuthDenied{} = packet) do
    writer = PacketWriter.new()
    {:ok, writer} = ServerAuthDenied.write(packet, writer)
    PacketWriter.to_binary(writer)
  end

  defp encode_packet(%ServerAuthAccepted{} = packet) do
    writer = PacketWriter.new()
    {:ok, writer} = ServerAuthAccepted.write(packet, writer)
    PacketWriter.to_binary(writer)
  end

  defp encode_packet(%ServerRealmMessages{} = packet) do
    writer = PacketWriter.new()
    {:ok, writer} = ServerRealmMessages.write(packet, writer)
    PacketWriter.to_binary(writer)
  end

  defp encode_packet(%ServerRealmInfo{} = packet) do
    writer = PacketWriter.new()
    {:ok, writer} = ServerRealmInfo.write(packet, writer)
    PacketWriter.to_binary(writer)
  end
end
