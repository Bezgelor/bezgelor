defmodule Mix.Tasks.Dungeon.Generate do
  @moduledoc """
  Mix task to generate boss encounter DSL modules from JSON encounter data.

  ## Usage

      # Generate all bosses from an encounter file
      mix dungeon.generate stormtalon_lair.json

      # Generate a specific boss
      mix dungeon.generate stormtalon_lair.json --boss stormtalon

      # Dry run (show output without writing)
      mix dungeon.generate stormtalon_lair.json --dry-run

      # Force overwrite existing files
      mix dungeon.generate stormtalon_lair.json --force

  ## Options

      --boss NAME    Generate only the specified boss (by name)
      --dry-run      Print generated code without writing files
      --force        Overwrite existing files
      --output DIR   Output directory (default: encounter/bosses/)

  """
  use Mix.Task

  alias BezgelorWorld.Encounter.Generator

  @shortdoc "Generate boss encounter scripts from JSON data"

  @default_data_path "apps/bezgelor_data/priv/data/encounters"
  @default_output_path "apps/bezgelor_world/lib/bezgelor_world/encounter/bosses"

  @impl Mix.Task
  def run(args) do
    {opts, args, _} =
      OptionParser.parse(args,
        switches: [
          boss: :string,
          dry_run: :boolean,
          force: :boolean,
          output: :string
        ],
        aliases: [
          b: :boss,
          n: :dry_run,
          f: :force,
          o: :output
        ]
      )

    case args do
      [] ->
        Mix.shell().error("Usage: mix dungeon.generate <filename.json> [options]")
        Mix.shell().error("")
        Mix.shell().error("Available encounter files:")
        list_encounter_files()

      [filename | _] ->
        generate(filename, opts)
    end
  end

  defp list_encounter_files do
    path = Path.join(File.cwd!(), @default_data_path)

    case File.ls(path) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".json"))
        |> Enum.each(&Mix.shell().info("  - #{&1}"))

      {:error, _} ->
        Mix.shell().error("  (no encounter files found)")
    end
  end

  defp generate(filename, opts) do
    data_path = Path.join([File.cwd!(), @default_data_path, filename])
    output_path = opts[:output] || Path.join(File.cwd!(), @default_output_path)

    Mix.shell().info("Loading encounter data from: #{data_path}")

    case File.read(data_path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, data} ->
            process_encounter_data(data, opts, output_path)

          {:error, reason} ->
            Mix.shell().error("Failed to parse JSON: #{inspect(reason)}")
        end

      {:error, reason} ->
        Mix.shell().error("Failed to read file: #{inspect(reason)}")
    end
  end

  defp process_encounter_data(data, opts, output_path) do
    instance_name = data["instance_name"] || "Unknown"
    bosses = data["bosses"] || []

    Mix.shell().info("Instance: #{instance_name}")
    Mix.shell().info("Found #{length(bosses)} bosses")

    bosses_to_generate =
      case opts[:boss] do
        nil ->
          bosses

        boss_name ->
          Enum.filter(bosses, fn boss ->
            String.downcase(boss["name"] || "") == String.downcase(boss_name)
          end)
      end

    if Enum.empty?(bosses_to_generate) do
      Mix.shell().error("No matching bosses found")
    else
      Enum.each(bosses_to_generate, fn boss ->
        generate_boss(boss, data, opts, output_path, instance_name)
      end)
    end
  end

  defp generate_boss(boss, encounter_data, opts, output_path, instance_name) do
    boss_name = boss["name"] || "Unknown"
    difficulty = boss["difficulty"] || "normal"

    Mix.shell().info("")
    Mix.shell().info("Generating: #{boss_name} (#{difficulty})")

    # Generate the Elixir module code
    code = Generator.generate_boss_module(boss, encounter_data)

    if opts[:dry_run] do
      Mix.shell().info("--- Generated Code ---")
      Mix.shell().info(code)
      Mix.shell().info("--- End Generated Code ---")
    else
      # Determine output filename
      module_name = Generator.boss_to_module_name(boss_name, difficulty)
      filename = Generator.module_to_filename(module_name)

      # Create instance subdirectory if needed
      instance_dir = Generator.instance_to_dirname(instance_name)
      full_output_path = Path.join(output_path, instance_dir)

      File.mkdir_p!(full_output_path)

      output_file = Path.join(full_output_path, filename)

      if File.exists?(output_file) && !opts[:force] do
        Mix.shell().error("  File exists: #{output_file}")
        Mix.shell().error("  Use --force to overwrite")
      else
        File.write!(output_file, code)
        Mix.shell().info("  Written: #{output_file}")
      end
    end
  end
end
