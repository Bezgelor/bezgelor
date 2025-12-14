defmodule BezgelorCore.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    # Set up rotating file log in dev (keeps console clean, captures debug)
    setup_file_log()

    children = [
      # PubSub for real-time event broadcasting (achievements, etc.)
      {Phoenix.PubSub, name: BezgelorCore.PubSub}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: BezgelorCore.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Add rotating file log handler using Erlang's disk_log
  # Only in dev, configured via :bezgelor_core, :file_log
  defp setup_file_log do
    case Application.get_env(:bezgelor_core, :file_log) do
      nil ->
        :ok

      config ->
        path = Keyword.get(config, :path, "logs/dev.log")
        max_bytes = Keyword.get(config, :max_bytes, 5_000_000)
        max_files = Keyword.get(config, :max_files, 3)

        # Ensure logs directory exists
        path |> Path.dirname() |> File.mkdir_p!()

        # Add disk_log handler for rotating logs
        handler_config = %{
          config: %{
            file: String.to_charlist(path),
            max_no_bytes: max_bytes,
            max_no_files: max_files
          },
          level: :debug,
          formatter: {:logger_formatter, %{template: [:time, ~c" [", :level, ~c"] ", :msg, ~c"\n"]}}
        }

        case :logger.add_handler(:file_log, :logger_disk_log_h, handler_config) do
          :ok ->
            Logger.info("Rotating file log: #{path} (#{div(max_bytes, 1_000_000)}MB x #{max_files})")

          {:error, {:already_exist, _}} ->
            :ok

          {:error, reason} ->
            Logger.warning("Failed to setup file log: #{inspect(reason)}")
        end
    end
  end
end
