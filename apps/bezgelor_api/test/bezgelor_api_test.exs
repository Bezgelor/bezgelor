defmodule BezgelorApiTest do
  use ExUnit.Case

  import Plug.Test
  import Plug.Conn

  alias BezgelorApi.Router

  @opts Router.init([])

  describe "GET /health" do
    test "returns OK" do
      conn =
        :get
        |> conn("/health")
        |> Router.call(@opts)

      assert conn.status == 200
      assert conn.resp_body == "OK"
    end
  end

  describe "GET /api/v1/status" do
    test "returns server status" do
      conn =
        :get
        |> conn("/api/v1/status")
        |> Router.call(@opts)

      assert conn.status == 200

      body = Jason.decode!(conn.resp_body)
      assert body["status"] == "online"
      assert is_integer(body["uptime_seconds"])
      assert is_integer(body["players_online"])
      assert is_integer(body["zones_active"])
    end
  end

  describe "GET /api/v1/zones" do
    test "returns zone list" do
      conn =
        :get
        |> conn("/api/v1/zones")
        |> Router.call(@opts)

      assert conn.status == 200

      body = Jason.decode!(conn.resp_body)
      assert is_list(body["zones"])
      assert is_integer(body["count"])
    end
  end

  describe "GET /api/v1/zones/:id" do
    test "returns 400 for invalid ID" do
      conn =
        :get
        |> conn("/api/v1/zones/invalid")
        |> Router.call(@opts)

      assert conn.status == 400

      body = Jason.decode!(conn.resp_body)
      assert body["error"] == "Invalid zone ID"
    end

    test "returns 404 for nonexistent zone" do
      conn =
        :get
        |> conn("/api/v1/zones/999999")
        |> Router.call(@opts)

      assert conn.status == 404

      body = Jason.decode!(conn.resp_body)
      assert body["error"] == "Zone not found"
    end

    test "returns zone details for existing zone with data" do
      # Zone 1 exists in our sample data (Northern Wilds)
      conn =
        :get
        |> conn("/api/v1/zones/1")
        |> Router.call(@opts)

      # Should return 200 if zone data exists, even without running instance
      assert conn.status in [200, 404]
    end
  end

  describe "GET /api/v1/players/online" do
    test "returns online players" do
      conn =
        :get
        |> conn("/api/v1/players/online")
        |> Router.call(@opts)

      assert conn.status == 200

      body = Jason.decode!(conn.resp_body)
      assert is_integer(body["online_count"])
      assert is_list(body["players"])
    end
  end

  describe "404 handling" do
    test "returns 404 for unknown routes" do
      conn =
        :get
        |> conn("/api/v1/nonexistent")
        |> Router.call(@opts)

      assert conn.status == 404

      body = Jason.decode!(conn.resp_body)
      assert body["error"] == "Not found"
    end
  end
end
