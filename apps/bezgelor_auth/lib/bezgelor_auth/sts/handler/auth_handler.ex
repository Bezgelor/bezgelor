defmodule BezgelorAuth.Sts.Handler.AuthHandler do
  @moduledoc """
  Handler for /Auth/* endpoints.

  Implements SRP6 authentication flow:
  1. LoginStart - Client sends email, server returns salt and B
  2. KeyData - Client sends A and M1, server verifies and returns M2
  3. LoginFinish - Complete login
  4. RequestGameToken - Get token to pass to realm server
  """

  require Logger

  alias BezgelorAuth.Sts.{Packet, Session}
  alias BezgelorDb.Accounts

  @doc """
  Handle /Auth/LoginStart

  Request body contains email.
  Response contains salt and B as base64-encoded binary.
  """
  @spec handle_login_start(Packet.t(), Session.t()) :: {:ok, binary(), Session.t()} | {:error, integer(), String.t(), Session.t()}
  def handle_login_start(packet, session) do
    if session.state != :connected do
      {:error, 400, "Bad Request", session}
    else
      # Parse the request body to get email
      case parse_login_start_request(packet.body) do
        {:ok, email} ->
          Logger.debug("[STS] LoginStart for: #{email}")

          case Accounts.get_by_email(email) do
            nil ->
              Logger.debug("[STS] Account not found: #{email}")
              {:error, 400, "Invalid credentials", session}

            account ->
              # Check if account is banned or suspended
              case Accounts.check_suspension(account) do
                {:error, :account_banned} ->
                  Logger.debug("[STS] Account is banned: #{email}")
                  {:error, 403, "Account banned", session}

                {:error, {:account_suspended, days}} ->
                  Logger.debug("[STS] Account is suspended: #{email} (#{days} days remaining)")
                  {:error, 403, "Account suspended", session}

                :ok ->
                  {:ok, new_session, salt, public_b} = Session.start_login(session, account)
                  response = build_login_start_response(salt, public_b)
                  {:ok, response, new_session}
              end
          end

        {:error, reason} ->
          Logger.warning("[STS] Invalid LoginStart request: #{inspect(reason)}")
          {:error, 400, "Bad Request", session}
      end
    end
  end

  @doc """
  Handle /Auth/KeyData

  Client sends A and M1, we verify and return M2.
  """
  @spec handle_key_data(Packet.t(), Session.t()) :: {:ok_init_encryption, binary(), Session.t()} | {:error, integer(), String.t(), Session.t()}
  def handle_key_data(packet, session) do
    if session.state != :login_start do
      {:error, 400, "Bad Request", session}
    else
      case parse_key_data_request(packet.body) do
        {:ok, client_public_a, client_proof_m1} ->
          case Session.key_exchange(session, client_public_a, client_proof_m1) do
            {:ok, new_session, server_proof_m2} ->
              response = build_key_data_response(server_proof_m2)
              # Signal that encryption should be initialized after sending this response
              {:ok_init_encryption, response, new_session}

            {:error, :invalid_proof} ->
              Logger.warning("[STS] Invalid client proof M1 - SRP6 authentication failed")
              Logger.warning("[STS] This usually means the password is wrong or the account was created with incompatible SRP6 credentials")
              {:error, 401, "Invalid credentials", session}

            {:error, reason} ->
              Logger.warning("[STS] Key exchange error: #{inspect(reason)}")
              {:error, 500, "Internal error", session}
          end

        {:error, reason} ->
          Logger.warning("[STS] Invalid KeyData request: #{inspect(reason)}")
          {:error, 400, "Bad Request", session}
      end
    end
  end

  @doc """
  Handle /Auth/LoginFinish

  Complete the login process.
  """
  @spec handle_login_finish(Packet.t(), Session.t()) :: {:ok, binary(), Session.t()} | {:error, integer(), String.t(), Session.t()}
  def handle_login_finish(_packet, session) do
    case Session.finish_login(session) do
      {:ok, new_session} ->
        # Return location and user info
        response = build_login_finish_response(new_session.account)
        {:ok, response, new_session}
    end
  end

  @doc """
  Handle /Auth/RequestGameToken

  Return a game token that the client will pass to the realm server.
  """
  @spec handle_request_game_token(Packet.t(), Session.t()) :: {:ok, binary(), Session.t()} | {:error, integer(), String.t(), Session.t()}
  def handle_request_game_token(_packet, session) do
    if session.state != :authenticated do
      {:error, 401, "Unauthorized", session}
    else
      # Get both token formats:
      # - game_token: GUID string for client (e.g., "e88d09e6-eced-85e4-...")
      # - game_token_raw: Raw hex for database matching client bytes (e.g., "E6098DE8...")
      game_token = Session.get_game_token(session)
      game_token_raw = Session.get_game_token_raw(session)

      # Store the RAW format in database - this matches what client sends to realm server
      account = session.account
      {:ok, _} = Accounts.update_game_token(account, game_token_raw)

      # Send the GUID string format to client
      response = build_game_token_response(game_token)
      {:ok, response, session}
    end
  end

  # Request parsing helpers

  defp parse_login_start_request(body) do
    # The request body is XML-like or just contains the email
    # For simplicity, try to extract email from XML or plain text
    cond do
      String.contains?(body, "<LoginName>") ->
        case Regex.run(~r/<LoginName>([^<]+)<\/LoginName>/, body) do
          [_, email] -> {:ok, String.trim(email)}
          _ -> {:error, :invalid_format}
        end

      String.contains?(body, "LoginName=") ->
        case Regex.run(~r/LoginName=([^\s&]+)/, body) do
          [_, email] -> {:ok, String.trim(email)}
          _ -> {:error, :invalid_format}
        end

      # Try base64 decode as binary format
      true ->
        try do
          decoded = Base.decode64!(body)
          # Binary format: length (4 bytes) + email bytes
          <<email_len::little-32, email_bytes::binary-size(email_len), _rest::binary>> = decoded
          {:ok, email_bytes}
        rescue
          _ ->
            # Last resort: treat the whole body as email
            if String.contains?(body, "@") do
              {:ok, String.trim(body)}
            else
              {:error, :invalid_format}
            end
        end
    end
  end

  defp parse_key_data_request(body) do
    try do
      # Client sends XML: <Request><KeyData>base64data</KeyData></Request>
      key_data =
        case Regex.run(~r/<KeyData>([^<]+)<\/KeyData>/, body) do
          [_, data] -> data
          _ -> body  # Fallback to raw body
        end

      # Base64 decode the key data
      decoded = Base.decode64!(key_data)
      # Binary format: A_len (4 bytes) + A + M1_len (4 bytes) + M1
      <<a_len::little-32, client_a::binary-size(a_len),
        m1_len::little-32, client_m1::binary-size(m1_len), _rest::binary>> = decoded
      {:ok, client_a, client_m1}
    rescue
      _ -> {:error, :invalid_format}
    end
  end

  # Response building helpers

  defp build_login_start_response(salt, public_b) do
    # Format: XML with base64(salt_len + salt + b_len + b)
    salt_len = byte_size(salt)
    b_len = byte_size(public_b)

    data = <<salt_len::little-32, salt::binary, b_len::little-32, public_b::binary>>
    key_data = Base.encode64(data)

    "<Reply><KeyData>#{key_data}</KeyData></Reply>"
  end

  defp build_key_data_response(server_proof_m2) do
    # Format: XML with base64(m2_len + m2)
    m2_len = byte_size(server_proof_m2)
    data = <<m2_len::little-32, server_proof_m2::binary>>
    key_data = Base.encode64(data)

    "<Reply><KeyData>#{key_data}</KeyData></Reply>"
  end

  defp build_login_finish_response(_account) do
    # Return XML with account info (no XML declaration per NexusForever)
    "<Reply>\n<LocationId></LocationId>\n<UserId></UserId>\n<UserCenter>0</UserCenter>\n<UserName></UserName>\n<AccessMask>1</AccessMask>\n</Reply>"
  end

  defp build_game_token_response(game_token) do
    # Return XML with game token (no XML declaration per NexusForever)
    "<Reply>\n<Token>#{game_token}</Token>\n</Reply>"
  end
end
