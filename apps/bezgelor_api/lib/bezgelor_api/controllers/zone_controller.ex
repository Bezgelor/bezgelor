defmodule BezgelorApi.Controllers.ZoneController do
  @moduledoc """
  Controller for zone endpoints.
  """

  import Plug.Conn

  alias BezgelorWorld.Zone.{Instance, InstanceSupervisor}

  @doc """
  GET /api/v1/zones

  Returns list of active zone instances.
  """
  def index(conn) do
    instances =
      InstanceSupervisor.list_instances()
      |> Enum.map(fn {zone_id, instance_id, pid} ->
        info = Instance.info(pid)

        %{
          zone_id: zone_id,
          instance_id: instance_id,
          zone_name: info.zone_name,
          player_count: info.player_count,
          creature_count: info.creature_count,
          total_entities: info.total_entities
        }
      end)

    json(conn, 200, %{zones: instances, count: length(instances)})
  end

  @doc """
  GET /api/v1/zones/:id

  Returns details for a specific zone (all instances).
  """
  def show(conn, id) do
    zone_id = parse_id(id)

    case zone_id do
      nil ->
        json(conn, 400, %{error: "Invalid zone ID"})

      zone_id ->
        zone_data = get_zone_data(zone_id)
        instances = get_zone_instances(zone_id)

        if zone_data || length(instances) > 0 do
          response = %{
            zone_id: zone_id,
            zone_name: zone_data[:name] || "Unknown",
            instances: instances,
            instance_count: length(instances),
            total_players: Enum.sum(Enum.map(instances, & &1.player_count))
          }

          json(conn, 200, response)
        else
          json(conn, 404, %{error: "Zone not found"})
        end
    end
  end

  defp get_zone_data(zone_id) do
    case BezgelorData.get_zone(zone_id) do
      {:ok, zone} -> zone
      :error -> nil
    end
  rescue
    _ -> nil
  end

  defp get_zone_instances(zone_id) do
    InstanceSupervisor.list_instances_for_zone(zone_id)
    |> Enum.map(fn {instance_id, pid} ->
      info = Instance.info(pid)

      %{
        instance_id: instance_id,
        player_count: info.player_count,
        creature_count: info.creature_count,
        total_entities: info.total_entities
      }
    end)
  end

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp parse_id(id) when is_integer(id), do: id

  defp json(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
