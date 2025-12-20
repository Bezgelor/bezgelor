defmodule BezgelorPortalWeb.Admin.AdminDashboardLive do
  @moduledoc """
  Admin Dashboard LiveView - main landing page for admin panel.

  Shows:
  - Quick stats (accounts, characters, server status)
  - Recent admin actions from audit log
  - Links to common admin actions
  """
  use BezgelorPortalWeb, :live_view

  alias BezgelorDb.{Accounts, Authorization}
  alias BezgelorPortal.GameData
  alias BezgelorWorld.Portal

  @impl true
  def mount(_params, _session, socket) do
    account = socket.assigns.current_account
    permissions = Authorization.get_account_permissions(account)
    permission_keys = Enum.map(permissions, & &1.key)

    # Load stats
    stats = load_stats()

    # Load recent audit log entries (if user has permission)
    recent_actions =
      if "admin.view_audit_log" in permission_keys do
        Authorization.list_audit_log(limit: 10)
      else
        []
      end

    {:ok,
     assign(socket,
       page_title: nil,
       permissions: permission_keys,
       stats: stats,
       recent_actions: recent_actions,
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
    with {:ok, account_id} <- parse_int(params["account_id"], "Account ID"),
         {:ok, race_id} <- parse_int(params["race_id"], "Race"),
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
             "Created character #{character.name} (ID #{character.id})"
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
    with {:ok, account_id} <- parse_int(params["account_id"], "Account ID") do
      class_ids = batch_ids(params, "class_ids", truthy?(params["all_classes"]), class_options())
      race_ids = batch_ids(params, "race_ids", truthy?(params["all_races"]), race_options())
      sexes = batch_sexes(params)

      if class_ids == [] or race_ids == [] or sexes == [] do
        {:noreply, put_flash(socket, :error, "Select at least one class, race, and sex")}
      else
        creation_start = parse_int_default(params["creation_start"], 4)
        path_id = parse_int_default(params["path"], 0)
        name_prefix = string_or_default(params["name_prefix"], "Test")

        {created, failed} =
          for(class_id <- class_ids, race_id <- race_ids, sex <- sexes, reduce: {0, 0}) do
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
           "Batch create complete: #{created} created, #{failed} failed"
         )}
      end
    else
      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
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
        <h1 class="text-3xl font-bold">Admin Dashboard</h1>
      </div>
      
    <!-- Stats Cards -->
      <div class="stats shadow w-full bg-base-100">
        <div class="stat">
          <div class="stat-figure text-primary">
            <.icon name="hero-users" class="size-8" />
          </div>
          <div class="stat-title">Total Accounts</div>
          <div class="stat-value text-primary">{format_stat(@stats.account_count)}</div>
          <div class="stat-desc">Registered users</div>
        </div>

        <div class="stat">
          <div class="stat-figure text-secondary">
            <.icon name="hero-user-group" class="size-8" />
          </div>
          <div class="stat-title">Total Characters</div>
          <div class="stat-value text-secondary">{format_stat(@stats.character_count)}</div>
          <div class="stat-desc">Created characters</div>
        </div>

        <div class="stat">
          <div class="stat-figure text-info">
            <.icon name="hero-globe-alt" class="size-8" />
          </div>
          <div class="stat-title">Online Players</div>
          <div class="stat-value text-info">--</div>
          <div class="stat-desc">Real-time tracking coming soon</div>
        </div>

        <div class="stat">
          <div class="stat-figure text-success">
            <.icon name="hero-server" class="size-8" />
          </div>
          <div class="stat-title">Server Status</div>
          <div class="stat-value text-success">Online</div>
          <div class="stat-desc">Portal operational</div>
        </div>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <!-- Quick Actions -->
        <div class="lg:col-span-2 space-y-6">
          <h2 class="text-xl font-semibold">Quick Actions</h2>
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <.admin_card
              :if={"users.view" in @permissions}
              title="User Management"
              description="Search and manage player accounts"
              href="/admin/users"
              icon="hero-users"
            />

            <.admin_card
              :if={"characters.view" in @permissions}
              title="Character Management"
              description="View and manage characters"
              href="/admin/characters"
              icon="hero-user-group"
            />

            <.admin_card
              :if={"events.broadcast_message" in @permissions}
              title="Broadcast Message"
              description="Send server-wide announcements"
              href="/admin/events/broadcast"
              icon="hero-megaphone"
            />

            <.admin_card
              :if={"admin.view_audit_log" in @permissions}
              title="Audit Log"
              description="View admin action history"
              href="/admin/audit-log"
              icon="hero-document-text"
            />

            <.admin_card
              :if={"admin.manage_roles" in @permissions}
              title="Role Management"
              description="Manage roles and permissions"
              href="/admin/roles"
              icon="hero-shield-check"
            />

            <.admin_card
              :if={"server.view_logs" in @permissions}
              title="Server Logs"
              description="View server logs and errors"
              href="/admin/server/logs"
              icon="hero-command-line"
            />
          </div>
        </div>
        
    <!-- Recent Admin Actions -->
        <div class="space-y-4">
          <div class="flex items-center justify-between">
            <h2 class="text-xl font-semibold">Recent Activity</h2>
            <.link
              :if={"admin.view_audit_log" in @permissions}
              href="/admin/audit-log"
              class="text-sm link link-primary"
            >
              View all
            </.link>
          </div>

          <div class="card bg-base-100 shadow">
            <div class="card-body p-4">
              <%= if Enum.empty?(@recent_actions) do %>
                <div class="text-center py-6 text-base-content/50">
                  <.icon name="hero-clock" class="size-8 mx-auto mb-2" />
                  <p class="text-sm">No recent admin actions</p>
                </div>
              <% else %>
                <ul class="space-y-3">
                  <li :for={action <- @recent_actions} class="flex items-start gap-3 text-sm">
                    <div class={"p-1.5 rounded-full #{action_color(action.action)}"}>
                      <.icon name={action_icon(action.action)} class="size-3" />
                    </div>
                    <div class="flex-1 min-w-0">
                      <p class="font-medium truncate">{format_action(action.action)}</p>
                      <p class="text-xs text-base-content/50">
                        {format_relative_time(action.inserted_at)}
                      </p>
                    </div>
                  </li>
                </ul>
              <% end %>
            </div>
          </div>
        </div>
      </div>

      <div class="space-y-4">
        <div class="flex items-center justify-between">
          <h2 class="text-xl font-semibold">Testing Tools</h2>
          <span class="text-xs text-base-content/60">Admin-only helpers</span>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-3 gap-4">
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
                <.input field={@create_form[:account_id]} type="number" label="Account ID" />
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
                <.input field={@batch_form[:account_id]} type="number" label="Account ID" />
                <.input field={@batch_form[:name_prefix]} type="text" label="Name Prefix" />

                <.input
                  field={@batch_form[:all_classes]}
                  type="checkbox"
                  label="All Classes"
                />
                <.input
                  field={@batch_form[:class_ids]}
                  type="select"
                  label="Classes"
                  options={@class_options}
                  multiple
                />

                <.input field={@batch_form[:all_races]} type="checkbox" label="All Races" />
                <.input
                  field={@batch_form[:race_ids]}
                  type="select"
                  label="Races"
                  options={@race_options}
                  multiple
                />

                <.input field={@batch_form[:all_sexes]} type="checkbox" label="All Sexes" />
                <.input
                  field={@batch_form[:sexes]}
                  type="select"
                  label="Sexes"
                  options={@sex_options}
                  multiple
                />

                <.input
                  field={@batch_form[:creation_start]}
                  type="select"
                  label="Creation Start"
                  options={@creation_start_options}
                />
                <.input field={@batch_form[:path]} type="select" label="Path" options={@path_options} />
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
    </div>
    """
  end

  attr :title, :string, required: true
  attr :description, :string, required: true
  attr :href, :string, required: true
  attr :icon, :string, required: true

  defp admin_card(assigns) do
    ~H"""
    <.link href={@href} class="card bg-base-100 shadow-md hover:shadow-lg transition-shadow">
      <div class="card-body p-4">
        <div class="flex items-center gap-3">
          <div class="p-2.5 rounded-lg bg-primary/10 text-primary">
            <.icon name={@icon} class="size-5" />
          </div>
          <div>
            <h3 class="font-semibold">{@title}</h3>
            <p class="text-xs text-base-content/70">{@description}</p>
          </div>
        </div>
      </div>
    </.link>
    """
  end

  # Load dashboard stats
  defp load_stats do
    %{
      account_count: Accounts.count_accounts(),
      character_count: Accounts.count_characters()
    }
  end

  defp build_create_form do
    to_form(
      %{
        "account_id" => "",
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
        "account_id" => "",
        "name_prefix" => "Test",
        "all_classes" => "true",
        "class_ids" => [],
        "all_races" => "true",
        "race_ids" => [],
        "all_sexes" => "true",
        "sexes" => [],
        "creation_start" => "4",
        "path" => "0"
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

  # Format stat for display
  defp format_stat(nil), do: "--"
  defp format_stat(n) when is_integer(n), do: format_number(n)

  defp format_number(n) when n >= 1_000_000 do
    "#{Float.round(n / 1_000_000, 1)}M"
  end

  defp format_number(n) when n >= 1_000 do
    "#{Float.round(n / 1_000, 1)}K"
  end

  defp format_number(n), do: to_string(n)

  # Format action name for display
  defp format_action(action) when is_binary(action) do
    action
    |> String.replace(".", " ")
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  # Get icon for action type
  defp action_icon(action) do
    cond do
      String.contains?(action, "ban") -> "hero-no-symbol"
      String.contains?(action, "unban") -> "hero-check-circle"
      String.contains?(action, "role") -> "hero-shield-check"
      String.contains?(action, "user") -> "hero-user"
      String.contains?(action, "character") -> "hero-user-group"
      String.contains?(action, "item") -> "hero-gift"
      String.contains?(action, "currency") -> "hero-currency-dollar"
      true -> "hero-cog-6-tooth"
    end
  end

  # Get color class for action type
  defp action_color(action) do
    cond do
      String.contains?(action, "ban") -> "bg-error/20 text-error"
      String.contains?(action, "unban") -> "bg-success/20 text-success"
      String.contains?(action, "delete") -> "bg-error/20 text-error"
      String.contains?(action, "grant") -> "bg-success/20 text-success"
      String.contains?(action, "create") -> "bg-info/20 text-info"
      true -> "bg-base-300 text-base-content"
    end
  end

  # Format relative time
  defp format_relative_time(datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, datetime, :second)

    cond do
      diff < 60 -> "Just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      diff < 604_800 -> "#{div(diff, 86400)}d ago"
      true -> Calendar.strftime(datetime, "%b %d")
    end
  end
end
