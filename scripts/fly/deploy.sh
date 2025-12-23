#!/bin/bash
# Fly.io Deploy Script for Bezgelor
# Deploys with automatic version tagging from git

set -e

APP_NAME="bezgelor"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=== Bezgelor Fly.io Deploy ==="
echo ""

# Check flyctl
if ! command -v fly &> /dev/null; then
    echo -e "${RED}Error: flyctl not installed${NC}"
    exit 1
fi

# Get version from git
if git describe --tags --always &> /dev/null; then
    VERSION=$(git describe --tags --always)
else
    VERSION=$(git rev-parse --short HEAD)
fi

# Check for uncommitted changes
if ! git diff-index --quiet HEAD -- 2>/dev/null; then
    VERSION="${VERSION}-dirty"
    echo -e "${YELLOW}Warning: Uncommitted changes detected${NC}"
fi

echo "Version: $VERSION"
echo "App:     $APP_NAME"
echo ""

# Confirm deployment
read -p "Deploy version $VERSION to $APP_NAME? [y/N] " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Deployment cancelled."
    exit 0
fi

# Record deployment start
DEPLOY_START=$(date +%s)
echo ""
echo "=== Starting deployment at $(date) ==="
echo ""

# Deploy with version label
fly deploy \
    --app "$APP_NAME" \
    --build-arg "APP_VERSION=$VERSION" \
    --strategy rolling

DEPLOY_END=$(date +%s)
DEPLOY_DURATION=$((DEPLOY_END - DEPLOY_START))

echo ""
echo -e "${GREEN}=== Deployment Complete ===${NC}"
echo ""
echo "Version:  $VERSION"
echo "Duration: ${DEPLOY_DURATION}s"
echo "Time:     $(date)"
echo ""

# Show status
echo "=== Current Status ==="
fly status --app "$APP_NAME"
echo ""

# Health check
echo "=== Health Check ==="
sleep 5  # Wait for instance to be ready
HEALTH_URL="https://bezgelor.com/health"
echo "Checking $HEALTH_URL ..."

if curl -sf "$HEALTH_URL" > /dev/null 2>&1; then
    echo -e "${GREEN}Health check passed${NC}"
    curl -s "$HEALTH_URL" | head -c 200
    echo ""
else
    echo -e "${YELLOW}Health check pending (app may still be starting)${NC}"
    echo "Check manually: curl $HEALTH_URL"
fi
echo ""

# Show recent logs
echo "=== Recent Logs ==="
fly logs --app "$APP_NAME" -n 10
echo ""

echo "Deployment of $VERSION complete."
