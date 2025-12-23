defmodule BezgelorPortal.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end

    # Run essential seeds after migrations
    seed()
  end

  def seed do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, fn _repo -> run_seeds() end)
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    # Database is in bezgelor_db umbrella app
    Application.fetch_env!(:bezgelor_db, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(:bezgelor_db)
  end

  # Essential seeds that must exist for the server to function
  defp run_seeds do
    seed_realms()
    seed_permissions()
    seed_roles()
  end

  defp seed_realms do
    alias BezgelorDb.Repo
    alias BezgelorDb.Schema.Realm

    IO.puts("Seeding realms...")

    realm_attrs = %{
      name: "Bezgelor",
      address: System.get_env("WORLD_PUBLIC_ADDRESS", "127.0.0.1"),
      port: String.to_integer(System.get_env("WORLD_PORT", "24000")),
      type: :pve,
      flags: 0,
      online: false,
      note_text_id: 0
    }

    case Repo.get(Realm, 1) do
      nil ->
        %Realm{id: 1}
        |> Realm.changeset(realm_attrs)
        |> Repo.insert!()
        IO.puts("  Created realm: Bezgelor (ID: 1)")

      existing ->
        existing
        |> Realm.changeset(realm_attrs)
        |> Repo.update!()
        IO.puts("  Updated realm: Bezgelor (ID: 1)")
    end
  end

  defp seed_permissions do
    alias BezgelorDb.Repo
    alias BezgelorDb.Schema.Permission

    IO.puts("Seeding permissions...")

    permissions = [
      %{key: "admin.dashboard", category: "admin", description: "Access admin dashboard"},
      %{key: "admin.accounts", category: "admin", description: "Manage user accounts"},
      %{key: "admin.characters", category: "admin", description: "Manage characters"},
      %{key: "admin.realms", category: "admin", description: "Manage realms"},
      %{key: "admin.audit", category: "admin", description: "View audit logs"},
      %{key: "admin.economy", category: "admin", description: "Manage economy settings"}
    ]

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Enum.each(permissions, fn attrs ->
      case Repo.get_by(Permission, key: attrs.key) do
        nil ->
          Repo.insert!(%Permission{
            key: attrs.key,
            category: attrs.category,
            description: attrs.description,
            inserted_at: now,
            updated_at: now
          })

        _existing ->
          :ok
      end
    end)

    IO.puts("  Permissions seeded")
  end

  defp seed_roles do
    alias BezgelorDb.Repo
    alias BezgelorDb.Schema.{Role, Permission, RolePermission}

    IO.puts("Seeding roles...")

    # Create admin role
    admin_role =
      case Repo.get_by(Role, name: "admin") do
        nil ->
          %Role{}
          |> Role.changeset(%{name: "admin", description: "Full administrator access", protected: true})
          |> Repo.insert!()

        existing ->
          existing
      end

    # Assign all permissions to admin role
    all_permissions = Repo.all(Permission)

    Enum.each(all_permissions, fn permission ->
      case Repo.get_by(RolePermission, role_id: admin_role.id, permission_id: permission.id) do
        nil ->
          Repo.insert!(%RolePermission{
            role_id: admin_role.id,
            permission_id: permission.id
          })

        _existing ->
          :ok
      end
    end)

    IO.puts("  Roles seeded")
  end
end
