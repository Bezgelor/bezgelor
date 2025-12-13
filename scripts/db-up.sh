#!/bin/bash
# Start just the database
set -e

echo "==> Starting PostgreSQL..."
docker compose up -d

echo "==> Waiting for database to be ready..."
until docker compose exec -T postgres pg_isready -U bezgelor -d bezgelor_dev > /dev/null 2>&1; do
  sleep 1
done

echo "PostgreSQL is ready on port 5433."
