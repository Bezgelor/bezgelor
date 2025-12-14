defmodule Mix.Tasks.Bezgelor.Stop do
  @moduledoc """
  Stop all Bezgelor game servers.

  ## Usage

      mix bezgelor.stop           # Stop servers only
      mix bezgelor.stop --all     # Stop servers and PostgreSQL

  ## Servers Stopped

  - Portal:  localhost:4000
  - Auth:    localhost:6600
  - Realm:   localhost:23115
  - World:   localhost:24000
  """

  use Mix.Task

  @shortdoc "Stop all Bezgelor game servers"

  @ports [4000, 4002, 6600, 23115, 24000]

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: [all: :boolean])

    Mix.shell().info("==> Stopping Bezgelor servers...")

    pids = find_server_pids()

    if pids == [] do
      Mix.shell().info("    No servers running")
    else
      stop_processes(pids)
    end

    # Fallback: kill any beam processes matching bezgelor
    kill_beam_processes()

    if opts[:all] do
      Mix.shell().info("")
      Mix.shell().info("==> Stopping PostgreSQL...")
      System.cmd("docker", ["compose", "down"], stderr_to_stdout: true)
    end

    Mix.shell().info("")
    Mix.shell().info("All servers stopped.")
  end

  defp find_server_pids do
    @ports
    |> Enum.flat_map(fn port ->
      case System.cmd("lsof", ["-ti:#{port}"], stderr_to_stdout: true) do
        {output, 0} ->
          output
          |> String.split("\n", trim: true)
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))

        _ ->
          []
      end
    end)
    |> Enum.uniq()
  end

  defp stop_processes(pids) do
    Mix.shell().info("    Killing PIDs: #{Enum.join(pids, ", ")}")

    # Graceful kill first
    Enum.each(pids, fn pid ->
      System.cmd("kill", [pid], stderr_to_stdout: true)
    end)

    Process.sleep(1000)

    # Check for remaining processes
    remaining = find_server_pids()

    if remaining != [] do
      Mix.shell().info("    Force killing: #{Enum.join(remaining, ", ")}")

      Enum.each(remaining, fn pid ->
        System.cmd("kill", ["-9", pid], stderr_to_stdout: true)
      end)
    end
  end

  defp kill_beam_processes do
    System.cmd("pkill", ["-f", "beam.*bezgelor"], stderr_to_stdout: true)
    :ok
  end
end
