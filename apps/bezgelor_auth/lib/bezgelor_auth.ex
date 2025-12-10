defmodule BezgelorAuth do
  @moduledoc """
  STS Auth Server for Bezgelor (WildStar server emulator).

  ## Overview

  The Auth Server handles the initial authentication flow:

  1. Client connects to port 6600
  2. Server sends ServerHello with SRP6 parameters
  3. Client sends ClientHelloAuth with credentials
  4. Server verifies SRP6 proof
  5. Server sends ServerAuthAccepted with game token

  ## Starting the Server

  The server starts automatically when the application starts.
  Configure the port in config:

      config :bezgelor_auth,
        port: 6600

  ## Architecture

  The auth server uses:
  - Ranch for TCP connection handling
  - BezgelorProtocol for packet parsing/framing
  - BezgelorCrypto.SRP6 for authentication
  - BezgelorDb for account storage
  """

  @doc """
  Get the configured auth server port.
  """
  @spec port() :: non_neg_integer()
  def port do
    Application.get_env(:bezgelor_auth, :port, 6600)
  end
end
