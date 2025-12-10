defmodule BezgelorDb.Repo.Migrations.FixVerifierColumnSize do
  use Ecto.Migration

  def change do
    # Verifier is 128 bytes hex-encoded = 256 characters
    # Salt is 16 bytes hex-encoded = 32 characters (already fits in 255)
    alter table(:accounts) do
      modify :verifier, :text, from: :string
    end
  end
end
