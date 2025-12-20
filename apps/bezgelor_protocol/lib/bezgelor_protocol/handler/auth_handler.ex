defmodule BezgelorProtocol.Handler.AuthHandler do
  @moduledoc """
  Handler for ClientHelloAuth packets.

  This handler processes the initial authentication request from clients
  and performs the SRP6 authentication handshake.

  ## Authentication Flow

  1. Parse ClientHelloAuth packet
  2. Validate build version (must be 16042)
  3. Look up account by email
  4. Verify SRP6 credentials (A, M1)
  5. Generate game token and session key
  6. Send ServerAuthAccepted with M2 and game token
  """

  @behaviour BezgelorProtocol.Handler

  alias BezgelorProtocol.Packets.{ClientHelloAuth, ServerAuthAccepted, ServerAuthDenied}
  alias BezgelorProtocol.{PacketReader, PacketWriter}
  alias BezgelorCrypto.{Random, SRP6}
  alias BezgelorDb.Accounts

  require Logger

  @expected_build 16042

  # Rate limiting: max 5 auth attempts per minute per IP
  @rate_limit_scale 60_000
  @rate_limit_count 5

  @impl true
  def handle(payload, state) do
    reader = PacketReader.new(payload)

    # Parse the packet first
    case ClientHelloAuth.read(reader) do
      {:ok, packet, _reader} ->
        # Store email in session for later use
        state = put_in(state.session_data[:email], packet.email)

        # Check rate limit before processing auth
        client_ip = get_client_ip(state)

        case check_rate_limit(client_ip) do
          {:allow, _count} ->
            process_auth(packet, state)

          {:deny, _limit} ->
            Logger.warning("Rate limit exceeded for IP: #{client_ip}")
            response = build_denial(:rate_limited)
            {:reply, :server_auth_denied, encode_packet(response), state}
        end

      {:error, reason} ->
        Logger.warning("Failed to parse ClientHelloAuth: #{inspect(reason)}")
        response = build_denial(:unknown)
        {:reply, :server_auth_denied, encode_packet(response), state}
    end
  end

  # Check rate limit using Hammer
  defp check_rate_limit(client_ip) do
    BezgelorProtocol.RateLimiter.hit("auth:#{client_ip}", @rate_limit_scale, @rate_limit_count)
  end

  # Extract client IP from state (stored by connection handler)
  defp get_client_ip(state) do
    case state do
      %{peer_ip: ip} when is_tuple(ip) -> :inet.ntoa(ip) |> to_string()
      %{peer_ip: ip} when is_binary(ip) -> ip
      _ -> "unknown"
    end
  end

  defp process_auth(packet, state) do
    with :ok <- validate_build(packet.build),
         {:ok, response, state} <- authenticate(packet, state) do
      {:reply, :server_auth_accepted, encode_packet(response), state}
    else
      {:error, reason} ->
        Logger.warning("Authentication failed: #{inspect(reason)}")
        response = build_denial(reason)
        {:reply, :server_auth_denied, encode_packet(response), state}
    end
  end

  # Validate the client build version
  defp validate_build(@expected_build), do: :ok

  defp validate_build(build) do
    Logger.warning("Build version mismatch: expected #{@expected_build}, got #{build}")
    {:error, :version_mismatch}
  end

  # Authenticate the client using SRP6
  defp authenticate(packet, state) do
    with {:ok, account} <- lookup_account(packet.email),
         :ok <- check_suspension(account),
         {:ok, server_proof_m2, session_key} <- verify_srp6(account, packet),
         {:ok, game_token} <- generate_game_token(account),
         {:ok, _account} <- store_session_key(account, session_key) do
      response = %ServerAuthAccepted{
        server_proof_m2: server_proof_m2,
        game_token: game_token
      }

      # Store account ID in session for later use
      state = put_in(state.session_data[:account_id], account.id)
      state = put_in(state.session_data[:session_key], session_key)

      {:ok, response, state}
    end
  end

  # Look up account by email
  defp lookup_account(email) do
    case Accounts.get_by_email(email) do
      nil ->
        Logger.debug("Account not found for email: #{email}")
        {:error, :account_not_found}

      account ->
        {:ok, account}
    end
  end

  # Check if account is suspended or banned
  defp check_suspension(account) do
    case Accounts.check_suspension(account) do
      :ok ->
        :ok

      {:error, :account_banned} ->
        Logger.debug("Account banned: #{account.email}")
        {:error, :account_banned}

      {:error, {:account_suspended, days}} ->
        Logger.debug("Account suspended: #{account.email} (#{days} days remaining)")
        {:error, {:account_suspended, days}}
    end
  end

  # Verify SRP6 credentials and return server proof M2
  defp verify_srp6(account, packet) do
    # Decode salt and verifier from hex strings
    salt = Base.decode16!(account.salt, case: :mixed)
    verifier = Base.decode16!(account.verifier, case: :mixed)

    # Create SRP6 server session
    {:ok, server} = SRP6.new_server(account.email, salt, verifier)

    # Generate server credentials (B) - needed internally
    {:ok, _server_b, server} = SRP6.server_credentials(server)

    # Process client's public key A
    case SRP6.calculate_secret(server, packet.client_key_a) do
      {:ok, server} ->
        # Calculate session key
        {:ok, session_key, server} = SRP6.calculate_session_key(server)

        # Verify client evidence M1
        case SRP6.verify_client_evidence(server, packet.client_proof_m1) do
          {:ok, server} ->
            # Generate server evidence M2
            {:ok, server_m2} = SRP6.server_evidence(server)
            {:ok, server_m2, session_key}

          {:error, :invalid_evidence} ->
            Logger.debug("Invalid SRP6 evidence for account: #{account.email}")
            {:error, :invalid_credentials}
        end

      {:error, :invalid_public_key} ->
        Logger.debug("Invalid SRP6 public key for account: #{account.email}")
        {:error, :invalid_credentials}
    end
  end

  # Generate and store a game token
  defp generate_game_token(account) do
    token = Random.bytes(16)
    token_hex = Base.encode16(token)

    case Accounts.update_game_token(account, token_hex) do
      {:ok, _account} ->
        {:ok, token}

      {:error, _changeset} ->
        {:error, :database_error}
    end
  end

  # Store the session key for later use
  defp store_session_key(account, session_key) do
    session_key_hex = Base.encode16(session_key)
    Accounts.update_session_key(account, session_key_hex)
  end

  # Build a denial response for various error conditions
  defp build_denial(reason) do
    {result, error_value, suspended_days} = denial_params(reason)

    %ServerAuthDenied{
      result: result,
      error_value: error_value,
      suspended_days: suspended_days
    }
  end

  defp denial_params(:version_mismatch), do: {:version_mismatch, 0, 0.0}
  defp denial_params(:account_not_found), do: {:invalid_token, 0, 0.0}
  defp denial_params(:invalid_credentials), do: {:invalid_token, 0, 0.0}
  defp denial_params(:database_error), do: {:database_error, 0, 0.0}
  defp denial_params(:account_banned), do: {:account_banned, 0, 0.0}
  # No specific code for rate limiting
  defp denial_params(:rate_limited), do: {:unknown, 0, 0.0}
  defp denial_params({:account_suspended, days}), do: {:account_suspended, 0, days / 1.0}
  defp denial_params(_unknown), do: {:unknown, 0, 0.0}

  # Encode a packet struct to binary
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
end
