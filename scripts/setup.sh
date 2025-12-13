#!/bin/bash
# First-time setup: database + dependencies + migrations
set -e

echo "==> Starting PostgreSQL..."
docker compose up -d

echo "==> Waiting for database to be ready..."
until docker compose exec -T postgres pg_isready -U bezgelor -d bezgelor_dev > /dev/null 2>&1; do
  sleep 1
done

echo "==> Installing dependencies..."
mix deps.get

echo "==> Setting up database..."
mix ecto.setup

echo ""
echo "Setup complete! Run ./scripts/start.sh to start the server."
