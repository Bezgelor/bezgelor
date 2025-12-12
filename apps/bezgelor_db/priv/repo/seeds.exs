# Main seed file - runs all seeds in order
#
# Run with: mix run priv/repo/seeds.exs
#
# Seeds are idempotent and safe to run multiple times.

IO.puts("=== Bezgelor Database Seeds ===\n")

seeds_dir = Path.join([__DIR__, "seeds"])

# Define seed files in order of execution
seed_files = [
  "permissions.exs",
  "roles.exs"
]

Enum.each(seed_files, fn file ->
  path = Path.join(seeds_dir, file)

  if File.exists?(path) do
    IO.puts("Running #{file}...")
    Code.eval_file(path)
    IO.puts("")
  else
    IO.puts("Warning: #{file} not found, skipping")
  end
end)

IO.puts("=== Seeds complete ===")
