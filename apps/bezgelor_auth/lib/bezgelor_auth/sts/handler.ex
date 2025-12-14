defmodule BezgelorAuth.Sts.Handler do
  @moduledoc """
  STS request handler router.

  Routes incoming STS requests to the appropriate handler module.
  """

  require Logger

  alias BezgelorAuth.Sts.{Packet, Session}
  alias BezgelorAuth.Sts.Handler.{AuthHandler, StsHandler, GameAccountHandler}

  @doc """
  Handle an STS request and return {response_binary | nil, new_session, init_encryption?}.

  Returns nil for the response when no response should be sent (e.g., /Sts/Connect).
  The third element indicates if encryption should be initialized after sending the response.
  """
  @spec handle(Packet.t(), Session.t()) :: {binary() | nil, Session.t(), boolean()}
  def handle(packet, session) do
    sequence = Map.get(packet.headers, "s", "0")

    case route(packet.uri, packet, session) do
      {:ok, body, new_session} ->
        {Packet.ok_response(sequence, body), new_session, false}

      {:ok_init_encryption, body, new_session} ->
        # Response sent unencrypted, then encryption is initialized
        {Packet.ok_response(sequence, body), new_session, true}

      {:error, status_code, message, new_session} ->
        {Packet.error_response(sequence, status_code, message), new_session, false}

      {:no_response, new_session} ->
        {nil, new_session, false}
    end
  end

  # Route to appropriate handler based on URI
  defp route("/Sts/Connect", packet, session) do
    StsHandler.handle_connect(packet, session)
  end

  defp route("/Sts/Ping", packet, session) do
    StsHandler.handle_ping(packet, session)
  end

  defp route("/Auth/LoginStart", packet, session) do
    AuthHandler.handle_login_start(packet, session)
  end

  defp route("/Auth/KeyData", packet, session) do
    AuthHandler.handle_key_data(packet, session)
  end

  defp route("/Auth/LoginFinish", packet, session) do
    AuthHandler.handle_login_finish(packet, session)
  end

  defp route("/Auth/RequestGameToken", packet, session) do
    AuthHandler.handle_request_game_token(packet, session)
  end

  defp route("/GameAccount/ListMyAccounts", packet, session) do
    GameAccountHandler.handle_list_accounts(packet, session)
  end

  defp route(uri, _packet, session) do
    Logger.warning("[STS] Unknown URI: #{uri}")
    {:error, 404, "Not Found", session}
  end
end
