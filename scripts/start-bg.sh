#!/bin/bash
# Start all servers in background (no interactive shell)
set -e

# Ensure database is running
if ! docker compose ps postgres | grep -q "running"; then
  echo "==> Starting PostgreSQL..."
  docker compose up -d

  echo "==> Waiting for database to be ready..."
  until docker compose exec -T postgres pg_isready -U bezgelor -d bezgelor_dev > /dev/null 2>&1; do
    sleep 1
  done
fi

echo "==> Starting Bezgelor servers in background..."
echo "    Portal:  http://localhost:4001"
echo "    Auth:    localhost:6600"
echo "    Realm:   localhost:23115"
echo "    World:   localhost:24000"
echo ""

MIX_ENV=dev elixir --erl "-detached" -S mix phx.server

echo "Servers started in background. Use ./scripts/stop.sh to stop."
