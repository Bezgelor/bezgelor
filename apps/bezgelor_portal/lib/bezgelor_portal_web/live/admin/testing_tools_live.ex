defmodule BezgelorPortalWeb.Admin.TestingToolsLive do
  @moduledoc """
  Admin Testing Tools LiveView.

  Provides development/testing utilities:
  - Create individual test characters
  - Batch create characters across all classes/races
  - Delete all characters (soft or hard)

  Requires the `testing.manage` permission.
  """
  use BezgelorPortalWeb, :live_view

  alias BezgelorDb.Authorization
  alias BezgelorPortal.GameData
  alias BezgelorWorld.Portal

  import BezgelorPortalWeb.Helpers.FormHelpers

  @impl true
  def mount(_params, _session, socket) do
    # Check permission - permissions are loaded by require_admin hook
    if "testing.manage" not in socket.assigns.permissions do
      {:ok,
       socket
       |> put_flash(:error, "You don't have permission to access testing tools.")
       |> redirect(to: "/admin")}
    else
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
         creation_start_options: creation_start_options(),
         batch_in_progress: false,
         batch_progress: nil
       ), layout: {BezgelorPortalWeb.Layouts, :admin}}
    end
  end

  @impl true
  def handle_event("create_character", %{"create_character" => params}, socket) do
    account_id = socket.assigns.current_account.id

    with {:ok, race_id} <- parse_int(params["race_id"], "Race"),
         {:ok, class_id} <- parse_int(params["class_id"], "Class") do
      sex = parse_int_default(params["sex"], 0)
      creation_start = parse_int_default(params["creation_start"], 4)
      path_id = parse_int_default(params["path"], 0)
      name_prefix = string_or_default(params["name_prefix"], "Test")
      auto_name = truthy?(params["auto_name"])
      name = if auto_name, do: :auto, else: blank_to_nil(params["name"])

      opts =
        []
        |> put_opt(:sex, sex)
        |> put_opt(:creation_start, creation_start)
        |> put_opt(:path, path_id)
        |> put_opt(:name_prefix, name_prefix)
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
    if socket.assigns.batch_in_progress do
      {:noreply, put_flash(socket, :error, "Batch creation already in progress")}
    else
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

        # Calculate total combinations
        total = length(class_ids) * length(race_ids) * length(sexes) * length(path_ids)

        # Build list of all combinations
        combinations =
          for class_id <- class_ids,
              race_id <- race_ids,
              sex <- sexes,
              path_id <- path_ids do
            {class_id, race_id, sex, path_id}
          end

        # Start async batch creation
        opts = [creation_start: creation_start, name_prefix: name_prefix]
        send(self(), {:start_batch, account_id, combinations, opts})

        {:noreply,
         socket
         |> assign(batch_in_progress: true, batch_progress: %{total: total, created: 0, failed: 0})
         |> put_flash(:info, "Starting batch creation of #{total} characters...")}
      end
    end
  end

  def handle_event("delete_all_characters", %{"delete_characters" => params}, socket) do
    if truthy?(params["confirm"]) do
      hard_delete = truthy?(params["hard"])
      mode = if hard_delete, do: "hard", else: "soft"

      case Portal.delete_all_characters(hard: hard_delete) do
        {:ok, count} ->
          # Log the admin action
          Authorization.log_action(
            socket.assigns.current_account,
            "testing.delete_all_characters",
            nil,
            nil,
            %{mode: mode, count: count}
          )

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
  def handle_info({:start_batch, account_id, combinations, opts}, socket) do
    # Process batch in chunks to allow UI updates
    chunk_size = 10
    parent = self()

    Task.start(fn ->
      combinations
      |> Enum.chunk_every(chunk_size)
      |> Enum.reduce({0, 0}, fn chunk, {created, failed} ->
        {chunk_created, chunk_failed} =
          Enum.reduce(chunk, {0, 0}, fn {class_id, race_id, sex, path_id}, {ok, err} ->
            character_opts = [
              sex: sex,
              creation_start: opts[:creation_start],
              path: path_id,
              name_prefix: opts[:name_prefix]
            ]

            case Portal.create_character(account_id, :auto, race_id, class_id, character_opts) do
              {:ok, _} -> {ok + 1, err}
              {:error, _} -> {ok, err + 1}
            end
          end)

        new_created = created + chunk_created
        new_failed = failed + chunk_failed
        send(parent, {:batch_progress, new_created, new_failed})
        {new_created, new_failed}
      end)

      send(parent, {:batch_complete, account_id})
    end)

    {:noreply, socket}
  end

  def handle_info({:batch_progress, created, failed}, socket) do
    {:noreply,
     assign(socket, batch_progress: %{socket.assigns.batch_progress | created: created, failed: failed})}
  end

  def handle_info({:batch_complete, account_id}, socket) do
    %{total: total, created: created, failed: failed} = socket.assigns.batch_progress

    {:noreply,
     socket
     |> assign(batch_in_progress: false, batch_progress: nil)
     |> put_flash(
       :info,
       "Batch complete: #{created}/#{total} created, #{failed} failed on account #{account_id}"
     )}
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
              <%= if @batch_in_progress do %>
                <div class="space-y-2">
                  <div class="flex justify-between text-sm">
                    <span>Progress:</span>
                    <span>{@batch_progress.created + @batch_progress.failed} / {@batch_progress.total}</span>
                  </div>
                  <progress
                    class="progress progress-secondary w-full"
                    value={@batch_progress.created + @batch_progress.failed}
                    max={@batch_progress.total}
                  />
                  <div class="text-xs text-base-content/60">
                    Created: {@batch_progress.created} | Failed: {@batch_progress.failed}
                  </div>
                </div>
              <% else %>
                <button type="submit" class="btn btn-secondary w-full" id="batch-create-submit">
                  Create Batch
                </button>
              <% end %>
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
