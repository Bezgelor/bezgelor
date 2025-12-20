defmodule BezgelorPortalWeb.Admin.EconomyLive do
  @moduledoc """
  Admin LiveView for economy overview and management.

  Features:
  - Economy statistics overview
  - Transaction log viewer
  - Gift/grant tools for currency and items

  Note: Full economy tracking is not yet implemented.
  This provides the UI framework for when the backend is ready.
  """
  use BezgelorPortalWeb, :live_view

  alias BezgelorDb.{Authorization, Characters, Inventory}
  alias BezgelorDb.Mail

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Economy Management",
       active_tab: :overview,
       # Gift form state
       gift_form: %{
         "recipient_type" => "character",
         "recipient" => "",
         "gift_type" => "item",
         "item_id" => "",
         "quantity" => "1",
         "currency_type" => "1",
         "amount" => "",
         "reason" => ""
       },
       gift_result: nil
     ), layout: {BezgelorPortalWeb.Layouts, :admin}}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div>
        <h1 class="text-2xl font-bold">Economy Management</h1>
        <p class="text-base-content/70">Monitor and manage game economy</p>
      </div>
      
    <!-- Tabs -->
      <div role="tablist" class="tabs tabs-boxed bg-base-100 p-1 w-fit">
        <button
          :for={tab <- [:overview, :transactions, :gifts]}
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
      <%= case @active_tab do %>
        <% :overview -> %>
          <.overview_tab />
        <% :transactions -> %>
          <.transactions_tab />
        <% :gifts -> %>
          <.gifts_tab form={@gift_form} result={@gift_result} />
      <% end %>
    </div>
    """
  end

  # Tab components

  defp overview_tab(assigns) do
    ~H"""
    <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
      <.stat_card
        title="Total Gold in Circulation"
        value="--"
        subtitle="Not yet tracked"
        icon="hero-currency-dollar"
      />
      <.stat_card
        title="Daily Gold Generated"
        value="--"
        subtitle="Quest rewards, loot, etc."
        icon="hero-arrow-trending-up"
      />
      <.stat_card
        title="Daily Gold Removed"
        value="--"
        subtitle="Repairs, vendors, AH fees"
        icon="hero-arrow-trending-down"
      />
      <.stat_card
        title="Active Auction House Listings"
        value="--"
        subtitle="Not yet implemented"
        icon="hero-shopping-cart"
      />
    </div>

    <div class="card bg-base-100 shadow mt-6">
      <div class="card-body">
        <h2 class="card-title">Economy Tracking</h2>
        <div class="alert alert-info">
          <.icon name="hero-information-circle" class="size-5" />
          <div>
            <h3 class="font-bold">Coming Soon</h3>
            <p class="text-sm">
              Economy tracking will provide real-time insights into gold flow,
              including charts for trends over time, top gold holders, and
              detection of unusual economic activity.
            </p>
          </div>
        </div>

        <div class="mt-4">
          <h3 class="font-semibold mb-2">Planned Features:</h3>
          <ul class="list-disc list-inside text-sm text-base-content/70 space-y-1">
            <li>Real-time gold circulation tracking</li>
            <li>Daily/weekly/monthly trend charts</li>
            <li>Gold sources breakdown (quests, loot, mail, trades)</li>
            <li>Gold sinks breakdown (repairs, vendors, AH fees)</li>
            <li>Top gold holders leaderboard</li>
            <li>Unusual activity detection</li>
          </ul>
        </div>
      </div>
    </div>
    """
  end

  defp transactions_tab(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow">
      <div class="card-body">
        <h2 class="card-title">Transaction Log</h2>
        <div class="alert alert-info">
          <.icon name="hero-information-circle" class="size-5" />
          <div>
            <h3 class="font-bold">Not Yet Implemented</h3>
            <p class="text-sm">
              The transaction log will allow searching and filtering all economic
              transactions in the game, including trades, mail, vendors, and
              auction house activity.
            </p>
          </div>
        </div>

        <div class="mt-4">
          <h3 class="font-semibold mb-2">Planned Search Filters:</h3>
          <ul class="list-disc list-inside text-sm text-base-content/70 space-y-1">
            <li>By account or character</li>
            <li>By transaction type (trade, mail, vendor, AH, quest, loot)</li>
            <li>By amount range</li>
            <li>By date range</li>
            <li>By item involved</li>
          </ul>
        </div>
        
    <!-- Placeholder search form -->
        <div class="mt-6 opacity-50 pointer-events-none">
          <form class="flex flex-wrap gap-4 items-end">
            <div class="form-control">
              <label class="label"><span class="label-text">Character</span></label>
              <input
                type="text"
                class="input input-bordered input-sm"
                placeholder="Character name"
                disabled
              />
            </div>
            <div class="form-control">
              <label class="label"><span class="label-text">Type</span></label>
              <select class="select select-bordered select-sm" disabled>
                <option>All Types</option>
              </select>
            </div>
            <div class="form-control">
              <label class="label"><span class="label-text">Min Amount</span></label>
              <input type="number" class="input input-bordered input-sm" disabled />
            </div>
            <div class="form-control">
              <label class="label"><span class="label-text">Max Amount</span></label>
              <input type="number" class="input input-bordered input-sm" disabled />
            </div>
            <button type="button" class="btn btn-primary btn-sm" disabled>Search</button>
          </form>
        </div>
      </div>
    </div>
    """
  end

  attr :form, :map, required: true
  attr :result, :map

  defp gifts_tab(assigns) do
    ~H"""
    <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
      <!-- Gift Form -->
      <div class="card bg-base-100 shadow">
        <div class="card-body">
          <h2 class="card-title">Send Gift</h2>
          <p class="text-sm text-base-content/70 mb-4">
            Send items or currency to a character. All gifts are logged to the audit log.
          </p>

          <form phx-submit="send_gift" class="space-y-4">
            <!-- Recipient -->
            <div class="form-control">
              <label class="label">
                <span class="label-text">Recipient Character Name</span>
              </label>
              <input
                type="text"
                name="recipient"
                value={@form["recipient"]}
                class="input input-bordered"
                placeholder="Enter character name"
                required
              />
            </div>
            
    <!-- Gift Type -->
            <div class="form-control">
              <label class="label">
                <span class="label-text">Gift Type</span>
              </label>
              <select name="gift_type" class="select select-bordered" phx-change="update_gift_type">
                <option value="item" selected={@form["gift_type"] == "item"}>Item</option>
                <option value="currency" selected={@form["gift_type"] == "currency"}>Currency</option>
              </select>
            </div>
            
    <!-- Item fields -->
            <div :if={@form["gift_type"] == "item"} class="space-y-4">
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
            </div>
            
    <!-- Currency fields -->
            <div :if={@form["gift_type"] == "currency"} class="space-y-4">
              <div class="form-control">
                <label class="label">
                  <span class="label-text">Currency Type</span>
                </label>
                <select name="currency_type" class="select select-bordered">
                  <option value="1">Gold</option>
                  <option value="5">Elder Gems</option>
                  <option value="4">Renown</option>
                  <option value="7">Prestige</option>
                  <option value="6">Glory</option>
                  <option value="8">Crafting Vouchers</option>
                  <option value="9">War Coins</option>
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
              </div>
            </div>
            
    <!-- Reason -->
            <div class="form-control">
              <label class="label">
                <span class="label-text">Reason (for audit log)</span>
              </label>
              <input
                type="text"
                name="reason"
                value={@form["reason"]}
                class="input input-bordered"
                placeholder="e.g., Bug compensation, Event reward"
              />
            </div>

            <button type="submit" class="btn btn-primary w-full">
              <.icon name="hero-gift" class="size-4" /> Send Gift
            </button>
          </form>
          
    <!-- Result message -->
          <div
            :if={@result}
            class={"alert mt-4 #{if @result.success, do: "alert-success", else: "alert-error"}"}
          >
            <.icon
              name={if @result.success, do: "hero-check-circle", else: "hero-x-circle"}
              class="size-5"
            />
            <span>{@result.message}</span>
          </div>
        </div>
      </div>
      
    <!-- Recent Gifts -->
      <div class="card bg-base-100 shadow">
        <div class="card-body">
          <h2 class="card-title">Recent Admin Gifts</h2>
          <p class="text-sm text-base-content/70">
            View recent gifts sent by administrators in the <.link
              navigate={~p"/admin/audit-log?action=character.grant*"}
              class="link link-primary"
            >
              audit log
            </.link>.
          </p>

          <div class="alert alert-info mt-4">
            <.icon name="hero-information-circle" class="size-5" />
            <span>All gifts are logged with admin ID, recipient, items/currency, and reason.</span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :value, :string, required: true
  attr :subtitle, :string, default: nil
  attr :icon, :string, required: true

  defp stat_card(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow">
      <div class="card-body">
        <div class="flex items-center gap-3">
          <div class="p-3 bg-primary/10 rounded-lg">
            <.icon name={@icon} class="size-6 text-primary" />
          </div>
          <div>
            <div class="text-2xl font-bold">{@value}</div>
            <div class="text-sm text-base-content/70">{@title}</div>
            <div :if={@subtitle} class="text-xs text-base-content/50">{@subtitle}</div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Event handlers

  @impl true
  def handle_event("change_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, active_tab: String.to_existing_atom(tab))}
  end

  @impl true
  def handle_event("update_gift_type", %{"gift_type" => gift_type}, socket) do
    form = Map.put(socket.assigns.gift_form, "gift_type", gift_type)
    {:noreply, assign(socket, gift_form: form)}
  end

  @impl true
  def handle_event("send_gift", params, socket) do
    admin = socket.assigns.current_account
    recipient_name = params["recipient"]
    gift_type = params["gift_type"]
    reason = params["reason"] || "Admin gift"

    case Characters.get_character_by_name(recipient_name) do
      nil ->
        {:noreply,
         assign(socket,
           gift_result: %{success: false, message: "Character not found: #{recipient_name}"}
         )}

      character ->
        result = send_gift(admin, character, gift_type, params, reason)
        {:noreply, assign(socket, gift_result: result)}
    end
  end

  defp send_gift(admin, character, "item", params, reason) do
    with {item_id, ""} <- Integer.parse(params["item_id"] || ""),
         {quantity, ""} <- Integer.parse(params["quantity"] || "1") do
      case Mail.send_system_mail(
             character.id,
             "Admin Gift",
             "You have received a gift from an administrator. Reason: #{reason}",
             attachments: [{item_id, quantity}]
           ) do
        {:ok, _} ->
          Authorization.log_action(admin, "character.grant_item", "character", character.id, %{
            item_id: item_id,
            quantity: quantity,
            reason: reason
          })

          %{success: true, message: "Sent #{quantity}x Item ##{item_id} to #{character.name}"}

        {:error, _} ->
          %{success: false, message: "Failed to send mail"}
      end
    else
      _ -> %{success: false, message: "Invalid item ID or quantity"}
    end
  end

  defp send_gift(admin, character, "currency", params, reason) do
    with {currency_id, ""} <- Integer.parse(params["currency_type"] || ""),
         {amount, ""} <- Integer.parse(params["amount"] || ""),
         currency_type when not is_nil(currency_type) <- currency_id_to_atom(currency_id) do
      case Inventory.modify_currency(character.id, currency_type, amount) do
        {:ok, _} ->
          Authorization.log_action(
            admin,
            "character.grant_currency",
            "character",
            character.id,
            %{
              currency_type: currency_type,
              amount: amount,
              reason: reason
            }
          )

          currency_name =
            currency_type |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize()

          %{success: true, message: "Granted #{amount} #{currency_name} to #{character.name}"}

        {:error, :insufficient_funds} ->
          %{success: false, message: "Insufficient funds - cannot remove more than character has"}

        {:error, :invalid_currency} ->
          %{success: false, message: "Invalid currency type"}

        {:error, _} ->
          %{success: false, message: "Failed to modify currency"}
      end
    else
      nil -> %{success: false, message: "Unknown currency type"}
      _ -> %{success: false, message: "Invalid currency type or amount"}
    end
  end

  # Map legacy numeric IDs to atom-based currency types
  defp currency_id_to_atom(1), do: :gold
  defp currency_id_to_atom(4), do: :renown
  defp currency_id_to_atom(5), do: :elder_gems
  defp currency_id_to_atom(6), do: :glory
  defp currency_id_to_atom(7), do: :prestige
  defp currency_id_to_atom(8), do: :crafting_vouchers
  defp currency_id_to_atom(9), do: :war_coins
  defp currency_id_to_atom(_), do: nil

  defp tab_label(:overview), do: "Overview"
  defp tab_label(:transactions), do: "Transactions"
  defp tab_label(:gifts), do: "Gift Tools"
end
