defmodule BezgelorApi.Router do
  @moduledoc """
  HTTP API Router for Bezgelor.

  ## Endpoints

  - `GET /api/v1/status` - Server status
  - `GET /api/v1/zones` - List active zones
  - `GET /api/v1/zones/:id` - Get zone details
  - `GET /api/v1/players/online` - Online player count
  """

  use Plug.Router

  alias BezgelorApi.Controllers.{StatusController, ZoneController, PlayerController}

  plug(Plug.Logger)
  plug(:match)

  plug(Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Jason
  )

  plug(:dispatch)

  # API v1 routes
  get "/api/v1/status" do
    StatusController.index(conn)
  end

  get "/api/v1/zones" do
    ZoneController.index(conn)
  end

  get "/api/v1/zones/:id" do
    ZoneController.show(conn, id)
  end

  get "/api/v1/players/online" do
    PlayerController.online(conn)
  end

  # Health check
  get "/health" do
    send_resp(conn, 200, "OK")
  end

  # Catch all
  match _ do
    send_resp(conn, 404, Jason.encode!(%{error: "Not found"}))
  end
end
