#!/bin/bash
# Stop all Bezgelor services
set -e

PORTS="6600,4000,4002,23115,24000"

echo "==> Stopping Bezgelor servers..."

# Find processes by port (more reliable than pkill pattern)
pids=$(lsof -ti:$PORTS 2>/dev/null | sort -u || true)

if [ -n "$pids" ]; then
  echo "    Killing PIDs: $pids"
  echo "$pids" | xargs kill 2>/dev/null || true
  sleep 1

  # Force kill if still running
  remaining=$(lsof -ti:$PORTS 2>/dev/null | sort -u || true)
  if [ -n "$remaining" ]; then
    echo "    Force killing: $remaining"
    echo "$remaining" | xargs kill -9 2>/dev/null || true
  fi
else
  echo "    No servers running"
fi

# Also try pkill as fallback for any missed processes
pkill -f "beam.*bezgelor" 2>/dev/null || true

echo ""
echo "==> Stopping PostgreSQL..."
docker compose down 2>/dev/null || true

echo ""
echo "All services stopped."
