# Seed permissions for RBAC system
#
# Run with: mix run priv/repo/seeds/permissions.exs
# Or via: mix run priv/repo/seeds.exs (which calls this)

alias BezgelorDb.Repo
alias BezgelorDb.Schema.Permission

permissions = [
  # User Management
  %{key: "users.view", category: "user_management", description: "Search and view account details"},
  %{key: "users.reset_password", category: "user_management", description: "Generate password reset or force new password"},
  %{key: "users.ban", category: "user_management", description: "Ban or suspend accounts"},
  %{key: "users.unban", category: "user_management", description: "Lift bans and suspensions"},
  %{key: "users.view_login_history", category: "user_management", description: "View IP addresses and login timestamps"},
  %{key: "users.impersonate", category: "user_management", description: "View-only impersonation"},

  # Character Management
  %{key: "characters.view", category: "character_management", description: "View character details, inventory, currency"},
  %{key: "characters.modify_items", category: "character_management", description: "Add/remove items from inventory"},
  %{key: "characters.modify_currency", category: "character_management", description: "Add/subtract currency"},
  %{key: "characters.modify_level", category: "character_management", description: "Set level, add XP"},
  %{key: "characters.teleport", category: "character_management", description: "Move character to location"},
  %{key: "characters.rename", category: "character_management", description: "Force name change"},
  %{key: "characters.delete", category: "character_management", description: "Soft delete characters"},
  %{key: "characters.restore", category: "character_management", description: "Restore deleted characters"},
  %{key: "characters.view_mail", category: "character_management", description: "View sent/received mail"},
  %{key: "characters.view_trades", category: "character_management", description: "View trade history"},

  # Achievements & Collections
  %{key: "collections.grant_achievements", category: "collections", description: "Unlock achievements"},
  %{key: "collections.grant_titles", category: "collections", description: "Unlock titles"},
  %{key: "collections.grant_mounts", category: "collections", description: "Add mounts to collection"},
  %{key: "collections.grant_costumes", category: "collections", description: "Unlock costume pieces"},

  # Economy
  %{key: "economy.grant_currency", category: "economy", description: "Gift gold or other currencies"},
  %{key: "economy.grant_items", category: "economy", description: "Send items via system mail"},
  %{key: "economy.view_stats", category: "economy", description: "View gold circulation, sinks/faucets"},
  %{key: "economy.view_transactions", category: "economy", description: "View gold transfers, sales"},
  %{key: "economy.rollback_transactions", category: "economy", description: "Reverse specific transactions"},

  # Events & Content
  %{key: "events.manage", category: "events", description: "Start/stop public events"},
  %{key: "events.spawn_creatures", category: "events", description: "Spawn creatures at location"},
  %{key: "events.broadcast_message", category: "events", description: "Server-wide announcements"},
  %{key: "events.schedule_maintenance", category: "events", description: "Set maintenance windows"},
  %{key: "events.manage_world_bosses", category: "events", description: "Force spawn, reset timers"},

  # Instances
  %{key: "instances.view", category: "instances", description: "View active dungeon/raid instances"},
  %{key: "instances.close", category: "instances", description: "Force close instances"},
  %{key: "instances.reset_lockouts", category: "instances", description: "Clear raid/dungeon lockouts"},

  # PvP
  %{key: "pvp.view_stats", category: "pvp", description: "View arena teams, battleground stats"},
  %{key: "pvp.reset_ratings", category: "pvp", description: "Reset ratings for team or player"},
  %{key: "pvp.ban", category: "pvp", description: "Temporary PvP ban"},

  # Server Operations
  %{key: "server.maintenance_mode", category: "server", description: "Enable/disable maintenance"},
  %{key: "server.restart_zones", category: "server", description: "Reload specific zone instances"},
  %{key: "server.reload_data", category: "server", description: "Hot-reload game data from ETS"},
  %{key: "server.kick_players", category: "server", description: "Force disconnect players"},
  %{key: "server.view_logs", category: "server", description: "View recent errors/warnings"},

  # Administration
  %{key: "admin.manage_roles", category: "administration", description: "Create/edit/delete roles"},
  %{key: "admin.assign_roles", category: "administration", description: "Assign roles to users"},
  %{key: "admin.view_audit_log", category: "administration", description: "View admin action history"},
  %{key: "admin.export_audit_log", category: "administration", description: "Download audit logs"},

  # Account Features
  %{key: "account.signature", category: "account_features", description: "Signature tier account (premium features, extra slots)"},

  # Testing Tools (development/QA)
  %{key: "testing.manage", category: "testing", description: "Access testing tools for character creation and deletion"}
]

now = DateTime.utc_now() |> DateTime.truncate(:second)

# Insert permissions idempotently
{inserted, updated} =
  Enum.reduce(permissions, {0, 0}, fn perm, {ins, upd} ->
    attrs = Map.merge(perm, %{inserted_at: now, updated_at: now})

    case Repo.insert(
           %Permission{}
           |> Ecto.Changeset.change(attrs),
           on_conflict: {:replace, [:description, :category, :updated_at]},
           conflict_target: :key
         ) do
      {:ok, %{__meta__: %{state: :loaded}}} -> {ins, upd + 1}
      {:ok, _} -> {ins + 1, upd}
      {:error, _} -> {ins, upd}
    end
  end)

IO.puts("Permissions: #{inserted} inserted, #{updated} updated")
