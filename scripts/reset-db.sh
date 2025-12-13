#!/bin/bash
# Reset database (drop, create, migrate, seed)
set -e

echo "==> Ensuring PostgreSQL is running..."
docker compose up -d

echo "==> Waiting for database to be ready..."
until docker compose exec -T postgres pg_isready -U bezgelor -d bezgelor_dev > /dev/null 2>&1; do
  sleep 1
done

echo "==> Resetting database..."
mix ecto.reset

echo "Database reset complete."
