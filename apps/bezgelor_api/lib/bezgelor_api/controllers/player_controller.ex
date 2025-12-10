defmodule BezgelorApi.Controllers.PlayerController do
  @moduledoc """
  Controller for player endpoints.
  """

  import Plug.Conn

  alias BezgelorWorld.WorldManager

  @doc """
  GET /api/v1/players/online

  Returns online player count and basic info.
  """
  def online(conn) do
    sessions = get_sessions()

    players =
      Enum.map(sessions, fn {account_id, session} ->
        %{
          account_id: account_id,
          character_name: session.character_name,
          entity_guid: session.entity_guid
        }
      end)

    response = %{
      online_count: length(players),
      players: players
    }

    json(conn, 200, response)
  end

  defp get_sessions do
    try do
      WorldManager.list_sessions()
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
