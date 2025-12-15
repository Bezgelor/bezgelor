# Seed realms for multi-realm support
#
# Creates the default Bezgelor realm and the test Mikros realm.
# Idempotent - safe to run multiple times.

alias BezgelorDb.Repo
alias BezgelorDb.Schema.Realm

IO.puts("Seeding realms...")

realms = [
  %{
    id: 1,
    name: "Bezgelor",
    address: System.get_env("WORLD_PUBLIC_ADDRESS", "127.0.0.1"),
    port: String.to_integer(System.get_env("WORLD_PORT", "24000")),
    type: :pve,
    flags: 0,
    online: false,
    note_text_id: 0
  },
  %{
    id: 2,
    name: "Mikros",
    address: System.get_env("MIKROS_ADDRESS", "127.0.0.1"),
    port: String.to_integer(System.get_env("MIKROS_PORT", "24001")),
    type: :pvp,
    flags: 0,
    online: false,
    note_text_id: 0
  }
]

Enum.each(realms, fn realm_attrs ->
  case Repo.get(Realm, realm_attrs.id) do
    nil ->
      # Insert new realm with specific ID
      %Realm{id: realm_attrs.id}
      |> Realm.changeset(Map.delete(realm_attrs, :id))
      |> Repo.insert!()
      IO.puts("  Created realm: #{realm_attrs.name} (ID: #{realm_attrs.id}, #{realm_attrs.type})")

    existing ->
      # Update existing realm
      existing
      |> Realm.changeset(Map.delete(realm_attrs, :id))
      |> Repo.update!()
      IO.puts("  Updated realm: #{realm_attrs.name} (ID: #{realm_attrs.id}, #{realm_attrs.type})")
  end
end)

IO.puts("Realms seeded: #{length(realms)} realm(s)")
