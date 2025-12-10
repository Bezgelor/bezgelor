defmodule BezgelorApi do
  @moduledoc """
  REST API for Bezgelor server monitoring and administration.

  ## Endpoints

  - `GET /api/v1/status` - Server status
  - `GET /api/v1/zones` - List active zones
  - `GET /api/v1/zones/:id` - Zone details
  - `GET /api/v1/players/online` - Online players
  - `GET /health` - Health check

  ## Configuration

  Configure in `config/config.exs`:

      config :bezgelor_api,
        port: 4000,
        start_server: true
  """
end
