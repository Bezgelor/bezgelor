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
  alias BezgelorWorld.Economy.Telemetry

  # 5 seconds - refresh interval for telemetry metrics
  @refresh_interval 5_000

  @impl true
  def mount(_params, _session, socket) do
    socket =
      if connected?(socket) do
        :timer.send_interval(@refresh_interval, self(), :refresh_telemetry)
        socket
      else
        socket
      end

    {:ok,
     socket
     |> assign(
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
       gift_result: nil,
       last_refresh: DateTime.utc_now(),
       telemetry_metrics: load_telemetry_metrics()
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
          :for={tab <- [:overview, :telemetry, :transactions, :gifts]}
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
        <% :telemetry -> %>
          <.telemetry_tab
            metrics={@telemetry_metrics}
            last_refresh={@last_refresh}
            refresh_interval={@refresh_interval}
          />
        <% :transactions -> %>
          <.transactions_tab />
        <% :gifts -> %>
          <.gifts_tab form={@gift_form} result={@gift_result} />
      <% end %>
    </div>
    """
  end

  # Event handlers

  @impl true
  def handle_info(:refresh_telemetry, socket) do
    {:noreply,
     socket
     |> assign(last_refresh: DateTime.utc_now(), telemetry_metrics: load_telemetry_metrics())}
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

  attr :metrics, :map, required: true
  attr :last_refresh, :any, required: true
  attr :refresh_interval, :integer, required: true

  defp telemetry_tab(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Header with auto-refresh indicator -->
      <div class="flex items-center justify-between">
        <div>
          <h2 class="text-lg font-semibold">Economy Telemetry Metrics</h2>
          <p class="text-sm text-base-content/70">Real-time economy activity tracking</p>
        </div>
        <div class="flex items-center gap-4">
          <div class="flex items-center gap-2 text-sm text-base-content/70">
            <span class="loading loading-ring loading-xs"></span>
            <span>Auto-refresh every {div(@refresh_interval, 1000)}s</span>
          </div>
          <span class="text-xs text-base-content/50">
            Last: {Calendar.strftime(@last_refresh, "%H:%M:%S")}
          </span>
        </div>
      </div>

    <!-- Metrics Overview Cards -->
      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        <.metric_card
          title="Currency Transactions"
          value={format_number(@metrics.currency_transactions)}
          icon="hero-currency-dollar"
          color="primary"
        />
        <.metric_card
          title="Vendor Transactions"
          value={format_number(@metrics.vendor_transactions)}
          icon="hero-shopping-bag"
          color="secondary"
        />
        <.metric_card
          title="Loot Drops"
          value={format_number(@metrics.loot_drops)}
          icon="hero-gift"
          color="accent"
        />
        <.metric_card
          title="Trade Completions"
          value={format_number(@metrics.trade_completions)}
          icon="hero-arrow-path-rounded-square"
          color="info"
        />
      </div>

    <!-- Currency Flow Cards -->
      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <.currency_flow_card
          title="Total Currency Gained"
          amount={@metrics.total_currency_gained}
          color="success"
          icon="hero-arrow-trending-up"
        />
        <.currency_flow_card
          title="Total Currency Spent"
          amount={@metrics.total_currency_spent}
          color="error"
          icon="hero-arrow-trending-down"
        />
      </div>

    <!-- Activity Breakdown -->
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <!-- Event Type Distribution -->
        <div class="card bg-base-100 shadow">
          <div class="card-body">
            <h3 class="card-title text-base">Event Type Distribution</h3>
            <div
              id="event-distribution-chart"
              phx-hook="ChartJS"
              phx-update="ignore"
              data-chart-type="doughnut"
              data-chart-config={event_distribution_config(@metrics)}
              class="h-64"
            >
              <canvas></canvas>
            </div>
          </div>
        </div>

      <!-- Additional Metrics -->
        <div class="card bg-base-100 shadow">
          <div class="card-body">
            <h3 class="card-title text-base">Additional Activity</h3>
            <div class="space-y-3">
              <.activity_row
                label="Auction Events"
                value={@metrics.auction_events}
                icon="hero-building-storefront"
              />
              <.activity_row label="Mail Sent" value={@metrics.mail_sent} icon="hero-envelope" />
              <.activity_row
                label="Crafting Completions"
                value={@metrics.crafting_completions}
                icon="hero-wrench-screwdriver"
              />
              <.activity_row
                label="Repair Completions"
                value={@metrics.repair_completions}
                icon="hero-shield-check"
              />
              <.activity_row
                label="Pending Events"
                value={@metrics.pending_events}
                icon="hero-clock"
              />
            </div>
          </div>
        </div>
      </div>

    <!-- System Status -->
      <div class="card bg-base-100 shadow">
        <div class="card-body">
          <h3 class="card-title text-base">Telemetry System Status</h3>
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div>
              <p class="text-sm text-base-content/70">
                <strong>Batch Size:</strong>
                Events are batched and flushed to database when 100 events accumulate or every 5 seconds.
              </p>
            </div>
            <div>
              <p class="text-sm text-base-content/70">
                <strong>Last Flush:</strong>
                <%= if @metrics.last_flush do %>
                  {Calendar.strftime(@metrics.last_flush, "%Y-%m-%d %H:%M:%S UTC")}
                <% else %>
                  <span class="text-warning">Not yet flushed</span>
                <% end %>
              </p>
            </div>
          </div>

        <div class="alert alert-info mt-4">
            <.icon name="hero-information-circle" class="size-5" />
            <div>
              <p class="text-sm">
                Economy telemetry tracks all economic events in real-time including currency transactions,
                vendor purchases, loot drops, trades, auctions, mail, crafting, and repairs.
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :value, :string, required: true
  attr :icon, :string, required: true
  attr :color, :string, default: "primary"

  defp metric_card(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow">
      <div class="card-body p-4">
        <div class="flex items-start justify-between">
          <div>
            <div class="text-2xl font-bold">{@value}</div>
            <div class="text-sm text-base-content/70">{@title}</div>
          </div>
          <div class={"p-2 rounded-lg bg-#{@color}/10"}>
            <.icon name={@icon} class={"size-6 text-#{@color}"} />
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :amount, :integer, required: true
  attr :color, :string, required: true
  attr :icon, :string, required: true

  defp currency_flow_card(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow">
      <div class="card-body p-4">
        <div class="flex items-start justify-between">
          <div>
            <div class="text-2xl font-bold font-mono">{format_currency(@amount)}</div>
            <div class="text-sm text-base-content/70">{@title}</div>
          </div>
          <div class={"p-2 rounded-lg bg-#{@color}/10"}>
            <.icon name={@icon} class={"size-6 text-#{@color}"} />
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :integer, required: true
  attr :icon, :string, required: true

  defp activity_row(assigns) do
    ~H"""
    <div class="flex items-center justify-between">
      <div class="flex items-center gap-2">
        <.icon name={@icon} class="size-4 text-base-content/70" />
        <span class="text-sm text-base-content/70">{@label}</span>
      </div>
      <span class="font-mono font-semibold">{format_number(@value)}</span>
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
  defp tab_label(:telemetry), do: "Telemetry"
  defp tab_label(:transactions), do: "Transactions"
  defp tab_label(:gifts), do: "Gift Tools"

  # Helper functions

  defp load_telemetry_metrics do
    try do
      Telemetry.get_metrics_summary()
    rescue
      _ ->
        # Return default metrics if telemetry server not available
        %{
          currency_transactions: 0,
          vendor_transactions: 0,
          loot_drops: 0,
          auction_events: 0,
          trade_completions: 0,
          mail_sent: 0,
          crafting_completions: 0,
          repair_completions: 0,
          total_currency_gained: 0,
          total_currency_spent: 0,
          last_flush: nil,
          pending_events: 0
        }
    end
  end

  defp event_distribution_config(metrics) do
    Jason.encode!(%{
      labels: [
        "Currency",
        "Vendor",
        "Loot",
        "Auction",
        "Trade",
        "Mail",
        "Crafting",
        "Repair"
      ],
      datasets: [
        %{
          label: "Event Count",
          data: [
            metrics.currency_transactions,
            metrics.vendor_transactions,
            metrics.loot_drops,
            metrics.auction_events,
            metrics.trade_completions,
            metrics.mail_sent,
            metrics.crafting_completions,
            metrics.repair_completions
          ],
          backgroundColor: [
            "rgba(99, 102, 241, 0.8)",
            "rgba(139, 92, 246, 0.8)",
            "rgba(168, 85, 247, 0.8)",
            "rgba(59, 130, 246, 0.8)",
            "rgba(34, 197, 94, 0.8)",
            "rgba(251, 191, 36, 0.8)",
            "rgba(249, 115, 22, 0.8)",
            "rgba(239, 68, 68, 0.8)"
          ],
          borderColor: [
            "rgba(99, 102, 241, 1)",
            "rgba(139, 92, 246, 1)",
            "rgba(168, 85, 247, 1)",
            "rgba(59, 130, 246, 1)",
            "rgba(34, 197, 94, 1)",
            "rgba(251, 191, 36, 1)",
            "rgba(249, 115, 22, 1)",
            "rgba(239, 68, 68, 1)"
          ],
          borderWidth: 1
        }
      ],
      options: %{
        responsive: true,
        maintainAspectRatio: false,
        plugins: %{
          legend: %{
            position: "bottom"
          }
        }
      }
    })
  end

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

  defp format_currency(amount) when is_integer(amount) do
    formatted = format_number(amount)

    cond do
      amount >= 1_000_000_000 -> "#{format_number(div(amount, 1_000_000))}M"
      amount >= 1_000_000 -> "#{format_number(div(amount, 1_000_000))}M"
      amount >= 1_000 -> "#{format_number(div(amount, 1_000))}K"
      true -> formatted
    end
  end

  defp format_currency(_), do: "0"
end
