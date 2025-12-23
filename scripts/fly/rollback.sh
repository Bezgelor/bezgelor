#!/bin/bash
# Fly.io Rollback Script for Bezgelor
# Rolls back to a previous release

set -e

APP_NAME="bezgelor"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=== Bezgelor Fly.io Rollback ==="
echo ""

# Check flyctl
if ! command -v fly &> /dev/null; then
    echo -e "${RED}Error: flyctl not installed${NC}"
    exit 1
fi

# Get release history
echo "=== Recent Releases ==="
fly releases --app "$APP_NAME" | head -15
echo ""

# Get current release
CURRENT=$(fly releases --app "$APP_NAME" --json | jq -r '.[0].Version')
echo "Current release: v$CURRENT"
echo ""

# Parse arguments
if [ -n "$1" ]; then
    TARGET_VERSION="$1"
else
    # Default to previous release (current - 1)
    TARGET_VERSION=$((CURRENT - 1))
fi

echo -e "${YELLOW}Target rollback version: v$TARGET_VERSION${NC}"
echo ""

# Confirm rollback
echo "This will:"
echo "  1. Deploy release v$TARGET_VERSION"
echo "  2. The current release (v$CURRENT) will remain in history"
echo ""
read -p "Proceed with rollback to v$TARGET_VERSION? [y/N] " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Rollback cancelled."
    exit 0
fi

echo ""
echo "=== Rolling back to v$TARGET_VERSION ==="
echo ""

# Perform rollback
fly releases rollback "$TARGET_VERSION" --app "$APP_NAME"

echo ""
echo -e "${GREEN}=== Rollback Complete ===${NC}"
echo ""

# Wait for deployment
echo "Waiting for rollback to complete..."
sleep 10

# Show new status
echo "=== Current Status ==="
fly status --app "$APP_NAME"
echo ""

# Health check
echo "=== Health Check ==="
HEALTH_URL="https://bezgelor.com/health"
echo "Checking $HEALTH_URL ..."

for i in {1..6}; do
    if curl -sf "$HEALTH_URL" > /dev/null 2>&1; then
        echo -e "${GREEN}Health check passed${NC}"
        curl -s "$HEALTH_URL" | head -c 200
        echo ""
        break
    else
        if [ $i -eq 6 ]; then
            echo -e "${RED}Health check failed after 30s${NC}"
            echo "Check logs: fly logs --app $APP_NAME"
        else
            echo "Waiting... ($i/6)"
            sleep 5
        fi
    fi
done
echo ""

# Show logs
echo "=== Recent Logs ==="
fly logs --app "$APP_NAME" -n 15
echo ""

NEW_VERSION=$(fly releases --app "$APP_NAME" --json | jq -r '.[0].Version')
echo "Rollback complete. Now running: v$NEW_VERSION"
echo ""
echo "If issues persist, check:"
echo "  fly logs --app $APP_NAME"
echo "  fly status --app $APP_NAME"
