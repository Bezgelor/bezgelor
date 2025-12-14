defmodule Mix.Tasks.Bezgelor.Status do
  @moduledoc """
  Check status of Bezgelor game servers.

  ## Usage

      mix bezgelor.status

  ## Output

  Shows running status for each server:
  - Portal (4000)
  - Auth (6600)
  - Realm (23115)
  - World (24000)
  - PostgreSQL (Docker)
  """

  use Mix.Task

  @shortdoc "Check status of Bezgelor game servers"

  @servers [
    {:portal, 4000, "Portal (Web Admin)"},
    {:auth, 6600, "Auth (STS)"},
    {:realm, 23115, "Realm"},
    {:world, 24000, "World"}
  ]

  @impl Mix.Task
  def run(_args) do
    Mix.shell().info("==> Bezgelor Server Status")
    Mix.shell().info("")

    # Check each server
    server_statuses =
      Enum.map(@servers, fn {_name, port, label} ->
        status = check_port(port)
        {label, port, status}
      end)

    # Display server statuses
    Enum.each(server_statuses, fn {label, port, status} ->
      status_str = if status, do: "✓ Running", else: "✗ Stopped"
      Mix.shell().info("    #{String.pad_trailing(label, 20)} :#{port}  #{status_str}")
    end)

    # Check PostgreSQL
    Mix.shell().info("")
    postgres_status = check_postgres()
    postgres_str = if postgres_status, do: "✓ Running", else: "✗ Stopped"
    Mix.shell().info("    #{String.pad_trailing("PostgreSQL", 20)} :5433  #{postgres_str}")

    Mix.shell().info("")

    # Summary
    running_count = Enum.count(server_statuses, fn {_, _, status} -> status end)
    total_count = length(server_statuses)

    cond do
      running_count == 0 and not postgres_status ->
        Mix.shell().info("All servers stopped.")

      running_count == total_count and postgres_status ->
        Mix.shell().info("All servers running.")

      true ->
        Mix.shell().info("#{running_count}/#{total_count} game servers running.")
    end
  end

  defp check_port(port) do
    case System.cmd("lsof", ["-ti:#{port}"], stderr_to_stdout: true) do
      {output, 0} -> String.trim(output) != ""
      _ -> false
    end
  end

  defp check_postgres do
    case System.cmd("docker", ["compose", "ps", "postgres"], stderr_to_stdout: true) do
      {output, 0} -> String.contains?(output, "running")
      _ -> false
    end
  end
end
