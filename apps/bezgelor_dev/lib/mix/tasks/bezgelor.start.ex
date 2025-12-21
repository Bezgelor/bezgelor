defmodule Mix.Tasks.Bezgelor.Start do
  @moduledoc """
  Start all Bezgelor game servers.

  ## Usage

      mix bezgelor.start           # Interactive with IEx shell
      mix bezgelor.start --detach  # Background (detached)
      mix bezgelor.start --no-db   # Skip database startup check

  ## Servers Started

  - Portal:  http://localhost:4000 (web admin, localhost only)
  - Auth:    0.0.0.0:6600 (STS authentication, all interfaces)
  - Realm:   0.0.0.0:23115 (realm list, all interfaces)
  - World:   0.0.0.0:24000 (game world, all interfaces)

  ## Logs

  Debug output goes to `logs/dev.log` (rotating, 5MB x 3 files).
  Monitor with: `tail -f logs/dev.log`
  """

  use Mix.Task

  @shortdoc "Start all Bezgelor game servers"

  @ports %{
    portal: 4000,
    auth: 6600,
    realm: 23115,
    world: 24000
  }

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: [detach: :boolean, no_db: :boolean])

    unless opts[:no_db] do
      ensure_database()
    end

    # Check if servers are already running
    case running_servers() do
      [] ->
        :ok

      running ->
        Mix.shell().error("Servers already running on ports: #{inspect(running)}")
        Mix.shell().error("Run 'mix bezgelor.stop' first")
        exit({:shutdown, 1})
    end

    print_banner()

    if opts[:detach] do
      start_detached()
    else
      start_interactive()
    end
  end

  defp ensure_database do
    Mix.shell().info("==> Checking PostgreSQL...")

    case System.cmd("docker", ["compose", "ps", "postgres"], stderr_to_stdout: true) do
      {output, 0} when output != "" ->
        if String.contains?(output, "running") do
          Mix.shell().info("    PostgreSQL is running")
        else
          start_database()
        end

      _ ->
        start_database()
    end
  end

  defp start_database do
    Mix.shell().info("    Starting PostgreSQL...")
    System.cmd("docker", ["compose", "up", "-d"], into: IO.stream(:stdio, :line))

    Mix.shell().info("    Waiting for database...")
    wait_for_database(30)
  end

  defp wait_for_database(0), do: Mix.raise("Database failed to start")

  defp wait_for_database(retries) do
    case System.cmd(
           "docker",
           ["compose", "exec", "-T", "postgres", "pg_isready", "-U", "bezgelor"],
           stderr_to_stdout: true
         ) do
      {_, 0} ->
        Mix.shell().info("    PostgreSQL ready")

      _ ->
        Process.sleep(1000)
        wait_for_database(retries - 1)
    end
  end

  defp print_banner do
    IO.puts("")
    IO.puts(gradient_banner())
    IO.puts("")

    public_address = System.get_env("WORLD_PUBLIC_ADDRESS", "127.0.0.1")

    Mix.shell().info("""
        Portal:  http://localhost:#{@ports.portal}  (localhost only)
        Auth:    0.0.0.0:#{@ports.auth}             (all interfaces)
        Realm:   0.0.0.0:#{@ports.realm}            (all interfaces)
        World:   0.0.0.0:#{@ports.world}            (all interfaces)

        Clients: #{public_address}:#{@ports.world}
        Logs:    tail -F logs/dev.log
    """)
  end

  defp gradient_banner do
    # Orange to blue gradient colors (256-color ANSI)
    colors = [208, 214, 220, 184, 148, 112, 76, 45, 39, 33]

    # ASCII art for BEZGELOR - each line is a row
    art = [
      " ██████╗ ███████╗███████╗ ██████╗ ███████╗██╗      ██████╗ ██████╗ ",
      " ██╔══██╗██╔════╝╚══███╔╝██╔════╝ ██╔════╝██║     ██╔═══██╗██╔══██╗",
      " ██████╔╝█████╗    ███╔╝ ██║  ███╗█████╗  ██║     ██║   ██║██████╔╝",
      " ██╔══██╗██╔══╝   ███╔╝  ██║   ██║██╔══╝  ██║     ██║   ██║██╔══██╗",
      " ██████╔╝███████╗███████╗╚██████╔╝███████╗███████╗╚██████╔╝██║  ██║",
      " ╚═════╝ ╚══════╝╚══════╝ ╚═════╝ ╚══════╝╚══════╝ ╚═════╝ ╚═╝  ╚═╝"
    ]

    # "For science!" tagline (aligned 2 chars right of center)
    for_science = "                                          F o r   s c i e n c e !"

    # Calculate segment width for gradient
    width = String.length(Enum.at(art, 0))
    segment_width = div(width, length(colors))

    # Apply gradient to each line of ASCII art
    art_colored =
      Enum.map(art, fn line ->
        apply_gradient(line, colors, segment_width)
      end)

    # Apply gradient to tagline
    for_science_colored = apply_gradient(for_science, colors, segment_width)

    reset = "\e[0m"

    (art_colored ++ [for_science_colored])
    |> Enum.join("\n")
    |> Kernel.<>(reset)
  end

  defp apply_gradient(line, colors, segment_width) do
    line
    |> String.graphemes()
    |> Enum.with_index()
    |> Enum.map(fn {char, idx} ->
      color_idx = min(div(idx, segment_width), length(colors) - 1)
      color = Enum.at(colors, color_idx)
      "\e[38;5;#{color}m#{char}"
    end)
    |> Enum.join()
  end

  defp start_interactive do
    # Use IEx with phoenix server
    Mix.Task.run("app.start")
    Mix.Task.run("phx.server")
  end

  defp start_detached do
    Mix.shell().info("    Starting in background...")

    # Start detached using elixir --erl "-detached"
    args = ["--erl", "-detached", "-S", "mix", "phx.server"]

    port =
      Port.open({:spawn_executable, System.find_executable("elixir")}, [
        :binary,
        :exit_status,
        args: args,
        cd: File.cwd!(),
        env: [{~c"MIX_ENV", ~c"dev"}]
      ])

    # Give it a moment to start
    Process.sleep(2000)

    # Close the port (process continues in background)
    Port.close(port)

    Mix.shell().info("""

    Servers started in background.
    Use 'mix bezgelor.stop' to stop.
    Use 'mix bezgelor.status' to check status.
    """)
  end

  defp running_servers do
    @ports
    |> Enum.filter(fn {_name, port} -> port_in_use?(port) end)
    |> Enum.map(fn {name, port} -> {name, port} end)
  end

  defp port_in_use?(port) do
    case System.cmd("lsof", ["-ti:#{port}"], stderr_to_stdout: true) do
      {output, 0} -> String.trim(output) != ""
      _ -> false
    end
  end
end
