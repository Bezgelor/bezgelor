defmodule Mix.Tasks.Bezgelor.RefreshActionSetDefaults do
  @moduledoc """
  Force-refresh default action set shortcuts for a character.

  ## Usage

      mix bezgelor.refresh_action_set_defaults CHARACTER_ID [options]

  ## Options

      --spec-index N   Refresh a single spec index (default: character.active_spec)
      --all-specs      Refresh specs 0..3
  """

  use Mix.Task

  alias BezgelorWorld.Portal

  @shortdoc "Refresh default action set shortcuts (admin helper)"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, args, _} =
      OptionParser.parse(args,
        switches: [
          spec_index: :integer,
          all_specs: :boolean
        ],
        aliases: [
          s: :spec_index,
          a: :all_specs
        ]
      )

    case args do
      [character_id] ->
        do_refresh(character_id, opts)

      _ ->
        Mix.shell().error(
          "Usage: mix bezgelor.refresh_action_set_defaults CHARACTER_ID [options]"
        )
    end
  end

  defp do_refresh(character_id, opts) do
    with {:ok, character_id} <- parse_int(character_id, "character_id") do
      result =
        Portal.refresh_action_set_defaults(
          character_id,
          opts
        )

      case result do
        {:ok, info} ->
          Mix.shell().info(
            "Refreshed action set defaults for character #{info.character_id} " <>
              "specs=#{inspect(info.spec_indices)}"
          )

        {:error, :not_found} ->
          Mix.shell().error("Character #{character_id} not found")
      end
    else
      {:error, message} ->
        Mix.shell().error(message)
    end
  end

  defp parse_int(value, label) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> {:ok, int}
      _ -> {:error, "Invalid #{label}: #{value}"}
    end
  end
end
