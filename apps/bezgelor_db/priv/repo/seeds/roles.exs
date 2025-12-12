# Seed default roles for RBAC system
#
# Run with: mix run priv/repo/seeds/roles.exs
# Or via: mix run priv/repo/seeds.exs (which calls this)
#
# Note: Run permissions.exs first!

alias BezgelorDb.Repo
alias BezgelorDb.Schema.{Permission, Role, RolePermission}
import Ecto.Query

# Define role configurations
roles_config = [
  %{
    name: "Moderator",
    description: "Community management focused - can view users, ban/unban, kick players, broadcast messages",
    protected: true,
    permissions: [
      "users.view",
      "users.ban",
      "users.unban",
      "users.view_login_history",
      "characters.view",
      "events.broadcast_message",
      "server.kick_players",
      "admin.view_audit_log"
    ]
  },
  %{
    name: "Admin",
    description: "Full player support + some server operations - can modify characters, grant items, manage events",
    protected: true,
    permissions: [
      # Moderator permissions
      "users.view",
      "users.ban",
      "users.unban",
      "users.view_login_history",
      "users.reset_password",
      "characters.view",
      "events.broadcast_message",
      "server.kick_players",
      "admin.view_audit_log",
      # Character management
      "characters.modify_items",
      "characters.modify_currency",
      "characters.modify_level",
      "characters.teleport",
      "characters.rename",
      "characters.delete",
      "characters.restore",
      "characters.view_mail",
      "characters.view_trades",
      # Collections
      "collections.grant_achievements",
      "collections.grant_titles",
      "collections.grant_mounts",
      "collections.grant_costumes",
      # Economy
      "economy.grant_currency",
      "economy.grant_items",
      "economy.view_stats",
      "economy.view_transactions",
      # Events
      "events.manage",
      "events.spawn_creatures",
      "events.manage_world_bosses",
      # Instances
      "instances.view",
      "instances.close",
      "instances.reset_lockouts",
      # PvP
      "pvp.view_stats",
      # Server
      "server.view_logs"
    ]
  },
  %{
    name: "Super Admin",
    description: "Everything including role management, server operations, and destructive actions",
    protected: true,
    permissions: :all  # Special marker for all permissions
  }
]

# Get all permission IDs by key
all_permissions = Repo.all(Permission)
permission_map = Map.new(all_permissions, fn p -> {p.key, p.id} end)

now = DateTime.utc_now() |> DateTime.truncate(:second)

Enum.each(roles_config, fn config ->
  # Create or update role
  role =
    case Repo.get_by(Role, name: config.name) do
      nil ->
        %Role{}
        |> Ecto.Changeset.change(%{
          name: config.name,
          description: config.description,
          protected: config.protected,
          inserted_at: now,
          updated_at: now
        })
        |> Repo.insert!()

      existing ->
        existing
        |> Ecto.Changeset.change(%{
          description: config.description,
          protected: config.protected,
          updated_at: now
        })
        |> Repo.update!()
    end

  # Determine which permission IDs to assign
  permission_ids =
    case config.permissions do
      :all ->
        Map.values(permission_map)

      keys when is_list(keys) ->
        Enum.map(keys, fn key ->
          case Map.get(permission_map, key) do
            nil ->
              IO.puts("  Warning: Permission '#{key}' not found for role '#{config.name}'")
              nil

            id ->
              id
          end
        end)
        |> Enum.reject(&is_nil/1)
    end

  # Delete existing role permissions
  from(rp in RolePermission, where: rp.role_id == ^role.id)
  |> Repo.delete_all()

  # Insert new role permissions
  if length(permission_ids) > 0 do
    entries =
      Enum.map(permission_ids, fn permission_id ->
        %{role_id: role.id, permission_id: permission_id}
      end)

    Repo.insert_all(RolePermission, entries)
  end

  IO.puts("Role '#{config.name}': #{length(permission_ids)} permissions assigned")
end)

IO.puts("Roles seeded successfully")
