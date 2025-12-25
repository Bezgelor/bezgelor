# Exclude integration tests by default (they need server running)
# Run with `mix test --include integration` to include them
ExUnit.start(exclude: [:integration, :pending_implementation])
