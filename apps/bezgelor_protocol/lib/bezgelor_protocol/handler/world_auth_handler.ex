defmodule BezgelorProtocol.Handler.WorldAuthHandler do
  @moduledoc """
  Handler for ClientHelloRealm packets on the world server (port 24000).

  This handler validates session keys issued by the realm server
  and sends the character list to the client.

  ## Authentication Flow

  1. Parse ClientHelloRealm with session key
  2. Look up account by email + session key
  3. Load character list for account
  4. Send ServerCharacterList with all characters
  """

  @behaviour BezgelorProtocol.Handler

  alias BezgelorProtocol.Packets.World.{
    ClientHelloRealm,
    ServerCharacterList
  }

  alias BezgelorProtocol.{PacketReader, PacketWriter}
  alias BezgelorDb.{Accounts, Characters}

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
        # For world server, we just disconnect on error
        {:error, reason}
    end
  end

  defp process_auth(packet, state) do
    with {:ok, account} <- validate_session(packet),
         characters <- load_characters(account.id) do
      # Store account in session
      state = put_in(state.session_data[:account_id], account.id)

      # Build character list response
      response = ServerCharacterList.from_characters(characters)

      {:reply, :server_character_list, encode_packet(response), state}
    else
      {:error, reason} ->
        Logger.warning("World authentication failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp validate_session(packet) do
    # Session key comes as raw bytes, need to convert to hex for comparison
    session_key_hex = Base.encode16(packet.session_key)

    case Accounts.get_by_session_key(packet.email, session_key_hex) do
      nil ->
        Logger.debug("Invalid session for email: #{packet.email}")
        {:error, :invalid_session}

      account ->
        # Also verify account ID matches
        if account.id == packet.account_id do
          {:ok, account}
        else
          Logger.warning("Account ID mismatch: expected #{account.id}, got #{packet.account_id}")
          {:error, :account_mismatch}
        end
    end
  end

  defp load_characters(account_id) do
    Characters.list_characters(account_id)
  end

  defp encode_packet(%ServerCharacterList{} = packet) do
    writer = PacketWriter.new()
    {:ok, writer} = ServerCharacterList.write(packet, writer)
    PacketWriter.to_binary(writer)
  end
end
