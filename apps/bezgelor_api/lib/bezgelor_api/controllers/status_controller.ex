defmodule BezgelorApi.Controllers.StatusController do
  @moduledoc """
  Controller for server status endpoints.
  """

  import Plug.Conn

  alias BezgelorWorld.WorldManager
  alias BezgelorWorld.Zone.InstanceSupervisor

  @doc """
  GET /api/v1/status

  Returns overall server status.
  """
  def index(conn) do
    status = %{
      status: "online",
      version: Application.spec(:bezgelor_api, :vsn) |> to_string(),
      uptime_seconds: uptime_seconds(),
      players_online: player_count(),
      zones_active: zone_count(),
      data_stats: data_stats()
    }

    json(conn, 200, status)
  end

  defp uptime_seconds do
    {uptime, _} = :erlang.statistics(:wall_clock)
    div(uptime, 1000)
  end

  defp player_count do
    try do
      WorldManager.session_count()
    rescue
      _ -> 0
    end
  end

  defp zone_count do
    try do
      InstanceSupervisor.instance_count()
    rescue
      _ -> 0
    end
  end

  defp data_stats do
    try do
      BezgelorData.stats()
    rescue
      _ -> %{}
    end
  end

  defp json(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
