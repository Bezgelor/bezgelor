#!/bin/bash
# Stop all services
set -e

echo "==> Stopping Elixir processes..."
pkill -f "beam.*bezgelor" 2>/dev/null || true

echo "==> Stopping PostgreSQL..."
docker compose down

echo "All services stopped."
