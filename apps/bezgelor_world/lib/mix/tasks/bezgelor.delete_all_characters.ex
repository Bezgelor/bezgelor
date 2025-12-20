defmodule Mix.Tasks.Bezgelor.DeleteAllCharacters do
  @moduledoc """
  Soft-delete all characters.

  ## Usage

      mix bezgelor.delete_all_characters --confirm [--hard]
  """

  use Mix.Task

  alias BezgelorWorld.Portal

  @shortdoc "Delete all characters (admin helper)"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _args, _} =
      OptionParser.parse(args,
        switches: [
          confirm: :boolean,
          hard: :boolean
        ],
        aliases: [
          y: :confirm
        ]
      )

    if opts[:confirm] do
      case Portal.delete_all_characters(hard: opts[:hard] || false) do
        {:ok, count} ->
          mode = if opts[:hard], do: "hard", else: "soft"
          Mix.shell().info("Deleted #{count} rows (#{mode})")

        {:error, reason} ->
          Mix.shell().error("Delete failed: #{inspect(reason)}")
      end
    else
      Mix.shell().error("Refusing to delete all characters without --confirm")
    end
  end
end
