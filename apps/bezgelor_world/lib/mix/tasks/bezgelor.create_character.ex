defmodule Mix.Tasks.Bezgelor.CreateCharacter do
  @moduledoc """
  Create a character for any race/class combination.

  ## Usage

      mix bezgelor.create_character ACCOUNT_ID RACE_ID CLASS_ID [options]

  ## Options

      --name NAME             Character name (omit for auto)
      --auto-name             Generate a unique name
      --name-prefix PREFIX    Prefix for auto-generated names (default: Test)
      --sex 0|1               Sex (default: 0)
      --faction-id ID         Override faction (166 Dominion, 167 Exile)
      --creation-start ID     CharacterCreationStart enum (default: 4)
      --path ID               Starting path (default: 0)
      --realm-id ID           Override realm id
  """

  use Mix.Task

  alias BezgelorWorld.Portal

  @shortdoc "Create a character (admin helper)"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, args, _} =
      OptionParser.parse(args,
        switches: [
          name: :string,
          auto_name: :boolean,
          name_prefix: :string,
          sex: :integer,
          faction_id: :integer,
          creation_start: :integer,
          path: :integer,
          realm_id: :integer
        ],
        aliases: [
          n: :name,
          s: :sex,
          f: :faction_id
        ]
      )

    case args do
      [account_id, race_id, class_id] ->
        do_create(account_id, race_id, class_id, opts)

      _ ->
        Mix.shell().error(
          "Usage: mix bezgelor.create_character ACCOUNT_ID RACE_ID CLASS_ID [options]"
        )
    end
  end

  defp do_create(account_id, race_id, class_id, opts) do
    with {:ok, account_id} <- parse_int(account_id, "account_id"),
         {:ok, race_id} <- parse_int(race_id, "race_id"),
         {:ok, class_id} <- parse_int(class_id, "class_id") do
      name =
        cond do
          opts[:auto_name] -> :auto
          is_binary(opts[:name]) -> opts[:name]
          true -> nil
        end

      result =
        Portal.create_character(
          account_id,
          name,
          race_id,
          class_id,
          Keyword.drop(opts, [:auto_name])
        )

      case result do
        {:ok, character} ->
          Mix.shell().info(
            "Created character #{character.name} (ID: #{character.id}) for account #{account_id}"
          )

        {:error, reason} ->
          Mix.shell().error("Failed to create character: #{inspect(reason)}")
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
