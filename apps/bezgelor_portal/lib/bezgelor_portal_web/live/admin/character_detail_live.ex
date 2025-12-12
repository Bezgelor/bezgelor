defmodule BezgelorPortalWeb.Admin.CharacterDetailLive do
  @moduledoc """
  Admin LiveView for viewing and managing individual characters.

  Features:
  - Character info display
  - Inventory/currencies view
  - Level modification
  - Teleport
  - Rename
  - Delete/Restore
  - Item grant (via mail)
  - Currency grant
  """
  use BezgelorPortalWeb, :live_view

  alias BezgelorDb.{Characters, Inventory, Authorization}
  alias BezgelorPortal.GameData

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    admin = socket.assigns.current_account
    permissions = Authorization.get_account_permissions(admin)
    permission_keys = Enum.map(permissions, & &1.key)

    case load_character(id) do
      {:ok, character} ->
        {:ok,
         socket
         |> assign(
           page_title: "Character: #{character.name}",
           character: character,
           permissions: permission_keys,
           active_tab: :overview,
           # Modal states
           show_level_modal: false,
           show_teleport_modal: false,
           show_rename_modal: false,
           show_currency_modal: false,
           show_item_modal: false,
           # Form data
           level_form: %{"level" => to_string(character.level)},
           teleport_form: %{"world_id" => "", "x" => "", "y" => "", "z" => ""},
           rename_form: %{"name" => character.name},
           currency_form: %{"type" => "money", "amount" => ""},
           item_form: %{"item_id" => "", "quantity" => "1"}
         )
         |> load_tab_data(:overview),
         layout: {BezgelorPortalWeb.Layouts, :admin}}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Character not found")
         |> push_navigate(to: ~p"/admin/characters"),
         layout: {BezgelorPortalWeb.Layouts, :admin}}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Header -->
      <div class="flex items-center justify-between">
        <div>
          <.link navigate={~p"/admin/characters"} class="text-sm text-base-content/70 hover:text-primary flex items-center gap-1">
            <.icon name="hero-arrow-left" class="size-4" />
            Back to Characters
          </.link>
          <h1 class="text-2xl font-bold mt-2 flex items-center gap-3">
            {@character.name}
            <span class="badge badge-lg" style={"background-color: #{GameData.class_color(@character.class)}; color: white"}>
              {GameData.class_name(@character.class)}
            </span>
          </h1>
          <p class="text-base-content/70">
            Level {@character.level} {GameData.race_name(@character.race)} •
            Owner: <.link navigate={~p"/admin/users/#{@character.account_id}"} class="link link-primary">{@character.account.email}</.link>
          </p>
        </div>
        <div class="flex gap-2">
          <%= if @character.deleted_at do %>
            <span class="badge badge-error badge-lg">Deleted</span>
          <% end %>
          <.faction_badge faction_id={@character.faction_id} />
        </div>
      </div>

      <!-- Actions Card -->
      <div class="card bg-base-100 shadow">
        <div class="card-body">
          <h2 class="card-title">Admin Actions</h2>
          <div class="flex flex-wrap gap-2 mt-2">
            <button
              :if={"characters.modify_level" in @permissions}
              type="button"
              class="btn btn-outline btn-sm"
              phx-click="show_level_modal"
            >
              <.icon name="hero-arrow-trending-up" class="size-4" />
              Set Level
            </button>

            <button
              :if={"characters.teleport" in @permissions}
              type="button"
              class="btn btn-outline btn-sm"
              phx-click="show_teleport_modal"
            >
              <.icon name="hero-map-pin" class="size-4" />
              Teleport
            </button>

            <button
              :if={"characters.rename" in @permissions}
              type="button"
              class="btn btn-outline btn-sm"
              phx-click="show_rename_modal"
            >
              <.icon name="hero-pencil" class="size-4" />
              Rename
            </button>

            <button
              :if={"characters.modify_currency" in @permissions}
              type="button"
              class="btn btn-outline btn-sm"
              phx-click="show_currency_modal"
            >
              <.icon name="hero-currency-dollar" class="size-4" />
              Grant Currency
            </button>

            <button
              :if={"characters.modify_items" in @permissions}
              type="button"
              class="btn btn-outline btn-sm"
              phx-click="show_item_modal"
            >
              <.icon name="hero-gift" class="size-4" />
              Grant Item
            </button>

            <%= if @character.deleted_at do %>
              <button
                :if={"characters.restore" in @permissions}
                type="button"
                class="btn btn-warning btn-sm"
                phx-click="restore_character"
                data-confirm="Are you sure you want to restore this character?"
              >
                <.icon name="hero-arrow-uturn-left" class="size-4" />
                Restore
              </button>
            <% else %>
              <button
                :if={"characters.delete" in @permissions}
                type="button"
                class="btn btn-error btn-outline btn-sm"
                phx-click="delete_character"
                data-confirm="Are you sure you want to delete this character?"
              >
                <.icon name="hero-trash" class="size-4" />
                Delete
              </button>
            <% end %>
          </div>
        </div>
      </div>

      <!-- Tabs -->
      <div role="tablist" class="tabs tabs-boxed bg-base-100 p-1 w-fit">
        <button
          :for={tab <- [:overview, :inventory, :currencies]}
          type="button"
          role="tab"
          class={"tab #{if @active_tab == tab, do: "tab-active"}"}
          phx-click="change_tab"
          phx-value-tab={tab}
        >
          {tab_label(tab)}
        </button>
      </div>

      <!-- Tab Content -->
      <div class="card bg-base-100 shadow">
        <div class="card-body">
          <%= case @active_tab do %>
            <% :overview -> %>
              <.overview_tab character={@character} />
            <% :inventory -> %>
              <.inventory_tab equipped_items={@equipped_items} inventory_items={@inventory_items} />
            <% :currencies -> %>
              <.currencies_tab currencies={@currencies} />
          <% end %>
        </div>
      </div>

      <!-- Modals -->
      <.level_modal
        :if={@show_level_modal}
        form={@level_form}
        current_level={@character.level}
      />

      <.teleport_modal
        :if={@show_teleport_modal}
        form={@teleport_form}
        character={@character}
      />

      <.rename_modal
        :if={@show_rename_modal}
        form={@rename_form}
      />

      <.currency_modal
        :if={@show_currency_modal}
        form={@currency_form}
      />

      <.item_modal
        :if={@show_item_modal}
        form={@item_form}
      />
    </div>
    """
  end

  # Tab components

  attr :character, :map, required: true

  defp overview_tab(assigns) do
    ~H"""
    <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
      <div>
        <h3 class="font-semibold mb-3">Character Info</h3>
        <div class="space-y-2 text-sm">
          <div class="flex justify-between">
            <span class="text-base-content/70">ID</span>
            <span class="font-mono">{@character.id}</span>
          </div>
          <div class="flex justify-between">
            <span class="text-base-content/70">Level</span>
            <span>{@character.level}</span>
          </div>
          <div class="flex justify-between">
            <span class="text-base-content/70">Total XP</span>
            <span>{format_number(@character.total_xp)}</span>
          </div>
          <div class="flex justify-between">
            <span class="text-base-content/70">Rested XP</span>
            <span>{format_number(@character.rest_bonus_xp)}</span>
          </div>
          <div class="flex justify-between">
            <span class="text-base-content/70">Path</span>
            <span>{GameData.path_name(@character.active_path)}</span>
          </div>
          <div class="flex justify-between">
            <span class="text-base-content/70">Play Time</span>
            <span>{GameData.format_play_time(@character.time_played_total)}</span>
          </div>
        </div>
      </div>

      <div>
        <h3 class="font-semibold mb-3">Location</h3>
        <div class="space-y-2 text-sm">
          <div class="flex justify-between">
            <span class="text-base-content/70">World ID</span>
            <span>{@character.world_id || "N/A"}</span>
          </div>
          <div class="flex justify-between">
            <span class="text-base-content/70">Zone ID</span>
            <span>{@character.world_zone_id || "N/A"}</span>
          </div>
          <div class="flex justify-between">
            <span class="text-base-content/70">Position</span>
            <span class="font-mono text-xs">
              {Float.round(@character.location_x, 2)},
              {Float.round(@character.location_y, 2)},
              {Float.round(@character.location_z, 2)}
            </span>
          </div>
        </div>
      </div>

      <div>
        <h3 class="font-semibold mb-3">Timestamps</h3>
        <div class="space-y-2 text-sm">
          <div class="flex justify-between">
            <span class="text-base-content/70">Created</span>
            <span>{format_datetime(@character.inserted_at)}</span>
          </div>
          <div class="flex justify-between">
            <span class="text-base-content/70">Last Online</span>
            <span>{format_datetime(@character.last_online)}</span>
          </div>
          <div :if={@character.deleted_at} class="flex justify-between">
            <span class="text-base-content/70">Deleted</span>
            <span class="text-error">{format_datetime(@character.deleted_at)}</span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :equipped_items, :list, required: true
  attr :inventory_items, :list, required: true

  defp inventory_tab(assigns) do
    ~H"""
    <div class="space-y-6">
      <div>
        <h3 class="font-semibold mb-3">Equipped Items ({length(@equipped_items)})</h3>
        <%= if Enum.empty?(@equipped_items) do %>
          <p class="text-base-content/50">No equipped items</p>
        <% else %>
          <div class="overflow-x-auto">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>Slot</th>
                  <th>Item ID</th>
                  <th>Stack</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={item <- @equipped_items}>
                  <td>{item.slot}</td>
                  <td class="font-mono">{item.item_id}</td>
                  <td>{item.quantity}</td>
                </tr>
              </tbody>
            </table>
          </div>
        <% end %>
      </div>

      <div>
        <h3 class="font-semibold mb-3">Inventory Items ({length(@inventory_items)})</h3>
        <%= if Enum.empty?(@inventory_items) do %>
          <p class="text-base-content/50">No inventory items</p>
        <% else %>
          <div class="overflow-x-auto">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>Bag</th>
                  <th>Slot</th>
                  <th>Item ID</th>
                  <th>Stack</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={item <- @inventory_items}>
                  <td>{item.container_type}</td>
                  <td>{item.bag_index}</td>
                  <td class="font-mono">{item.item_id}</td>
                  <td>{item.quantity}</td>
                </tr>
              </tbody>
            </table>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  attr :currencies, :list, required: true

  defp currencies_tab(assigns) do
    ~H"""
    <div>
      <h3 class="font-semibold mb-3">Currencies</h3>
      <%= if Enum.empty?(@currencies) do %>
        <p class="text-base-content/50">No currencies</p>
      <% else %>
        <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
          <div :for={currency <- @currencies} class="stat bg-base-200 rounded-lg">
            <div class="stat-figure text-primary">
              <.icon name={currency.icon || "hero-currency-dollar"} class="size-6" />
            </div>
            <div class="stat-title">{currency.name}</div>
            <div class="stat-value text-lg">{format_number(currency.amount)}</div>
            <div :if={currency.max} class="stat-desc">Max: {format_number(currency.max)}</div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # Modal components

  attr :form, :map, required: true
  attr :current_level, :integer, required: true

  defp level_modal(assigns) do
    ~H"""
    <.modal id="level-modal" show on_cancel={JS.push("hide_level_modal")}>
      <:title>Set Character Level</:title>
      <form phx-submit="set_level" class="space-y-4">
        <div class="form-control">
          <label class="label">
            <span class="label-text">Level (1-50)</span>
          </label>
          <input
            type="number"
            name="level"
            min="1"
            max="50"
            value={@form["level"]}
            class="input input-bordered"
            required
          />
          <label class="label">
            <span class="label-text-alt">Current: {@current_level}</span>
          </label>
        </div>
        <div class="modal-action">
          <button type="button" class="btn" phx-click="hide_level_modal">Cancel</button>
          <button type="submit" class="btn btn-primary">Set Level</button>
        </div>
      </form>
    </.modal>
    """
  end

  attr :form, :map, required: true
  attr :character, :map, required: true

  defp teleport_modal(assigns) do
    ~H"""
    <.modal id="teleport-modal" show on_cancel={JS.push("hide_teleport_modal")}>
      <:title>Teleport Character</:title>
      <form phx-submit="teleport" class="space-y-4">
        <div class="form-control">
          <label class="label">
            <span class="label-text">World ID</span>
          </label>
          <input
            type="number"
            name="world_id"
            value={@form["world_id"]}
            placeholder={to_string(@character.world_id)}
            class="input input-bordered"
          />
        </div>
        <div class="grid grid-cols-3 gap-2">
          <div class="form-control">
            <label class="label"><span class="label-text">X</span></label>
            <input type="text" name="x" value={@form["x"]} placeholder={Float.to_string(@character.location_x)} class="input input-bordered" />
          </div>
          <div class="form-control">
            <label class="label"><span class="label-text">Y</span></label>
            <input type="text" name="y" value={@form["y"]} placeholder={Float.to_string(@character.location_y)} class="input input-bordered" />
          </div>
          <div class="form-control">
            <label class="label"><span class="label-text">Z</span></label>
            <input type="text" name="z" value={@form["z"]} placeholder={Float.to_string(@character.location_z)} class="input input-bordered" />
          </div>
        </div>
        <p class="text-sm text-base-content/70">
          Leave fields empty to keep current values. Only works if character is offline.
        </p>
        <div class="modal-action">
          <button type="button" class="btn" phx-click="hide_teleport_modal">Cancel</button>
          <button type="submit" class="btn btn-primary">Teleport</button>
        </div>
      </form>
    </.modal>
    """
  end

  attr :form, :map, required: true

  defp rename_modal(assigns) do
    ~H"""
    <.modal id="rename-modal" show on_cancel={JS.push("hide_rename_modal")}>
      <:title>Rename Character</:title>
      <form phx-submit="rename" class="space-y-4">
        <div class="form-control">
          <label class="label">
            <span class="label-text">New Name</span>
          </label>
          <input
            type="text"
            name="name"
            value={@form["name"]}
            minlength="3"
            maxlength="24"
            class="input input-bordered"
            required
          />
          <label class="label">
            <span class="label-text-alt">3-24 characters, letters and numbers only</span>
          </label>
        </div>
        <div class="modal-action">
          <button type="button" class="btn" phx-click="hide_rename_modal">Cancel</button>
          <button type="submit" class="btn btn-primary">Rename</button>
        </div>
      </form>
    </.modal>
    """
  end

  attr :form, :map, required: true

  defp currency_modal(assigns) do
    ~H"""
    <.modal id="currency-modal" show on_cancel={JS.push("hide_currency_modal")}>
      <:title>Grant Currency</:title>
      <form phx-submit="grant_currency" class="space-y-4">
        <div class="form-control">
          <label class="label">
            <span class="label-text">Currency Type</span>
          </label>
          <select name="type" class="select select-bordered">
            <option value="1" selected={@form["type"] == "1"}>Gold</option>
            <option value="5" selected={@form["type"] == "5"}>Elder Gems</option>
            <option value="4" selected={@form["type"] == "4"}>Renown</option>
            <option value="7" selected={@form["type"] == "7"}>Prestige</option>
            <option value="6" selected={@form["type"] == "6"}>Glory</option>
            <option value="8" selected={@form["type"] == "8"}>Crafting Vouchers</option>
            <option value="9" selected={@form["type"] == "9"}>War Coins</option>
          </select>
        </div>
        <div class="form-control">
          <label class="label">
            <span class="label-text">Amount</span>
          </label>
          <input
            type="number"
            name="amount"
            value={@form["amount"]}
            class="input input-bordered"
            required
          />
          <label class="label">
            <span class="label-text-alt">Use negative values to remove currency</span>
          </label>
        </div>
        <div class="modal-action">
          <button type="button" class="btn" phx-click="hide_currency_modal">Cancel</button>
          <button type="submit" class="btn btn-primary">Grant Currency</button>
        </div>
      </form>
    </.modal>
    """
  end

  attr :form, :map, required: true

  defp item_modal(assigns) do
    ~H"""
    <.modal id="item-modal" show on_cancel={JS.push("hide_item_modal")}>
      <:title>Grant Item</:title>
      <form phx-submit="grant_item" class="space-y-4">
        <div class="form-control">
          <label class="label">
            <span class="label-text">Item ID</span>
          </label>
          <input
            type="number"
            name="item_id"
            value={@form["item_id"]}
            class="input input-bordered"
            required
          />
        </div>
        <div class="form-control">
          <label class="label">
            <span class="label-text">Quantity</span>
          </label>
          <input
            type="number"
            name="quantity"
            min="1"
            max="999"
            value={@form["quantity"]}
            class="input input-bordered"
            required
          />
        </div>
        <p class="text-sm text-base-content/70">
          Item will be sent via system mail.
        </p>
        <div class="modal-action">
          <button type="button" class="btn" phx-click="hide_item_modal">Cancel</button>
          <button type="submit" class="btn btn-primary">Grant Item</button>
        </div>
      </form>
    </.modal>
    """
  end

  attr :faction_id, :integer, required: true

  defp faction_badge(assigns) do
    faction = GameData.get_faction(assigns.faction_id)
    assigns = assign(assigns, :faction, faction)

    ~H"""
    <span class="badge badge-lg" style={"background-color: #{@faction.color}; color: white"}>
      {@faction.name}
    </span>
    """
  end

  # Event handlers

  @impl true
  def handle_event("change_tab", %{"tab" => tab}, socket) do
    tab = String.to_existing_atom(tab)
    {:noreply, socket |> assign(active_tab: tab) |> load_tab_data(tab)}
  end

  # Modal show/hide handlers
  @impl true
  def handle_event("show_level_modal", _, socket), do: {:noreply, assign(socket, show_level_modal: true)}
  def handle_event("hide_level_modal", _, socket), do: {:noreply, assign(socket, show_level_modal: false)}
  def handle_event("show_teleport_modal", _, socket), do: {:noreply, assign(socket, show_teleport_modal: true)}
  def handle_event("hide_teleport_modal", _, socket), do: {:noreply, assign(socket, show_teleport_modal: false)}
  def handle_event("show_rename_modal", _, socket), do: {:noreply, assign(socket, show_rename_modal: true)}
  def handle_event("hide_rename_modal", _, socket), do: {:noreply, assign(socket, show_rename_modal: false)}
  def handle_event("show_currency_modal", _, socket), do: {:noreply, assign(socket, show_currency_modal: true)}
  def handle_event("hide_currency_modal", _, socket), do: {:noreply, assign(socket, show_currency_modal: false)}
  def handle_event("show_item_modal", _, socket), do: {:noreply, assign(socket, show_item_modal: true)}
  def handle_event("hide_item_modal", _, socket), do: {:noreply, assign(socket, show_item_modal: false)}

  @impl true
  def handle_event("set_level", %{"level" => level_str}, socket) do
    admin = socket.assigns.current_account
    character = socket.assigns.character

    case Integer.parse(level_str) do
      {level, ""} when level >= 1 and level <= 50 ->
        case Characters.admin_set_level(character, level) do
          {:ok, updated} ->
            Authorization.log_action(admin, "character.set_level", "character", character.id, %{
              old_level: character.level,
              new_level: level
            })

            {:noreply,
             socket
             |> put_flash(:info, "Level set to #{level}")
             |> assign(character: updated, show_level_modal: false)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to set level")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Invalid level (must be 1-50)")}
    end
  end

  @impl true
  def handle_event("teleport", params, socket) do
    admin = socket.assigns.current_account
    character = socket.assigns.character

    attrs =
      %{}
      |> maybe_put_float(:location_x, params["x"])
      |> maybe_put_float(:location_y, params["y"])
      |> maybe_put_float(:location_z, params["z"])
      |> maybe_put_int(:world_id, params["world_id"])

    if map_size(attrs) == 0 do
      {:noreply, put_flash(socket, :error, "No changes specified")}
    else
      case Characters.admin_teleport(character, attrs) do
        {:ok, updated} ->
          Authorization.log_action(admin, "character.teleport", "character", character.id, attrs)

          {:noreply,
           socket
           |> put_flash(:info, "Character teleported")
           |> assign(character: updated, show_teleport_modal: false)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to teleport")}
      end
    end
  end

  @impl true
  def handle_event("rename", %{"name" => new_name}, socket) do
    admin = socket.assigns.current_account
    character = socket.assigns.character
    old_name = character.name

    case Characters.admin_rename(character, new_name) do
      {:ok, updated} ->
        Authorization.log_action(admin, "character.rename", "character", character.id, %{
          old_name: old_name,
          new_name: new_name
        })

        {:noreply,
         socket
         |> put_flash(:info, "Character renamed to #{new_name}")
         |> assign(character: updated, show_rename_modal: false, page_title: "Character: #{new_name}")}

      {:error, :name_taken} ->
        {:noreply, put_flash(socket, :error, "Name is already taken")}

      {:error, :invalid_name} ->
        {:noreply, put_flash(socket, :error, "Invalid name format")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to rename character")}
    end
  end

  @impl true
  def handle_event("grant_currency", %{"type" => type_str, "amount" => amount_str}, socket) do
    admin = socket.assigns.current_account
    character = socket.assigns.character

    with {currency_id, ""} <- Integer.parse(type_str),
         {amount, ""} <- Integer.parse(amount_str),
         currency_type when not is_nil(currency_type) <- currency_id_to_atom(currency_id) do
      case Inventory.modify_currency(character.id, currency_type, amount) do
        {:ok, _} ->
          Authorization.log_action(admin, "character.grant_currency", "character", character.id, %{
            currency_type: currency_type,
            amount: amount
          })

          {:noreply,
           socket
           |> put_flash(:info, "Currency granted")
           |> assign(show_currency_modal: false)
           |> load_tab_data(:currencies)}

        {:error, :insufficient_funds} ->
          {:noreply, put_flash(socket, :error, "Insufficient funds for removal")}

        {:error, :invalid_currency} ->
          {:noreply, put_flash(socket, :error, "Invalid currency type")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to grant currency")}
      end
    else
      nil -> {:noreply, put_flash(socket, :error, "Unknown currency type")}
      _ -> {:noreply, put_flash(socket, :error, "Invalid input")}
    end
  end

  @impl true
  def handle_event("grant_item", %{"item_id" => item_id_str, "quantity" => qty_str}, socket) do
    admin = socket.assigns.current_account
    character = socket.assigns.character

    with {item_id, ""} <- Integer.parse(item_id_str),
         {quantity, ""} <- Integer.parse(qty_str) do
      # Send via mail system
      case BezgelorDb.Mail.send_system_mail(character.id, "Admin Item Grant", "You have received an item from an administrator.", attachments: [{item_id, quantity}]) do
        {:ok, _} ->
          Authorization.log_action(admin, "character.grant_item", "character", character.id, %{
            item_id: item_id,
            quantity: quantity
          })

          {:noreply,
           socket
           |> put_flash(:info, "Item sent via mail")
           |> assign(show_item_modal: false)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to send item")}
      end
    else
      _ -> {:noreply, put_flash(socket, :error, "Invalid input")}
    end
  end

  @impl true
  def handle_event("delete_character", _, socket) do
    admin = socket.assigns.current_account
    character = socket.assigns.character

    case Characters.admin_delete_character(character) do
      {:ok, updated} ->
        Authorization.log_action(admin, "character.delete", "character", character.id, %{
          name: character.name
        })

        {:noreply,
         socket
         |> put_flash(:info, "Character deleted")
         |> assign(character: updated)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete character")}
    end
  end

  @impl true
  def handle_event("restore_character", _, socket) do
    admin = socket.assigns.current_account
    character = socket.assigns.character

    case Characters.admin_restore_character(character) do
      {:ok, updated} ->
        Authorization.log_action(admin, "character.restore", "character", character.id, %{
          name: updated.name
        })

        {:noreply,
         socket
         |> put_flash(:info, "Character restored")
         |> assign(character: updated)}

      {:error, :name_taken} ->
        {:noreply, put_flash(socket, :error, "Cannot restore: original name is taken")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to restore character")}
    end
  end

  # Helpers

  defp load_character(id) do
    case Integer.parse(id) do
      {id_int, ""} ->
        case Characters.get_character_for_admin(id_int) do
          nil -> {:error, :not_found}
          character -> {:ok, character}
        end

      _ ->
        {:error, :not_found}
    end
  end

  defp load_tab_data(socket, :overview) do
    assign(socket,
      equipped_items: [],
      inventory_items: [],
      currencies: []
    )
  end

  defp load_tab_data(socket, :inventory) do
    character_id = socket.assigns.character.id
    all_items = Inventory.get_items(character_id)

    equipped = Enum.filter(all_items, &(&1.container_type == :equipped))
    inventory = Enum.filter(all_items, &(&1.container_type in [:bag, :bank]))

    assign(socket,
      equipped_items: equipped,
      inventory_items: inventory
    )
  end

  defp load_tab_data(socket, :currencies) do
    character_id = socket.assigns.character.id
    currencies = Inventory.get_currencies(character_id)
    assign(socket, currencies: currencies)
  end

  defp tab_label(:overview), do: "Overview"
  defp tab_label(:inventory), do: "Inventory"
  defp tab_label(:currencies), do: "Currencies"

  defp format_datetime(nil), do: "-"
  defp format_datetime(datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M")

  defp format_number(nil), do: "0"
  defp format_number(n) when is_integer(n) do
    n
    |> Integer.to_string()
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.join(",")
    |> String.reverse()
  end

  # Map legacy numeric IDs to new atom-based currency types
  defp currency_id_to_atom(1), do: :gold
  defp currency_id_to_atom(4), do: :renown
  defp currency_id_to_atom(5), do: :elder_gems
  defp currency_id_to_atom(6), do: :glory
  defp currency_id_to_atom(7), do: :prestige
  defp currency_id_to_atom(8), do: :crafting_vouchers
  defp currency_id_to_atom(9), do: :war_coins
  defp currency_id_to_atom(_), do: nil

  defp maybe_put_float(map, _key, ""), do: map
  defp maybe_put_float(map, _key, nil), do: map
  defp maybe_put_float(map, key, value) do
    case Float.parse(value) do
      {f, _} -> Map.put(map, key, f)
      :error -> map
    end
  end

  defp maybe_put_int(map, _key, ""), do: map
  defp maybe_put_int(map, _key, nil), do: map
  defp maybe_put_int(map, key, value) do
    case Integer.parse(value) do
      {i, ""} -> Map.put(map, key, i)
      _ -> map
    end
  end
end
