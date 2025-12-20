defmodule BezgelorPortalWeb.Admin.TestingToolsLive do
  @moduledoc """
  Admin Testing Tools LiveView.

  Provides development/testing utilities:
  - Create individual test characters
  - Batch create characters across all classes/races
  - Delete all characters (soft or hard)
  """
  use BezgelorPortalWeb, :live_view

  alias BezgelorPortal.GameData
  alias BezgelorWorld.Portal

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Testing Tools",
       create_form: build_create_form(),
       batch_form: build_batch_form(),
       delete_form: to_form(%{"confirm" => false, "hard" => false}, as: :delete_characters),
       class_options: class_options(),
       race_options: race_options(),
       sex_options: sex_options(),
       path_options: path_options(),
       creation_start_options: creation_start_options()
     ), layout: {BezgelorPortalWeb.Layouts, :admin}}
  end

  @impl true
  def handle_event("create_character", %{"create_character" => params}, socket) do
    account_id = socket.assigns.current_account.id

    with {:ok, race_id} <- parse_int(params["race_id"], "Race"),
         {:ok, class_id} <- parse_int(params["class_id"], "Class") do
      sex = parse_int_default(params["sex"], 0)
      creation_start = parse_int_default(params["creation_start"], 4)
      path_id = parse_int_default(params["path"], 0)
      faction_id = parse_optional_int(params["faction_id"])
      name_prefix = string_or_default(params["name_prefix"], "Test")
      auto_name = truthy?(params["auto_name"])
      name = if auto_name, do: :auto, else: blank_to_nil(params["name"])

      opts =
        []
        |> put_opt(:sex, sex)
        |> put_opt(:creation_start, creation_start)
        |> put_opt(:path, path_id)
        |> put_opt(:name_prefix, name_prefix)
        |> put_opt(:faction_id, faction_id)
        |> maybe_put_name(auto_name)

      case Portal.create_character(account_id, name, race_id, class_id, opts) do
        {:ok, character} ->
          {:noreply,
           socket
           |> put_flash(
             :info,
             "Created character #{character.name} (ID #{character.id}) on account #{account_id}"
           )}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Create failed: #{inspect(reason)}")}
      end
    else
      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  def handle_event("batch_create_characters", %{"batch_create" => params}, socket) do
    account_id = socket.assigns.current_account.id
    class_ids = batch_ids(params, "class_ids", truthy?(params["all_classes"]), class_options())
    race_ids = batch_ids(params, "race_ids", truthy?(params["all_races"]), race_options())
    sexes = batch_sexes(params)
    path_ids = batch_ids(params, "path_ids", truthy?(params["all_paths"]), path_options())

    if class_ids == [] or race_ids == [] or sexes == [] or path_ids == [] do
      {:noreply, put_flash(socket, :error, "Select at least one class, race, sex, and path")}
    else
      creation_start = parse_int_default(params["creation_start"], 4)
      name_prefix = string_or_default(params["name_prefix"], "Test")

      {created, failed} =
        for(
          class_id <- class_ids,
          race_id <- race_ids,
          sex <- sexes,
          path_id <- path_ids,
          reduce: {0, 0}
        ) do
          {ok_count, error_count} ->
            opts = [
              sex: sex,
              creation_start: creation_start,
              path: path_id,
              name_prefix: name_prefix
            ]

            case Portal.create_character(account_id, :auto, race_id, class_id, opts) do
              {:ok, _} -> {ok_count + 1, error_count}
              {:error, _} -> {ok_count, error_count + 1}
            end
        end

      {:noreply,
       socket
       |> put_flash(
         :info,
         "Batch create complete: #{created} created, #{failed} failed on account #{account_id}"
       )}
    end
  end

  def handle_event("delete_all_characters", %{"delete_characters" => params}, socket) do
    if truthy?(params["confirm"]) do
      mode = if truthy?(params["hard"]), do: "hard", else: "soft"

      case Portal.delete_all_characters(hard: truthy?(params["hard"])) do
        {:ok, count} ->
          {:noreply,
           socket
           |> put_flash(:info, "Deleted #{count} characters (#{mode})")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Delete failed: #{inspect(reason)}")}
      end
    else
      {:noreply, put_flash(socket, :error, "Confirm deletion to proceed")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div>
        <h1 class="text-3xl font-bold">Testing Tools</h1>
        <p class="text-base-content/60 mt-1">Development utilities for character creation and cleanup</p>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-4 items-start">
        <div class="card bg-base-100 shadow">
          <div class="card-body space-y-4">
            <div>
              <h3 class="font-semibold">Create Character</h3>
              <p class="text-xs text-base-content/60">
                Create a single character for any race/class/sex.
              </p>
            </div>

            <.form
              for={@create_form}
              id="create-character-form"
              phx-submit="create_character"
              class="space-y-3"
            >
              <.input field={@create_form[:name]} type="text" label="Name (optional)" />
              <.input
                field={@create_form[:auto_name]}
                type="checkbox"
                label="Auto-generate name"
              />
              <.input field={@create_form[:name_prefix]} type="text" label="Name Prefix" />
              <.input
                field={@create_form[:race_id]}
                type="select"
                label="Race"
                options={@race_options}
              />
              <.input
                field={@create_form[:class_id]}
                type="select"
                label="Class"
                options={@class_options}
              />
              <.input field={@create_form[:sex]} type="select" label="Sex" options={@sex_options} />
              <.input
                field={@create_form[:faction_id]}
                type="number"
                label="Faction ID (optional)"
              />
              <.input
                field={@create_form[:creation_start]}
                type="select"
                label="Creation Start"
                options={@creation_start_options}
              />
              <.input
                field={@create_form[:path]}
                type="select"
                label="Path"
                options={@path_options}
              />
              <button type="submit" class="btn btn-primary w-full" id="create-character-submit">
                Create Character
              </button>
            </.form>
          </div>
        </div>

        <div class="card bg-base-100 shadow">
          <div class="card-body space-y-4">
            <div>
              <h3 class="font-semibold">Batch Create Characters</h3>
              <p class="text-xs text-base-content/60">
                Create combinations across classes/races/sexes.
              </p>
            </div>

            <.form
              for={@batch_form}
              id="batch-create-character-form"
              phx-submit="batch_create_characters"
              class="space-y-3"
            >
              <.input field={@batch_form[:name_prefix]} type="text" label="Name Prefix" />

              <.input
                field={@batch_form[:class_ids]}
                type="select"
                label="Classes"
                options={@class_options}
                multiple
                size={length(@class_options)}
              />
              <.input
                field={@batch_form[:all_classes]}
                type="checkbox"
                label="All Classes"
              />

              <.input
                field={@batch_form[:race_ids]}
                type="select"
                label="Races"
                options={@race_options}
                multiple
                size={length(@race_options)}
              />
              <.input field={@batch_form[:all_races]} type="checkbox" label="All Races" />

              <.input
                field={@batch_form[:sexes]}
                type="select"
                label="Sexes"
                options={@sex_options}
                multiple
                size={length(@sex_options)}
              />
              <.input field={@batch_form[:all_sexes]} type="checkbox" label="All Sexes" />

              <.input
                field={@batch_form[:path_ids]}
                type="select"
                label="Paths"
                options={@path_options}
                multiple
                size={length(@path_options)}
              />
              <.input field={@batch_form[:all_paths]} type="checkbox" label="All Paths" />

              <.input
                field={@batch_form[:creation_start]}
                type="select"
                label="Creation Start"
                options={@creation_start_options}
              />
              <button type="submit" class="btn btn-secondary w-full" id="batch-create-submit">
                Create Batch
              </button>
            </.form>
          </div>
        </div>

        <div class="card bg-base-100 shadow border border-error/30">
          <div class="card-body space-y-4">
            <div>
              <h3 class="font-semibold text-error">Delete All Characters</h3>
              <p class="text-xs text-base-content/60">
                Soft-deletes every character. Use only for testing resets.
              </p>
            </div>

            <.form
              for={@delete_form}
              id="delete-all-characters-form"
              phx-submit="delete_all_characters"
              class="space-y-3"
            >
              <.input
                field={@delete_form[:confirm]}
                type="checkbox"
                label="I understand this will delete all characters"
              />
              <.input
                field={@delete_form[:hard]}
                type="checkbox"
                label="Hard delete (purge all character data)"
              />
              <button type="submit" class="btn btn-error w-full" id="delete-all-characters-submit">
                Delete All Characters
              </button>
            </.form>

            <div class="text-xs text-base-content/60">
              Mix usage: <code>mix bezgelor.delete_all_characters --confirm [--hard]</code>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp build_create_form do
    to_form(
      %{
        "name" => "",
        "auto_name" => "true",
        "name_prefix" => "Test",
        "race_id" => "",
        "class_id" => "",
        "sex" => "0",
        "faction_id" => "",
        "creation_start" => "4",
        "path" => "0"
      },
      as: :create_character
    )
  end

  defp build_batch_form do
    to_form(
      %{
        "name_prefix" => "Test",
        "all_classes" => "true",
        "class_ids" => [],
        "all_races" => "true",
        "race_ids" => [],
        "all_sexes" => "true",
        "sexes" => [],
        "all_paths" => "true",
        "path_ids" => [],
        "creation_start" => "4"
      },
      as: :batch_create
    )
  end

  defp class_options do
    GameData.all_classes()
    |> Enum.map(fn {id, info} -> {"#{info.name} (#{id})", id} end)
    |> Enum.sort_by(fn {_label, id} -> id end)
  end

  defp race_options do
    GameData.all_races()
    |> Enum.map(fn {id, info} -> {"#{info.name} (#{id})", id} end)
    |> Enum.sort_by(fn {_label, id} -> id end)
  end

  defp sex_options do
    [{"Male (0)", 0}, {"Female (1)", 1}]
  end

  defp path_options do
    GameData.all_paths()
    |> Enum.map(fn {id, info} -> {"#{info.name} (#{id})", id} end)
    |> Enum.sort_by(fn {_label, id} -> id end)
  end

  defp creation_start_options do
    [
      {"Arkship (0)", 0},
      {"Demo01 (1)", 1},
      {"Demo02 (2)", 2},
      {"Nexus (3)", 3},
      {"PreTutorial (4)", 4},
      {"Level50 (5)", 5}
    ]
  end

  defp parse_int(nil, label), do: {:error, "#{label} is required"}

  defp parse_int(value, label) do
    case Integer.parse(to_string(value)) do
      {int, ""} -> {:ok, int}
      _ -> {:error, "#{label} is invalid"}
    end
  end

  defp parse_int_default(nil, default), do: default

  defp parse_int_default(value, default) when is_integer(default) do
    case Integer.parse(to_string(value)) do
      {int, ""} -> int
      _ -> default
    end
  end

  defp parse_optional_int(nil), do: nil
  defp parse_optional_int(""), do: nil

  defp parse_optional_int(value) do
    case Integer.parse(to_string(value)) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp truthy?(value) when value in [true, "true", "on", "1"], do: true
  defp truthy?(_), do: false

  defp string_or_default(value, default) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: default, else: trimmed
  end

  defp string_or_default(_, default), do: default

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(_), do: nil

  defp put_opt(opts, _key, nil), do: opts
  defp put_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp maybe_put_name(opts, true), do: Keyword.put(opts, :name, :auto)
  defp maybe_put_name(opts, _), do: opts

  defp batch_ids(params, key, use_all, options) do
    if use_all do
      Enum.map(options, fn {_label, id} -> id end)
    else
      params
      |> Map.get(key, [])
      |> List.wrap()
      |> Enum.map(&to_string/1)
      |> Enum.map(fn value ->
        case Integer.parse(value) do
          {id, ""} -> id
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)
    end
  end

  defp batch_sexes(params) do
    if truthy?(params["all_sexes"]) do
      [0, 1]
    else
      params
      |> Map.get("sexes", [])
      |> List.wrap()
      |> Enum.map(&to_string/1)
      |> Enum.map(fn value ->
        case Integer.parse(value) do
          {id, ""} -> id
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)
    end
  end
end
