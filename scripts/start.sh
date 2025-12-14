#!/bin/bash
# Start all servers with the web portal (interactive)
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

echo "==> Starting Bezgelor servers..."
echo "    Portal:  http://localhost:4000  (localhost only)"
echo "    Auth:    0.0.0.0:6600           (all interfaces)"
echo "    Realm:   0.0.0.0:23115          (all interfaces)"
echo "    World:   0.0.0.0:24000          (all interfaces)"
echo ""
echo "    Logs:    tail -f logs/dev.log"
echo ""

iex -S mix phx.server
